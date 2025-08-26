import requests
from bs4 import BeautifulSoup
import boto3
import hashlib
import os
import re
from typing import Optional, Dict, Tuple
from urllib.parse import urljoin, urlparse
from botocore.exceptions import ClientError
from datetime import datetime
from dotenv import load_dotenv

# .env 파일 로드
load_dotenv()

class ImageExtractor:
    def __init__(self):
        self.s3_client = None
        self.s3_bucket = os.getenv("S3_BUCKET_NAME", "news-service-dev-images-236528210774")
        self.cloudfront_domain = os.getenv("CLOUDFRONT_DOMAIN", "https://d2hpi3mpmg4l2t.cloudfront.net")
        self.distribution_id = os.getenv("CLOUDFRONT_DISTRIBUTION_ID", "E2YK8FLDYXXCB4")
        
        # S3 클라이언트 초기화 (간소화된 로그)
        if self.s3_bucket:
            try:
                self.s3_client = boto3.client(
                    's3',
                    region_name=os.getenv("AWS_REGION", "ap-northeast-2")
                )
                print(f"✅ S3 서비스 준비 완료")
            except Exception as e:
                print(f"⚠️  S3 초기화 실패: {str(e)[:50]}...")
                self.s3_client = None
        else:
            print("⚠️  S3 미설정 - 이미지 업로드 비활성화")
    
    def extract_image_from_article(self, article_url: str) -> Optional[str]:
        """뉴스 기사 URL에서 이미지 URL을 추출"""
        try:
            # User-Agent 헤더 추가하여 크롤링 차단 방지
            headers = {
                'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36'
            }
            
            # 기사 페이지 가져오기
            response = requests.get(article_url, headers=headers, timeout=10)
            response.raise_for_status()
            
            # BeautifulSoup으로 HTML 파싱
            soup = BeautifulSoup(response.content, 'html.parser')
            
            # 이미지 추출 시도 (여러 패턴)
            image_url = None
            
            # 1. 일반적인 기사 이미지 태그들
            img_patterns = [
                # 메타 태그의 og:image (가장 우선)
                soup.find('meta', {'property': 'og:image'}),
                # 트위터 카드 이미지
                soup.find('meta', {'name': 'twitter:image'}),
                # 일반 img 태그 (기사 관련)
                soup.find('img', {'class': re.compile(r'.*article.*|.*news.*|.*content.*|.*photo.*', re.I)}),
                # 첫 번째 본문 이미지
                soup.find('div', {'class': re.compile(r'.*article.*|.*content.*|.*body.*', re.I)}).find('img') if soup.find('div', {'class': re.compile(r'.*article.*|.*content.*|.*body.*', re.I)}) else None,
                # 단순히 첫 번째 img 태그
                soup.find('img')
            ]
            
            for img_tag in img_patterns:
                if img_tag:
                    src = None
                    if img_tag.name == 'img':
                        # img 태그에서 src 추출
                        src = img_tag.get('src') or img_tag.get('data-src') or img_tag.get('data-original')
                    elif img_tag.name == 'meta':
                        # meta 태그에서 content 추출
                        src = img_tag.get('content')
                    
                    if src:
                        # 상대 URL을 절대 URL로 변환
                        if src.startswith('//'):
                            image_url = 'https:' + src
                        elif src.startswith('/'):
                            image_url = urljoin(article_url, src)
                        elif src.startswith('http'):
                            image_url = src
                        else:
                            continue
                        
                        # 유효한 이미지 URL인지 확인
                        if image_url and any(ext in image_url.lower() for ext in ['.jpg', '.jpeg', '.png', '.gif', '.webp']):
                            return image_url
            
            return None
            
        except requests.RequestException:
            return None
        except Exception:
            return None
    
    def download_image(self, image_url: str) -> Optional[Tuple[bytes, str, str]]:
        """이미지 다운로드 및 기본 검증"""
        try:
            # User-Agent 헤더 추가
            headers = {
                'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36'
            }
            
            # 이미지 다운로드
            response = requests.get(image_url, headers=headers, timeout=30, stream=True)
            response.raise_for_status()
            
            # 콘텐츠 타입 확인
            content_type = response.headers.get('content-type', '')
            if not content_type.startswith('image/'):
                return None
            
            # 이미지 크기 검증
            content_length = response.headers.get('content-length')
            if content_length:
                size_mb = int(content_length) / (1024 * 1024)
                if size_mb > 10:  # 10MB 제한
                    return None
            
            # 파일 확장자 결정
            if 'jpeg' in content_type or 'jpg' in content_type:
                ext = '.jpg'
            elif 'png' in content_type:
                ext = '.png'
            elif 'gif' in content_type:
                ext = '.gif'
            elif 'webp' in content_type:
                ext = '.webp'
            else:
                # URL에서 확장자 추출 시도
                parsed_url = urlparse(image_url)
                path = parsed_url.path.lower()
                if any(path.endswith(e) for e in ['.jpg', '.jpeg', '.png', '.gif', '.webp']):
                    ext = '.' + path.split('.')[-1]
                else:
                    ext = '.jpg'  # 기본값
            
            # 이미지 데이터 읽기
            image_data = response.content
            return (image_data, content_type, ext)
            
        except Exception:
            return None
    
    def upload_to_s3_and_get_url(self, image_data: bytes, s3_key: str, content_type: str, original_url: str, id: str) -> Dict:
        """S3 업로드 및 CloudFront URL 생성"""
        try:
            # S3에 업로드
            self.s3_client.put_object(
                Bucket=self.s3_bucket,
                Key=s3_key,
                Body=image_data,
                ContentType=content_type,
                CacheControl='max-age=31536000',  # 1년 캐시
                Metadata={
                    'original_url': original_url,
                    'uploaded_at': datetime.now().isoformat(),
                    'news_id': id,
                    'environment': os.getenv('ENVIRONMENT', 'dev')
                }
            )
            
            # CloudFront URL 생성
            cloudfront_url = f"{self.cloudfront_domain.rstrip('/')}/{s3_key}"
            
            return {
                's3_key': s3_key,
                'cloudfront_url': cloudfront_url,
                'original_url': original_url
            }
            
        except Exception as e:
            print(f"❌ S3 업로드 실패: {str(e)[:50]}...")
            raise e
    
    def process_news_image(self, article_url: str, id: str) -> Optional[Dict]:
        """전체 프로세스 조합: 추출 → 다운로드 → 업로드 → URL 생성"""
        if not self.s3_client or not self.s3_bucket:
            return None
        
        try:
            # 1. 이미지 URL 추출
            image_url = self.extract_image_from_article(article_url)
            if not image_url:
                return None
            
            # 2. 이미지 다운로드 및 검증
            download_result = self.download_image(image_url)
            if not download_result:
                return None
            
            image_data, content_type, ext = download_result
            
            # 3. S3 키 생성: {id}/images/이미지파일명
            image_hash = hashlib.md5(image_url.encode()).hexdigest()[:12]
            s3_key = f"{id}/images/{image_hash}{ext}"
            
            # 4. S3 업로드 및 CloudFront URL 생성
            return self.upload_to_s3_and_get_url(image_data, s3_key, content_type, image_url, id)
            
        except Exception:
            return None
    
    def invalidate_cloudfront_cache(self, s3_key: str) -> bool:
        """CloudFront 캐시 무효화 (선택사항)"""
        try:
            if not self.distribution_id:
                return False
                
            cloudfront_client = boto3.client('cloudfront', region_name='us-east-1')  # CloudFront는 us-east-1 사용
            
            response = cloudfront_client.create_invalidation(
                DistributionId=self.distribution_id,
                InvalidationBatch={
                    'Paths': {
                        'Quantity': 1,
                        'Items': [f'/{s3_key}']
                    },
                    'CallerReference': f"{s3_key}-{datetime.now().timestamp()}"
                }
            )
            
            return True
            
        except Exception:
            return False

# 전역 인스턴스
image_extractor = ImageExtractor()
import json
import requests
import os
from datetime import datetime
import boto3
from botocore.exceptions import ClientError
import uuid
from bs4 import BeautifulSoup
import re
from urllib.parse import urlparse
import hashlib

def lambda_handler(event, context):
    """
    AWS Lambda 함수: 네이버 뉴스 수집 및 DynamoDB 저장
    """
    
    # 네이버 API 설정 (환경 변수에서 가져오기)
    NAVER_CLIENT_ID = os.environ.get('NAVER_CLIENT_ID')
    NAVER_CLIENT_SECRET = os.environ.get('NAVER_CLIENT_SECRET')
    
    # 필수 환경 변수 검증
    if not NAVER_CLIENT_ID or not NAVER_CLIENT_SECRET:
        print("⚠️ 네이버 API 키가 설정되지 않았습니다.")
        return {
            'statusCode': 500,
            'body': {
                'message': '환경 변수 설정 오류',
                'error': 'NAVER_CLIENT_ID 또는 NAVER_CLIENT_SECRET가 설정되지 않았습니다.'
            }
        }
    
    # DynamoDB 설정 (오사카 리전)
    dynamodb = boto3.resource('dynamodb', region_name='ap-northeast-3')
    table = dynamodb.Table('ioi_contents_table')
    
    # S3 설정 (오사카 리전)
    s3_client = boto3.client('s3', region_name='ap-northeast-3')
    S3_BUCKET = 'ioi-contents-bukket'
    
    # CloudFront 도메인 
    CLOUDFRONT_DOMAIN = os.environ.get('CLOUDFRONT_DOMAIN', 'https://d3nvut5aamy17o.cloudfront.net')
    
    print(f"🔧 설정 확인:")
    print(f"  - S3 버킷: {S3_BUCKET}")
    print(f"  - CloudFront 도메인: {CLOUDFRONT_DOMAIN}")
    print(f"  - DynamoDB 테이블: ioi_contents_table")
    print(f"  - 리전: ap-northeast-3 (오사카)")
    
    # 검색할 키워드들
    keywords = [
        "비트코인"
    ]
    
    # 결과 저장용
    collected_news = []
    
    # 네이버 뉴스 검색 API URL
    url = "https://openapi.naver.com/v1/search/news.json"
    
    # 요청 헤더
    headers = {
        'X-Naver-Client-Id': NAVER_CLIENT_ID,
        'X-Naver-Client-Secret': NAVER_CLIENT_SECRET,
        'Content-Type': 'application/json'
    }
    
    print(f"=== 네이버 뉴스 수집 시작 ===")
    print(f"수집 시간: {datetime.now().isoformat()}")
    print(f"검색 키워드: {keywords}")
    
    total_collected = 0
    
    for keyword in keywords:
        print(f"\n--- '{keyword}' 키워드로 뉴스 수집 중 ---")
        
        # 요청 파라미터
        params = {
            'query': keyword,
            'display': 50,  # 10개씩 수집
            'start': 1,
            'sort': 'date'  # 최신순
        }
        
        try:
            # API 요청
            response = requests.get(url, params=params, headers=headers)
            
            if response.status_code == 200:
                data = response.json()
                items = data.get('items', [])
                
                print(f"'{keyword}': {len(items)}개 뉴스 수집됨")
                
                # 뉴스 데이터 정리 및 DynamoDB 저장
                for item in items:
                    # 날짜 기반 uid 생성 (소팅용)
                    now = datetime.now()
                    uid = now.strftime('%Y%m%d_%H%M%S_') + str(uuid.uuid4())[:8]
                    
                    # HTML 태그 제거 함수
                    def clean_html_tags(text):
                        import re
                        clean = re.compile('<.*?>')
                        return re.sub(clean, '', text)
                    
                    # 원본 링크에서 이미지 URL 추출 및 S3 업로드
                    original_link = item.get('originallink', '')
                    image_data = None
                    cloudfront_url = None
                    s3_key = None
                    
                    if original_link:
                        print(f"  📸 이미지 추출 시도: {original_link}")
                        extracted_image_url = extract_image_from_article(original_link)
                        
                        if extracted_image_url:
                            print(f"  ✓ 이미지 URL 추출 성공: {extracted_image_url}")
                            
                            # S3에 이미지 업로드
                            print(f"  📤 S3 업로드 시도...")
                            image_data = download_and_upload_image_to_s3(
                                extracted_image_url, 
                                uid, 
                                s3_client, 
                                S3_BUCKET, 
                                CLOUDFRONT_DOMAIN
                            )
                            
                            if image_data:
                                cloudfront_url = image_data['cloudfront_url']
                                s3_key = image_data['s3_key']
                                print(f"  ✓ S3 업로드 성공!")
                                print(f"  🌐 CloudFront URL: {cloudfront_url}")
                            else:
                                print(f"  ✗ S3 업로드 실패")
                        else:
                            print(f"  ✗ 이미지 URL 추출 실패")
                    
                    news_item = {
                        'uid': uid,  # 파티션 키
                        'id': str(uuid.uuid4()),  # 추가 고유 ID
                        'keyword': keyword,
                        'title': clean_html_tags(item.get('title', '')),
                        'originallink': original_link,
                        'link': item.get('link', ''),
                        'description': clean_html_tags(item.get('description', '')),
                        'pubDate': item.get('pubDate', ''),
                        'image_url': cloudfront_url,  # CloudFront URL
                        's3_key': s3_key,  # S3 경로
                        'original_image_url': image_data['original_url'] if image_data else None,  # 원본 이미지 URL
                        'collected_at': datetime.now().isoformat(),
                        'content_type': 'news',
                        'source': 'naver_api'
                    }
                    
                    # DynamoDB에 저장
                    try:
                        table.put_item(Item=news_item)
                        print(f"  ✓ DynamoDB 저장 성공: {news_item['title'][:30]}...")
                        if cloudfront_url:
                            print(f"    📸 CloudFront URL 포함됨: {cloudfront_url}")
                        if s3_key:
                            print(f"    📁 S3 경로: {s3_key}")
                    except ClientError as e:
                        print(f"  ✗ DynamoDB 저장 실패: {e.response['Error']['Message']}")
                        continue
                    
                    collected_news.append(news_item)
                    total_collected += 1
                    
                    # 로그에 뉴스 정보 출력
                    print(f"  - {news_item['title'][:50]}...")
                    
            else:
                print(f"API 오류 ({keyword}): {response.status_code} - {response.text}")
                
        except Exception as e:
            print(f"오류 발생 ({keyword}): {str(e)}")
        
        # API 호출 제한을 위한 대기
        import time
        time.sleep(1)
    
    print(f"\n=== 수집 완료 ===")
    print(f"총 수집된 뉴스: {total_collected}개")
    print(f"수집된 키워드: {len(keywords)}개")
    print(f"DynamoDB 테이블: ioi_contents_table (오사카 리전)")
    
    # 결과 반환
    result = {
        'statusCode': 200,
        'body': {
            'message': '뉴스 수집 및 DynamoDB 저장 완료',
            'total_collected': total_collected,
            'keywords_searched': keywords,
            'collected_at': datetime.now().isoformat(),
            'dynamodb_table': 'ioi_contents_table',
            'dynamodb_region': 'ap-northeast-3',
            'sample_news': collected_news[:3] if collected_news else []  # 샘플 3개만 반환
        }
    }
    
    # 전체 뉴스 데이터를 CloudWatch 로그에 출력
    print(f"\n=== 수집된 뉴스 상세 정보 ===")
    for i, news in enumerate(collected_news, 1):
        print(f"\n[{i}] UID: {news['uid']}")
        print(f"    키워드: {news['keyword']}")
        print(f"    제목: {news['title']}")
        print(f"    링크: {news['link']}")
        print(f"    발행일: {news['pubDate']}")
        print(f"    이미지: {news.get('image_url', '없음')}")
        print(f"    S3 경로: {news.get('s3_key', '없음')}")
        print(f"    원본 이미지: {news.get('original_image_url', '없음')}")
        print(f"    설명: {news['description'][:100]}...")
    
    return result

def download_and_upload_image_to_s3(image_url, uid, s3_client, bucket_name, cloudfront_domain):
    """
    이미지를 다운로드하여 S3에 업로드하고 CloudFront URL 반환
    """
    try:
        print(f"이미지 다운로드 시작: {image_url}")
        
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
            print(f"유효하지 않은 이미지 타입: {content_type}")
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
        
        # S3 키 생성: {uid}/images/이미지파일명
        # 이미지 URL을 해시하여 고유한 파일명 생성
        image_hash = hashlib.md5(image_url.encode()).hexdigest()[:12]
        s3_key = f"{uid}/images/{image_hash}{ext}"
        
        # S3에 업로드
        s3_client.put_object(
            Bucket=bucket_name,
            Key=s3_key,
            Body=response.content,
            ContentType=content_type,
            CacheControl='max-age=31536000',  # 1년 캐시
            Metadata={
                'original_url': image_url,
                'uploaded_at': datetime.now().isoformat()
            }
        )
        
        # CloudFront URL 생성
        cloudfront_url = f"{cloudfront_domain.rstrip('/')}/{s3_key}"
        
        print(f"S3 업로드 성공: s3://{bucket_name}/{s3_key}")
        print(f"CloudFront URL: {cloudfront_url}")
        
        return {
            's3_key': s3_key,
            'cloudfront_url': cloudfront_url,
            'original_url': image_url
        }
        
    except requests.RequestException as e:
        print(f"❌ 이미지 다운로드 오류: {str(e)}")
        if hasattr(e, 'response') and e.response is not None:
            print(f"   HTTP 상태 코드: {e.response.status_code}")
        return None
    except ClientError as e:
        error_code = e.response['Error']['Code']
        error_message = e.response['Error']['Message']
        print(f"❌ S3 업로드 오류 [{error_code}]: {error_message}")
        
        if error_code == 'AccessDenied':
            print(f"   💡 S3 버킷 '{bucket_name}' 접근 권한을 확인하세요.")
        elif error_code == 'NoSuchBucket':
            print(f"   💡 S3 버킷 '{bucket_name}'이 존재하지 않습니다.")
        
        return None
    except Exception as e:
        print(f"❌ 이미지 처리 중 예상치 못한 오류: {str(e)}")
        print(f"   이미지 URL: {image_url}")
        return None

def extract_image_from_article(article_url):
    """
    뉴스 기사 URL에서 이미지 URL을 추출
    """
    try:
        print(f"이미지 추출 시작: {article_url}")
        
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
            # 일반 img 태그
            soup.find('img', {'class': re.compile(r'.*article.*|.*news.*|.*content.*|.*photo.*')}),
            # 메타 태그의 og:image
            soup.find('meta', {'property': 'og:image'}),
            # 트위터 카드 이미지
            soup.find('meta', {'name': 'twitter:image'}),
            # 첫 번째 본문 이미지
            soup.find('div', {'class': re.compile(r'.*article.*|.*content.*|.*body.*')}).find('img') if soup.find('div', {'class': re.compile(r'.*article.*|.*content.*|.*body.*')}) else None,
            # 단순히 첫 번째 img 태그
            soup.find('img')
        ]
        
        for img_tag in img_patterns:
            if img_tag:
                if img_tag.name == 'img':
                    # img 태그에서 src 추출
                    src = img_tag.get('src') or img_tag.get('data-src')
                elif img_tag.name == 'meta':
                    # meta 태그에서 content 추출
                    src = img_tag.get('content')
                else:
                    continue
                
                if src:
                    # 상대 URL을 절대 URL로 변환
                    if src.startswith('//'):
                        image_url = 'https:' + src
                    elif src.startswith('/'):
                        from urllib.parse import urljoin
                        image_url = urljoin(article_url, src)
                    elif src.startswith('http'):
                        image_url = src
                    
                    # 유효한 이미지 URL인지 확인
                    if image_url and any(ext in image_url.lower() for ext in ['.jpg', '.jpeg', '.png', '.gif', '.webp']):
                        print(f"이미지 URL 추출 성공: {image_url}")
                        return image_url
        
        print(f"이미지를 찾을 수 없음: {article_url}")
        return None
        
    except requests.RequestException as e:
        print(f"HTTP 요청 오류: {str(e)}")
        return None
    except Exception as e:
        print(f"이미지 추출 오류: {str(e)}")
        return None

def get_news_from_dynamodb(limit=10):
    """
    DynamoDB에서 뉴스 데이터 조회 (uid 기준 최신순)
    """
    try:
        dynamodb = boto3.resource('dynamodb', region_name='ap-northeast-3')
        table = dynamodb.Table('ioi_contents_table')
        
        # 최신 뉴스부터 조회 (uid 기준 내림차순 - 날짜순 정렬)
        response = table.scan(
            Limit=limit,
            ProjectionExpression='uid, id, title, description, keyword, pubDate, collected_at, originallink, image_url, s3_key, original_image_url'
        )
        
        items = response.get('Items', [])
        
        # uid 기준으로 정렬 (최신순 - 날짜가 앞에 있어서 내림차순하면 최신이 위로)
        sorted_items = sorted(items, key=lambda x: x.get('uid', ''), reverse=True)
        
        print(f"DynamoDB에서 {len(sorted_items)}개 뉴스 조회됨 (uid 기준 정렬)")
        
        return {
            'statusCode': 200,
            'body': {
                'message': 'DynamoDB 뉴스 조회 성공',
                'total_items': len(sorted_items),
                'news_items': sorted_items,
                'table_name': 'ioi_contents_table',
                'region': 'ap-northeast-3',
                'sort_key': 'uid (날짜 기반)'
            }
        }
        
    except ClientError as e:
        print(f"DynamoDB 조회 오류: {e.response['Error']['Message']}")
        return {
            'statusCode': 500,
            'body': {
                'message': 'DynamoDB 조회 실패',
                'error': e.response['Error']['Message']
            }
        }

def test_local():
    """로컬 테스트용 함수"""
    # 환경 변수 설정 (실제 값으로 변경)
    os.environ['NAVER_CLIENT_ID'] = "2GgDhd6gDxBt6S4lQ2DU"
    os.environ['NAVER_CLIENT_SECRET'] = "OUghVjqy34"
    # CloudFront 도메인 설정
    os.environ['CLOUDFRONT_DOMAIN'] = "https://d3nvut5aamy17o.cloudfront.net"
    
    # 테스트 이벤트
    test_event = {
        'test': True,
        'keywords': ['IT']  # 테스트용으로 IT만
    }
    
    print("=== 뉴스 수집 및 DynamoDB 저장 테스트 ===")
    result = lambda_handler(test_event, None)
    print(f"\n=== 수집 테스트 결과 ===")
    print(json.dumps(result, indent=2, ensure_ascii=False))
    
    print("\n=== DynamoDB 조회 테스트 ===")
    read_result = get_news_from_dynamodb(5)
    print(json.dumps(read_result, indent=2, ensure_ascii=False))

if __name__ == "__main__":
    test_local() 
import urllib.request
import urllib.parse
import urllib.error
import json
import os
import re
import uuid
from typing import Dict, List
from datetime import datetime
from dotenv import load_dotenv

# .env 파일 로드
load_dotenv()

class NaverNewsAPI:
    def __init__(self):
        self.client_id = os.getenv("NAVER_CLIENT_ID")
        self.client_secret = os.getenv("NAVER_CLIENT_SECRET")
        self.search_url = "https://openapi.naver.com/v1/search/news.json"
        
        print(f"🔑 네이버 API 설정 확인:")
        print(f"   Client ID: {'설정됨' if self.client_id else '❌ 없음'}")
        print(f"   Client Secret: {'설정됨' if self.client_secret else '❌ 없음'}")
        
        if not self.client_id or not self.client_secret:
            print("\n❌ 네이버 API 키가 설정되지 않았습니다!")
            print("📝 해결 방법:")
            print("1. 프로젝트 루트에 .env 파일이 있는지 확인")
            print("2. .env 파일에 다음 내용이 있는지 확인:")
            print("   NAVER_CLIENT_ID=your_client_id")
            print("   NAVER_CLIENT_SECRET=your_client_secret")
            print("3. .env 파일이 main.py와 같은 폴더에 있는지 확인")
            raise ValueError("네이버 API 키가 설정되지 않았습니다.")
    
    def search_news(self, query: str, display: int = 10, start: int = 1, sort: str = "date") -> Dict:
        """네이버 뉴스 검색 API 호출"""
        try:
            # 요청 헤더 설정
            headers = {
                'X-Naver-Client-Id': self.client_id,
                'X-Naver-Client-Secret': self.client_secret
            }
            
            # 쿼리 파라미터 설정
            params = {
                'query': query,
                'display': display,
                'start': start,
                'sort': sort
            }
            
            # URL에 쿼리 파라미터 추가
            query_string = urllib.parse.urlencode(params)
            full_url = f"{self.search_url}?{query_string}"
            
            print(f"🔍 네이버 API 호출: {query} (display={display}, start={start})")
            
            # API 호출
            request = urllib.request.Request(full_url, headers=headers)
            
            with urllib.request.urlopen(request) as response:
                if response.status != 200:
                    raise Exception(f"네이버 API 호출 실패: HTTP {response.status}")
                
                response_data = response.read().decode('utf-8')
                news_data = json.loads(response_data)
                
                print(f"✅ API 응답 성공: {news_data.get('total', 0)}개 결과")
                return news_data
                
        except urllib.error.HTTPError as e:
            raise Exception(f"HTTP 에러: {e.code} - {e.reason}")
        except urllib.error.URLError as e:
            raise Exception(f"URL 에러: {e.reason}")
        except Exception as e:
            raise Exception(f"네이버 API 호출 중 오류: {str(e)}")
    
    def format_for_dynamodb(self, news_data: Dict, query: str) -> List[Dict]:
        """네이버 API 응답을 DynamoDB 형태로 변환"""
        formatted_items = []
        current_time = datetime.now().isoformat()
        
        for item in news_data.get('items', []):
            # 고유 ID 생성 (Lambda 코드와 동일한 방식)
            now = datetime.now()
            news_id = now.strftime('%Y%m%d_%H%M%S_') + str(uuid.uuid4())[:8]
            
            # DynamoDB 아이템 구성 (Lambda 코드와 동일)
            db_item = {
                'id': news_id,
                'title': self._clean_html_tags(item.get('title', '')),
                'description': self._clean_html_tags(item.get('description', '')),
                'keyword': query,
                'pubDate': item.get('pubDate', ''),
                'originallink': item.get('originallink', ''),
                'link': item.get('link', ''),
                'created_at': current_time,
                'collected_at': current_time,
                'content_type': 'news',
                'source': 'naver_api'  # Lambda에서는 'naver-api'였지만 통일
            }
            
            formatted_items.append(db_item)
        
        return formatted_items
    
    def _clean_html_tags(self, text: str) -> str:
        """HTML 태그 제거 (네이버 API 응답에 포함된 <b>, </b> 등)"""
        if not text:
            return ""
        
        # HTML 태그 제거
        clean = re.compile('<.*?>')
        cleaned_text = re.sub(clean, '', text)
        
        # HTML 엔티티 디코딩
        import html
        cleaned_text = html.unescape(cleaned_text)
        
        return cleaned_text.strip()

# 전역 인스턴스
naver_api = NaverNewsAPI()

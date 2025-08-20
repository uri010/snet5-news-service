import boto3
import os
from boto3.dynamodb.conditions import Key, Attr
from typing import Dict, List, Optional
from botocore.exceptions import ClientError
from dotenv import load_dotenv
import time

# .env 파일 로드
load_dotenv()

class DynamoDBManager:
    def __init__(self):
        self.dynamodb = None
        self.table = None
        self.table_name = os.getenv("DYNAMODB_TABLE_NAME", "naver_news_articles")
        self.gsi_name = "content_type-collected_at-index"  # 글로벌 인덱스 이름
        
    def connect(self):
        """DynamoDB 연결"""
        try:
            self.dynamodb = boto3.resource(
                'dynamodb',
                region_name=os.getenv("AWS_REGION", "ap-northeast-2")
            )
            
            self.table = self.dynamodb.Table(self.table_name)
            
            # 테이블 존재 확인
            response = self.table.meta.client.describe_table(TableName=self.table_name)
            print(f"✅ DynamoDB 연결 성공: {self.table_name}")
            print(f"📊 테이블 상태: {response['Table']['TableStatus']}")
            
            # 글로벌 인덱스 확인
            gsi_exists = False
            for gsi in response['Table'].get('GlobalSecondaryIndexes', []):
                if gsi['IndexName'] == self.gsi_name:
                    gsi_exists = True
                    print(f"🔍 글로벌 인덱스 확인: {self.gsi_name} ({gsi['IndexStatus']})")
                    break
            
            if not gsi_exists:
                print(f"⚠️  글로벌 인덱스를 찾을 수 없음: {self.gsi_name}")
                print("💡 다음 명령어로 글로벌 인덱스를 생성하세요:")
                print(f"aws dynamodb update-table --table-name {self.table_name} --attribute-definitions AttributeName=content_type,AttributeType=S AttributeName=collected_at,AttributeType=S --global-secondary-index-updates '[{{\"Create\":{{\"IndexName\":\"{self.gsi_name}\",\"KeySchema\":[{{\"AttributeName\":\"content_type\",\"KeyType\":\"HASH\"}},{{\"AttributeName\":\"collected_at\",\"KeyType\":\"RANGE\"}}],\"Projection\":{{\"ProjectionType\":\"ALL\"}},\"ProvisionedThroughput\":{{\"ReadCapacityUnits\":5,\"WriteCapacityUnits\":5}}}}}}]'")
            
        except ClientError as e:
            if e.response['Error']['Code'] == 'ResourceNotFoundException':
                print(f"❌ 테이블을 찾을 수 없습니다: {self.table_name}")
                print("💡 먼저 data-collection-service를 실행하여 테이블을 생성하세요.")
            raise e
        except Exception as e:
            print(f"❌ DynamoDB 연결 실패: {e}")
            raise e
    
    def get_news(self, limit: int = 20, offset: int = 0, keyword: Optional[str] = None) -> Dict:
        """뉴스 목록 조회 (글로벌 인덱스 사용 - collected_at 내림차순)"""
        try:
            start_time = time.time()
            
            # 글로벌 인덱스를 사용한 쿼리
            query_params = {
                'IndexName': self.gsi_name,
                'KeyConditionExpression': Key('content_type').eq('news'),
                'ScanIndexForward': False,  # collected_at 내림차순 정렬 (최신순)
                'Select': 'ALL_ATTRIBUTES'
            }
            
            # 키워드 필터링 추가
            if keyword:
                query_params['FilterExpression'] = (
                    Attr('keyword').contains(keyword) | 
                    Attr('title').contains(keyword) | 
                    Attr('description').contains(keyword)
                )
            
            # DynamoDB Query 실행 (GSI 사용)
            items = []
            last_evaluated_key = None
            
            # 페이지네이션을 고려하여 필요한 만큼 데이터 조회
            target_count = offset + limit
            
            while len(items) < target_count:
                if last_evaluated_key:
                    query_params['ExclusiveStartKey'] = last_evaluated_key
                
                response = self.table.query(**query_params)
                batch_items = response.get('Items', [])
                items.extend(batch_items)
                
                last_evaluated_key = response.get('LastEvaluatedKey')
                if not last_evaluated_key:  # 더 이상 조회할 데이터가 없음
                    break
            
            # 수동 pagination 처리
            total_count = len(items)
            paginated_items = items[offset:offset + limit]
            
            duration = time.time() - start_time
            print(f"🔍 뉴스 조회 완료 (GSI 사용): {total_count}개 중 {len(paginated_items)}개 반환 ({duration:.2f}초)")
            
            return {
                'items': paginated_items,
                'total_count': total_count,
                'returned_count': len(paginated_items)
            }
            
        except Exception as e:
            print(f"❌ DynamoDB 조회 에러: {e}")
            return {'items': [], 'total_count': 0, 'returned_count': 0}

    def get_statistics(self) -> Dict:
        """뉴스 통계 정보 (글로벌 인덱스 사용)"""
        try:
            # 전체 아이템 수 (GSI 사용)
            response = self.table.query(
                IndexName=self.gsi_name,
                KeyConditionExpression=Key('content_type').eq('news'),
                Select='COUNT'
            )
            total_count = response['Count']
            
            # 키워드별 통계를 위한 샘플링 (최대 100개)
            items_response = self.table.query(
                IndexName=self.gsi_name,
                KeyConditionExpression=Key('content_type').eq('news'),
                ScanIndexForward=False,
                Limit=100
            )
            items = items_response.get('Items', [])
            
            keyword_stats = {}
            source_stats = {}
            
            for item in items:
                # 키워드 통계
                keyword = item.get('keyword', 'Unknown')
                keyword_stats[keyword] = keyword_stats.get(keyword, 0) + 1
                
                # 소스 통계
                source = item.get('source', 'Unknown')
                source_stats[source] = source_stats.get(source, 0) + 1
            
            return {
                'total_items': total_count,
                'keyword_distribution': dict(sorted(keyword_stats.items(), key=lambda x: x[1], reverse=True)),
                'source_distribution': source_stats,
                'sample_size': len(items),
                'index_used': self.gsi_name
            }
            
        except Exception as e:
            print(f"❌ 통계 조회 실패: {e}")
            return {
                'total_items': 0, 
                'keyword_distribution': {}, 
                'source_distribution': {},
                'index_used': self.gsi_name
            }

# 전역 인스턴스
db_manager = DynamoDBManager()
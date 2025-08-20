import boto3
import os
from typing import Dict, List, Optional
from botocore.exceptions import ClientError
from dotenv import load_dotenv

# .env 파일 로드
load_dotenv()

class DynamoDBManager:
    def __init__(self):
        self.dynamodb = None
        self.table = None
        self.table_name = os.getenv("DYNAMODB_TABLE_NAME", "naver_news_articles")
        
    def connect(self):
        """DynamoDB 연결 (PC에 설정된 AWS 자격증명 사용)"""
        try:
            # AWS 자격증명은 PC에 이미 설정되어 있으므로 별도 지정 불필요
            self.dynamodb = boto3.resource(
                'dynamodb',
                region_name=os.getenv("AWS_REGION", "ap-northeast-2")
            )
            
            self.table = self.dynamodb.Table(self.table_name)
            
            # 테이블 존재 확인
            response = self.table.meta.client.describe_table(TableName=self.table_name)
            print(f"✅ DynamoDB 연결 성공: {self.table_name}")
            print(f"📊 테이블 상태: {response['Table']['TableStatus']}")
            print(f"🔑 AWS 자격증명: PC에 설정된 기본 프로파일 사용")
            
        except ClientError as e:
            if e.response['Error']['Code'] == 'ResourceNotFoundException':
                print(f"❌ 테이블을 찾을 수 없습니다: {self.table_name}")
                print("💡 다음 명령어로 테이블을 생성하세요:")
                print(f"aws dynamodb create-table --table-name {self.table_name} --attribute-definitions AttributeName=id,AttributeType=S --key-schema AttributeName=id,KeyType=HASH --provisioned-throughput ReadCapacityUnits=5,WriteCapacityUnits=5 --region {os.getenv('AWS_REGION', 'ap-northeast-2')}")
            elif e.response['Error']['Code'] == 'UnauthorizedOperation':
                print("❌ AWS 자격증명 오류. 다음을 확인하세요:")
                print("1. AWS CLI가 설치되어 있는지: aws --version")
                print("2. 자격증명이 설정되어 있는지: aws configure list")
                print("3. DynamoDB 권한이 있는지 확인")
            raise e
        except Exception as e:
            print(f"❌ DynamoDB 연결 실패: {e}")
            raise e
    
    def save_news_items(self, news_items: List[Dict]) -> Dict:
        """뉴스 아이템들을 DynamoDB에 저장"""
        saved_count = 0
        failed_count = 0
        saved_items = []
        
        for item in news_items:
            try:
                # DynamoDB에 저장
                self.table.put_item(Item=item)
                saved_count += 1
                saved_items.append({
                    'title': item['title'],
                    'id': item['id']
                })
                print(f"✅ 저장 성공: {item['id']} - {item['title'][:50]}...")
                
            except Exception as e:
                failed_count += 1
                print(f"❌ 저장 실패: {item.get('title', 'Unknown')} - {str(e)}")
        
        return {
            'saved_count': saved_count,
            'failed_count': failed_count,
            'saved_items': saved_items
        }
    
    def get_crawl_statistics(self) -> Dict:
        """크롤링 통계 조회"""
        try:
            # 테이블 스캔으로 전체 아이템 수 조회 (실제 운영에서는 별도 카운터 테이블 사용 권장)
            response = self.table.scan(Select='COUNT')
            total_items = response['Count']
            
            return {
                'total_items': total_items,
                'table_name': self.table_name
            }
        except Exception as e:
            print(f"❌ 통계 조회 실패: {e}")
            return {'total_items': 0, 'table_name': self.table_name}

# 전역 인스턴스
db_manager = DynamoDBManager()
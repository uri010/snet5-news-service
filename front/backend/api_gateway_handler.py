#!/usr/bin/env python3
"""
API Gateway 전용 Lambda 함수
뉴스 데이터 조회 API 제공
"""

import json
import logging
import boto3
from datetime import datetime
from botocore.exceptions import ClientError

# 로거 설정
logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    """API Gateway 요청 처리 메인 핸들러"""
    
    logger.info(f"API 요청 이벤트: {json.dumps(event, ensure_ascii=False)}")
    
    try:
        # HTTP 메서드 및 경로 확인
        http_method = event.get('httpMethod', '')
        path = event.get('path', '')
        query_params = event.get('queryStringParameters') or {}
        
        logger.info(f"HTTP 요청: {http_method} {path}")
        logger.info(f"쿼리 파라미터: {query_params}")
        
        # 라우팅
        if path == '/content/content_list' and http_method == 'GET':
            return handle_content_list(query_params)
        elif path == '/health' and http_method == 'GET':
            return handle_health_check()
        else:
            return create_api_response(404, {
                'message': 'Not Found',
                'error': f'경로 {path}를 찾을 수 없습니다.',
                'available_endpoints': [
                    'GET /content/content_list',
                    'GET /health'
                ]
            })
            
    except Exception as e:
        logger.error(f"API 처리 중 오류 발생: {str(e)}")
        return create_api_response(500, {
            'message': 'Internal Server Error',
            'error': str(e),
            'timestamp': datetime.now().isoformat()
        })

def handle_content_list(query_params):
    """뉴스 목록 조회 처리"""
    
    try:
        # 파라미터 파싱
        limit = int(query_params.get('limit', 20))
        offset = int(query_params.get('offset', 0))
        keyword = query_params.get('keyword', '')
        
        # 제한 체크
        if limit > 100:
            limit = 100
        elif limit < 1:
            limit = 1
        
        if offset < 0:
            offset = 0
            
        logger.info(f"뉴스 목록 조회 요청: limit={limit}, offset={offset}, keyword={keyword}")
        
        # DynamoDB에서 뉴스 데이터 조회
        news_data = get_news_from_dynamodb(limit, offset, keyword)
        
        if news_data['statusCode'] == 200:
            # 성공 응답
            response_body = {
                'message': '뉴스 목록 조회 성공',
                'total_items': news_data['body']['total_items'],
                'news_items': news_data['body']['news_items'],
                'parameters': {
                    'limit': limit,
                    'offset': offset,
                    'keyword': keyword if keyword else None
                },
                'timestamp': datetime.now().isoformat()
            }
            return create_api_response(200, response_body)
        else:
            # DynamoDB 오류
            return create_api_response(news_data['statusCode'], news_data['body'])
            
    except ValueError as e:
        logger.error(f"파라미터 오류: {str(e)}")
        return create_api_response(400, {
            'message': 'Bad Request',
            'error': 'limit 파라미터는 숫자여야 합니다.',
            'timestamp': datetime.now().isoformat()
        })
    except Exception as e:
        logger.error(f"뉴스 목록 조회 오류: {str(e)}")
        return create_api_response(500, {
            'message': 'Internal Server Error',
            'error': str(e),
            'timestamp': datetime.now().isoformat()
        })

def handle_health_check():
    """헬스 체크 처리"""
    
    return create_api_response(200, {
        'message': 'API Gateway Lambda 함수 정상 작동',
        'timestamp': datetime.now().isoformat(),
        'version': '1.0.0',
        'status': 'healthy'
    })

def get_news_from_dynamodb(limit=20, offset=0, keyword=''):
    """DynamoDB에서 뉴스 데이터 조회"""
    
    try:
        # DynamoDB 연결 (오사카 리전)
        dynamodb = boto3.resource('dynamodb', region_name='ap-northeast-3')
        table = dynamodb.Table('ioi_contents_table')
        
        logger.info(f"DynamoDB 조회 시작: limit={limit}, offset={offset}, keyword='{keyword}'")
        
        # Query 파라미터 설정 (GSI 사용)
        # content_type-collected_at-index 사용하여 시간순 정렬
        query_params = {
            'IndexName': 'content_type-collected_at-index',
            'KeyConditionExpression': 'content_type = :content_type',
            'ExpressionAttributeValues': {
                ':content_type': 'news'
            },
            'ScanIndexForward': False,  # 내림차순 정렬 (최신순)
            'Limit': limit + offset,  # offset + limit만큼 가져옴
            'ProjectionExpression': 'uid, id, title, description, keyword, pubDate, collected_at, originallink, image_url, s3_key, original_image_url, link'
        }
        
        # 키워드 필터링이 있는 경우
        if keyword:
            query_params['FilterExpression'] = 'contains(title, :keyword) OR contains(description, :keyword)'
            if ':keyword' not in query_params['ExpressionAttributeValues']:
                query_params['ExpressionAttributeValues'][':keyword'] = keyword
            else:
                query_params['ExpressionAttributeValues'][':keyword'] = keyword
        
        try:
            # DynamoDB Query 실행 (GSI 사용)
            response = table.query(**query_params)
            items = response.get('Items', [])
            logger.info(f"GSI Query 성공: {len(items)}개 아이템 조회")
        except Exception as e:
            logger.warning(f"GSI Query 실패, Scan으로 대체: {str(e)}")
            # GSI가 없는 경우 기존 Scan 방식으로 대체
            scan_params = {
                'Limit': (limit + offset) * 2,
                'ProjectionExpression': 'uid, id, title, description, keyword, pubDate, collected_at, originallink, image_url, s3_key, original_image_url, link'
            }
            if keyword:
                scan_params['FilterExpression'] = 'contains(title, :keyword) OR contains(description, :keyword)'
                scan_params['ExpressionAttributeValues'] = {':keyword': keyword}
            
            response = table.scan(**scan_params)
            items = response.get('Items', [])
        
        # GSI 사용 시에는 이미 collected_at 기준으로 정렬되어 있음
        # GSI 실패 시에만 정렬 필요
        if 'GSI Query 성공' in str(logger.handlers):
            # GSI 사용 시 이미 정렬됨
            sorted_items = items
        else:
            # Scan 사용 시 정렬 필요
            def parse_pub_date(item):
                try:
                    pub_date = item.get('pubDate', '')
                    if not pub_date:
                        return datetime.min
                    
                    from datetime import datetime
                    import re
                    
                    clean_date = re.sub(r'^[A-Za-z]{3},\s*', '', pub_date.strip())
                    months = {
                        'Jan': '01', 'Feb': '02', 'Mar': '03', 'Apr': '04',
                        'May': '05', 'Jun': '06', 'Jul': '07', 'Aug': '08',
                        'Sep': '09', 'Oct': '10', 'Nov': '11', 'Dec': '12'
                    }
                    
                    parts = clean_date.split(' ')
                    if len(parts) >= 5:
                        day = parts[0].zfill(2)
                        month = months.get(parts[1], '01')
                        year = parts[2]
                        time = parts[3]
                        timezone = parts[4]
                        
                        iso_date = f"{year}-{month}-{day}T{time}{timezone[:3]}:{timezone[3:]}"
                        return datetime.fromisoformat(iso_date.replace('+', '+').replace('-', '-', 2))
                    
                    return datetime.min
                except:
                    return datetime.min
            
            sorted_items = sorted(items, key=parse_pub_date, reverse=True)
        
        # offset 적용하여 페이지네이션 처리
        start_index = offset
        end_index = offset + limit
        final_items = sorted_items[start_index:end_index]
        
        logger.info(f"DynamoDB 조회 완료: {len(final_items)}개 반환")
        
        # 응답 데이터 정리
        cleaned_items = []
        for item in final_items:
            cleaned_item = {
                'uid': item.get('uid', ''),
                'id': item.get('id', ''),
                'title': item.get('title', ''),
                'description': item.get('description', ''),
                'keyword': item.get('keyword', ''),
                'pubDate': item.get('pubDate', ''),
                'originallink': item.get('originallink', ''),
                'link': item.get('link', ''),
                'image_url': item.get('image_url'),  # CloudFront URL
                's3_key': item.get('s3_key'),        # S3 경로
                'original_image_url': item.get('original_image_url'),  # 원본 이미지 URL
                'collected_at': item.get('collected_at', '')
            }
            cleaned_items.append(cleaned_item)
        
        return {
            'statusCode': 200,
            'body': {
                'message': 'DynamoDB 뉴스 조회 성공',
                'total_items': len(cleaned_items),
                'total_available': len(sorted_items),  # 전체 사용 가능한 아이템 수
                'has_more': end_index < len(sorted_items),  # 더 많은 데이터가 있는지
                'news_items': cleaned_items,
                'table_name': 'ioi_contents_table',
                'region': 'ap-northeast-3'
            }
        }
        
    except ClientError as e:
        logger.error(f"DynamoDB 조회 오류: {e.response['Error']['Message']}")
        return {
            'statusCode': 500,
            'body': {
                'message': 'DynamoDB 조회 실패',
                'error': e.response['Error']['Message'],
                'error_code': e.response['Error']['Code']
            }
        }
    except Exception as e:
        logger.error(f"예상하지 못한 DynamoDB 오류: {str(e)}")
        return {
            'statusCode': 500,
            'body': {
                'message': 'DynamoDB 조회 중 예상하지 못한 오류',
                'error': str(e)
            }
        }

def create_api_response(status_code, body_data):
    """API Gateway 호환 응답 생성"""
    
    return {
        'statusCode': status_code,
        'headers': {
            'Content-Type': 'application/json',
            'Access-Control-Allow-Origin': '*',  # CORS 허용
            'Access-Control-Allow-Headers': 'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token',
            'Access-Control-Allow-Methods': 'GET,POST,OPTIONS'
        },
        'body': json.dumps(body_data, ensure_ascii=False, indent=2)
    }

# 로컬 테스트용
def test_local():
    """로컬 테스트 함수"""
    
    # 테스트 이벤트 1: content_list
    test_event_1 = {
        'httpMethod': 'GET',
        'path': '/content/content_list',
        'queryStringParameters': {
            'limit': '5'
        }
    }
    
    print("=== 뉴스 목록 조회 테스트 ===")
    result = lambda_handler(test_event_1, None)
    print(f"상태 코드: {result['statusCode']}")
    print(f"응답 본문: {result['body']}")
    
    # 테스트 이벤트 2: health check
    test_event_2 = {
        'httpMethod': 'GET',
        'path': '/health',
        'queryStringParameters': None
    }
    
    print("\n=== 헬스 체크 테스트 ===")
    result = lambda_handler(test_event_2, None)
    print(f"상태 코드: {result['statusCode']}")
    print(f"응답 본문: {result['body']}")

if __name__ == "__main__":
    test_local()
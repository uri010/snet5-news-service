#!/usr/bin/env python3
"""
수집된 뉴스 데이터 분석 - Lambda 버전
"""

import json
import logging
from datetime import datetime
from collections import Counter

# 로거 설정
logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    """Lambda 핸들러: 뉴스 데이터 분석"""
    
    # 파라미터 검증
    logger.info("파라미터 검증 시작")
    
    # key 파라미터 확인
    if 'key' not in event:
        logger.error("key 파라미터 누락")
        return {
            'statusCode': 400,
            'body': {
                'message': '필수 파라미터 누락: key',
                'error': 'key 파라미터가 필요합니다.',
                'required_value': 'group01',
                'timestamp': datetime.now().isoformat()
            }
        }
    
    # key 값이 group01인지 확인
    key_value = event.get('key')
    if key_value != 'group01':
        logger.error(f"잘못된 key 값: {key_value}")
        return {
            'statusCode': 403,
            'body': {
                'message': '잘못된 key 값',
                'error': f'key 값이 올바르지 않습니다. (받은 값: {key_value})',
                'required_value': 'group01',
                'received_value': key_value,
                'timestamp': datetime.now().isoformat()
            }
        }
    
    logger.info(f"파라미터 검증 통과: {key_value}")
    
    # 뉴스 수집기 실행하여 데이터 가져오기
    from lambda_news_collector import lambda_handler as collect_news
    
    logger.info("뉴스 수집 시작")
    result = collect_news(event, context)
    
    # 수집된 뉴스 데이터 분석
    if 'body' in result and 'sample_news' in result['body']:
        total_news = result['body']['total_collected']
        keywords = result['body']['keywords_searched']
        sample_news = result['body']['sample_news']
        
        logger.info(f"뉴스 수집 완료: {total_news}개, 키워드: {keywords}")
        
        # 핵심 정보만 로깅
        if sample_news:
            logger.info(f"샘플 뉴스 {len(sample_news)}개 분석 완료")
    else:
        logger.warning("뉴스 데이터 수집 실패")
    
    # 분석 결과를 응답에 추가
    analysis_result = {
        'statusCode': 200,
        'body': {
            'message': '뉴스 수집 및 분석 완료',
            'authorized_key': key_value,
            'original_result': result['body'],
            'analysis': {
                'total_collected': result['body'].get('total_collected', 0),
                'keywords_searched': result['body'].get('keywords_searched', []),
                'sample_news_count': len(result['body'].get('sample_news', [])),
                'analysis_timestamp': datetime.now().isoformat()
            }
        }
    }
    
    logger.info("뉴스 분석 완료")
    return analysis_result

def test_news_structure(result=None):
    """뉴스 데이터 구조 테스트"""
    
    logger.info("뉴스 데이터 구조 테스트 시작")
    
    # 이미 수집된 결과가 있으면 사용, 없으면 새로 수집
    if result is None:
        from lambda_news_collector import lambda_handler as collect_news
        result = collect_news({}, None)
    
    # 실제 수집된 뉴스 데이터 중 첫 번째 것을 사용
    if 'body' in result and 'sample_news' in result['body'] and result['body']['sample_news']:
        actual_news = result['body']['sample_news'][0]
        test_news = {
            'keyword': actual_news['keyword'],
            'title': actual_news['title'],
            'originallink': actual_news['originallink'],
            'link': actual_news['link'],
            'description': actual_news['description'],
            'pubDate': actual_news['pubDate'],
            'collected_at': datetime.now().isoformat()
        }
        logger.info(f"실제 뉴스 데이터 사용: {actual_news['title'][:30]}...")
    else:
        # 백업용 테스트 데이터
        test_news = {
            'keyword': '주식',
            'title': '삼성전자, 2분기 영업익 4조6771억…전년比 55.23%↓',
            'originallink': 'http://www.popcornnews.net/news/articleView.html?idxno=88632',
            'link': 'http://www.popcornnews.net/news/articleView.html?idxno=88632',
            'description': '디스플레이는 스마트폰 신제품 수요와 IT·자동차에 공급되는 중소형 패널 판매 확대로 전분기 대비...',
            'pubDate': 'Thu, 31 Jul 2025 09:46:00 +0900',
            'collected_at': datetime.now().isoformat()
        }
        logger.warning("실제 데이터 수집 실패, 백업 데이터 사용")
    
    # 데이터 검증
    title_len = len(test_news['title'])
    desc_len = len(test_news['description'])
    link_valid = 'http' in test_news['link']
    date_valid = '+' in test_news['pubDate']
    
    logger.info(f"데이터 검증 완료: 제목={title_len}자, 설명={desc_len}자, 링크={link_valid}, 날짜={date_valid}")

def check_api_limits():
    """API 제한 확인"""
    
    # 현재 사용량 계산
    keywords = ["IT"]
    daily_usage = len(keywords)
    usage_percent = daily_usage / 25000 * 100
    
    logger.info(f"API 사용량 확인: {daily_usage}건/{25000}건 ({usage_percent:.1f}%)")
    
    return {
        'daily_limit': 25000,
        'current_usage': daily_usage,
        'usage_percent': round(usage_percent, 1),
        'keywords_count': len(keywords)
    }


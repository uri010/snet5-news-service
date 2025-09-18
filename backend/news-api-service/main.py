from fastapi import FastAPI, HTTPException, Query
from fastapi.middleware.cors import CORSMiddleware
import uvicorn
import os
import time
import random
from datetime import datetime
from typing import Optional
from dotenv import load_dotenv
import logging
import json
from datetime import datetime
import sys
import pytz

# .env 파일 로드
load_dotenv()

# 한국 시간대 설정
KST = pytz.timezone('Asia/Seoul')

from models import NewsItem, APIResponse, APIResponseBody, QueryParams, HealthResponse
from database import db_manager

# FastAPI 앱 생성
app = FastAPI(
    title="News API Service",
    description="뉴스 조회 및 검색 API",
    version="1.0.0"
)

# CORS 설정
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# JSON 포맷터 클래스
class JSONFormatter(logging.Formatter):
    def format(self, record):
        log_entry = {
            "timestamp": datetime.now(KST).isoformat(),
            "level": record.levelname,
            "service": "news-api-service",
            "message": record.getMessage(),
            "module": record.module,
            "function": record.funcName,
            "line": record.lineno
        }
        
        # extra 필드 추가
        if hasattr(record, 'extra_data'):
            log_entry.update(record.extra_data)
            
        return json.dumps(log_entry)

# 로거 설정
def setup_logging():
    logger = logging.getLogger("news_api")
    logger.setLevel(logging.INFO)
    
    # 기존 핸들러 제거
    for handler in logger.handlers[:]:
        logger.removeHandler(handler)
    
    # 새로운 핸들러 추가
    handler = logging.StreamHandler(sys.stdout)
    handler.setFormatter(JSONFormatter())
    logger.addHandler(handler)
    
    return logger

# 로거 인스턴스 생성
logger = setup_logging()


@app.on_event("startup")
async def startup_event():
    """앱 시작시 DynamoDB 연결"""
    try:
        logger.info("🚀 뉴스 API 서비스 시작 중...")
        db_manager.connect()
        stats = db_manager.get_statistics()
        logger.info(f"📊 현재 저장된 뉴스: {stats['total_items']}개")
        logger.info("✅ API 서비스 준비 완료!")
    except Exception as e:
        logger.error(f"❌ 시작 시 오류: {e}")
        logger.warning("⚠️  서비스가 정상적으로 시작되지 않았을 수 있습니다.")

@app.get("/")
async def root():
    return {
        "service": "News API Service",
        "version": "1.0.0",
        "description": "뉴스 조회 및 검색 API",
        "endpoints": [
            "GET / - 서비스 정보 및 상태 조회",
            "GET /health - 헬스체크",
            "GET /api/news - 뉴스 목록 조회 (키워드, 페이지네이션 지원)",
            "GET /api/cpu-test - CPU 부하 테스트 (Auto Scaling 테스트용)",
            "GET /api/memory-test - 메모리 부하 테스트 (Auto Scaling 테스트용)", 
            "GET /api/db-stress - DynamoDB 부하 테스트",
            "GET /api/load-test - 종합 부하 테스트 (CPU + DB + Memory)"
        ]
    }

@app.get("/test/cicd")
async def test_cicd():
    logger.info("CI/CD 테스트 엔드포인트 호출됨")
    return {
        "message": "CI/CD 테스트 성공!!",
        "version": "v1.0.0"
    }

@app.get("/health", response_model=HealthResponse)
async def health_check():
    return HealthResponse(
        status="healthy",
        timestamp=datetime.now(),
        service="news-api-service"
    )

@app.get("/api/news", response_model=APIResponse)
async def get_news(
    limit: int = Query(10, ge=1, le=100, description="조회할 뉴스 수"),
    offset: int = Query(0, ge=0, description="시작 위치 (페이지네이션)"),
    keyword: Optional[str] = Query('비트코인', description="검색 키워드")
):
    """뉴스 목록 조회 (DynamoDB)"""

    logger.info("News query requested", extra={
        'extra_data': {
            'limit': limit,
            'offset': offset,
            'keyword': keyword
        }
    })

    try:
        # DynamoDB에서 뉴스 조회
        result = db_manager.get_news(limit=limit, offset=offset, keyword=keyword)
        
        # NewsItem 객체로 변환
        news_items = []
        for item in result['items']:
            news_item = NewsItem(
                id=item.get('id', ''),
                title=item.get('title', ''),
                description=item.get('description', ''),
                keyword=item.get('keyword', ''),
                originallink=item.get('originallink', ''),
                link=item.get('link', ''),
                pubDate=item.get('pubDate', ''),
                image_url=item.get('image_url'),
                cloudfront_image_url=item.get('cloudfront_image_url'),
                collected_at=item.get('collected_at', ''),
                content_type=item.get('content_type', 'news'),
                source=item.get('source', '')
            )
            news_items.append(news_item)

        logger.info("News query successful", extra={
            'extra_data': {
                'returned_items': len(result['items']),
                'total_count': result['total_count']
            }
        })
        
        # API 응답 형태로 구성
        response_body = APIResponseBody(
            message="content_list 엔드포인트",
            news_items=news_items,
            total_items=result['total_count'],
            query_params=QueryParams(
                limit=str(limit),
                offset=str(offset),
                keyword=keyword
            ),
            timestamp=datetime.now().isoformat()
        )
        
        api_response = APIResponse(
            statusCode=200,
            headers={
                "Content-Type": "application/json",
                "Access-Control-Allow-Origin": "*",
                "Access-Control-Allow-Headers": "Content-Type",
                "Access-Control-Allow-Methods": "GET,POST,OPTIONS"
            },
            body=response_body
        )
        
        return api_response
        
    except Exception as e:
        logger.error("News query failed", extra={
            'extra_data': {
                'limit': limit,
                'offset': offset,
                'keyword': keyword,
                'error': str(e)
            }
        })
        raise HTTPException(status_code=500, detail=f"뉴스 조회 실패: {str(e)}")
    
# Auto Scaling 테스트용 엔드포인트들
@app.get("/api/cpu-test")
async def cpu_intensive_task():
    """CPU 집약적 작업 (Auto Scaling 테스트용)"""
    start_time = time.time()
    
    # CPU 부하 생성 (3초간)
    while time.time() - start_time < 3:
        _ = sum(range(100000))
    
    return {
        "statusCode": 200,
        "body": {
            "message": "CPU intensive task completed", 
            "duration": time.time() - start_time,
            "timestamp": datetime.now().isoformat()
        }
    }

@app.get("/api/memory-test")
async def memory_intensive_task():
    """메모리 집약적 작업 (Auto Scaling 테스트용)"""
    # 메모리 부하 생성
    large_list = [random.randint(1, 1000) for _ in range(2000000)]
    
    return {
        "statusCode": 200,
        "body": {
            "message": "Memory intensive task completed",
            "allocated_items": len(large_list),
            "timestamp": datetime.now().isoformat()
        }
    }

@app.get("/api/db-stress")
async def database_stress_test():
    """DynamoDB 부하 테스트"""
    start_time = time.time()
    
    # 여러 DynamoDB 쿼리 실행
    for i in range(5):
        db_manager.get_news(limit=10, offset=i*10)
    
    return {
        "statusCode": 200,
        "body": {
            "message": "DynamoDB stress test completed",
            "duration": time.time() - start_time,
            "timestamp": datetime.now().isoformat()
        }
    }

@app.get("/api/load-test")
async def load_test():
    """부하 테스트 (CPU + DB + Memory 조합)"""
    start_time = time.time()
    
    # 1. CPU 부하
    cpu_start = time.time()
    while time.time() - cpu_start < 1:
        _ = sum(range(50000))
    
    # 2. DB 부하
    db_manager.get_news(limit=20)
    db_manager.get_latest_news(limit=10)
    
    # 3. 메모리 부하
    temp_data = [random.randint(1, 1000) for _ in range(500000)]
    
    return {
        "statusCode": 200,
        "body": {
            "message": "Load test completed",
            "duration": time.time() - start_time,
            "memory_allocated": len(temp_data),
            "timestamp": datetime.now().isoformat()
        }
    }

if __name__ == "__main__":
    uvicorn.run(
        app, 
        host="0.0.0.0", 
        port=int(os.getenv("PORT", 8000)),
        reload=True
    )
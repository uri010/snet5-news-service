from fastapi import FastAPI, HTTPException, BackgroundTasks, Query
from fastapi.middleware.cors import CORSMiddleware
import uvicorn
import os
import time
from datetime import datetime
from typing import Optional, List

from models import CrawlRequest, CrawlResponse, CrawlStatus
from naver_api import naver_api
from database import db_manager

# FastAPI 앱 생성
app = FastAPI(
    title="News Data Collection Service",
    description="네이버 API를 활용한 뉴스 데이터 수집 서비스",
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

# 크롤링 상태 관리
crawl_status = CrawlStatus(
    is_running=False,
    last_run=None,
    total_collected=0,
    last_query=None,
    last_error=None
)

@app.on_event("startup")
async def startup_event():
    """앱 시작시 DynamoDB 연결"""
    try:
        db_manager.connect()
        stats = db_manager.get_crawl_statistics()
        crawl_status.total_collected = stats['total_items']
        print(f"📈 기존 수집된 뉴스: {stats['total_items']}개")
    except Exception as e:
        print(f"❌ 시작 시 오류: {e}")

@app.get("/")
async def root():
    return {
        "service": "News Data Collection Service",
        "version": "1.0.0",
        "description": "네이버 API를 활용한 뉴스 데이터 수집",
        "endpoints": [
            "POST /api/crawl/start - 뉴스 수집 시작",
            "POST /api/crawl/batch - 배치 수집",
            "GET /api/crawl/status - 수집 상태 조회",
            "GET /health - 헬스체크"
        ]
    }

@app.get("/health")
async def health_check():
    return {
        "status": "healthy",
        "timestamp": datetime.now().isoformat(),
        "service": "data-collection-service",
        "naver_api": "connected" if naver_api.client_id else "not_configured",
        "dynamodb": "connected" if db_manager.table else "not_connected"
    }

def crawl_news_sync(query: str, display: int = 10, start: int = 1, sort: str = "date") -> dict:
    """동기 방식 뉴스 크롤링 (백그라운드 작업용)"""
    crawl_status.is_running = True
    crawl_status.last_query = query
    crawl_status.last_error = None
    
    try:
        start_time = time.time()
        print(f"🚀 뉴스 수집 시작: '{query}' (display={display})")
        
        # CPU 부하 시뮬레이션 (Auto Scaling 테스트용)
        cpu_load_start = time.time()
        while time.time() - cpu_load_start < 1:  # 1초간 CPU 부하
            _ = sum(range(30000))
        
        # 네이버 API 호출
        news_data = naver_api.search_news(query=query, display=display, start=start, sort=sort)
        
        # DynamoDB 형태로 변환
        db_items = naver_api.format_for_dynamodb(news_data, query)
        
        # DynamoDB에 저장
        save_result = db_manager.save_news_items(db_items)
        
        # 상태 업데이트
        crawl_status.total_collected += save_result['saved_count']
        crawl_status.last_run = datetime.now().isoformat()
        
        duration = time.time() - start_time
        
        result = {
            'message': f'Successfully saved {save_result["saved_count"]} news items to DynamoDB',
            'search_query': query,
            'collected_at': datetime.now().isoformat(),
            'total_results': news_data.get('total', 0),
            'saved_items': save_result['saved_items'],
            'failed_count': save_result['failed_count'],
            'duration_seconds': round(duration, 2)
        }
        
        print(f"✅ 수집 완료: {save_result['saved_count']}개 저장, {duration:.2f}초 소요")
        return result
        
    except Exception as e:
        error_msg = f"뉴스 수집 실패: {str(e)}"
        crawl_status.last_error = error_msg
        print(f"❌ {error_msg}")
        raise Exception(error_msg)
    finally:
        crawl_status.is_running = False

@app.post("/api/crawl/start", response_model=CrawlResponse)
async def start_crawling(
    background_tasks: BackgroundTasks,
    query: str = Query("비트코인", description="검색 키워드"),
    display: int = Query(10, ge=1, le=100, description="수집할 뉴스 개수"),
    start: int = Query(1, ge=1, description="검색 시작 위치"),
    sort: str = Query("date", description="정렬 방식 (sim: 정확도순, date: 날짜순)")
):
    """뉴스 수집 시작 (백그라운드 실행)"""
    
    if crawl_status.is_running:
        raise HTTPException(status_code=400, detail="뉴스 수집이 이미 실행 중입니다")
    
    def background_crawl():
        try:
            crawl_news_sync(query, display, start, sort)
        except Exception as e:
            print(f"백그라운드 크롤링 실패: {e}")
    
    background_tasks.add_task(background_crawl)
    
    return CrawlResponse(
        statusCode=200,
        body={
            "message": f"'{query}' 키워드로 뉴스 수집이 시작되었습니다",
            "query": query,
            "display": display,
            "sort": sort,
            "timestamp": datetime.now().isoformat()
        }
    )

@app.post("/api/crawl/now", response_model=CrawlResponse)
async def crawl_now(
    query: str = Query("비트코인", description="검색 키워드"),
    display: int = Query(10, ge=1, le=100, description="수집할 뉴스 개수"),
    start: int = Query(1, ge=1, description="검색 시작 위치"),
    sort: str = Query("date", description="정렬 방식")
):
    """즉시 뉴스 수집 (동기 실행)"""
    
    if crawl_status.is_running:
        raise HTTPException(status_code=400, detail="뉴스 수집이 이미 실행 중입니다")
    
    try:
        result = crawl_news_sync(query, display, start, sort)
        
        return CrawlResponse(
            statusCode=200,
            body=result
        )
        
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/api/crawl/batch")
async def batch_crawling(
    queries: List[str] = Query(["비트코인", "AI", "클라우드"], description="검색 키워드 목록"),
    display_per_query: int = Query(5, ge=1, le=50, description="키워드당 수집할 뉴스 개수")
):
    """배치 수집 (여러 키워드, CPU 집약적)"""
    
    if crawl_status.is_running:
        raise HTTPException(status_code=400, detail="뉴스 수집이 이미 실행 중입니다")
    
    start_time = time.time()
    total_saved = 0
    results = []
    
    try:
        for i, query in enumerate(queries):
            print(f"🔍 배치 수집 [{i+1}/{len(queries)}]: '{query}'")
            
            result = crawl_news_sync(query, display_per_query)
            total_saved += result.get('saved_items', 0) if isinstance(result.get('saved_items'), int) else len(result.get('saved_items', []))
            results.append(result)
            
            # 키워드 간 딜레이 (API 제한 고려)
            if i < len(queries) - 1:  # 마지막이 아니면
                time.sleep(1)
        
        return CrawlResponse(
            statusCode=200,
            body={
                "message": f"배치 수집 완료: {len(queries)}개 키워드, {total_saved}개 뉴스 저장",
                "total_keywords": len(queries),
                "total_saved": total_saved,
                "duration_seconds": round(time.time() - start_time, 2),
                "results": results,
                "timestamp": datetime.now().isoformat()
            }
        )
        
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"배치 수집 실패: {str(e)}")

@app.get("/api/crawl/status")
async def get_crawl_status():
    """크롤링 상태 조회"""
    
    # 최신 통계 조회
    stats = db_manager.get_crawl_statistics()
    
    return {
        "statusCode": 200,
        "body": {
            "crawl_status": {
                "is_running": crawl_status.is_running,
                "last_run": crawl_status.last_run,
                "total_collected": stats['total_items'],  # DB에서 실시간 조회
                "last_query": crawl_status.last_query,
                "last_error": crawl_status.last_error
            },
            "database_stats": stats,
            "timestamp": datetime.now().isoformat()
        }
    }

# Auto Scaling 테스트용 엔드포인트
@app.get("/api/cpu-intensive")
async def cpu_intensive_crawl():
    """CPU 집약적 작업 (실제 크롤링 + CPU 부하)"""
    
    start_time = time.time()
    
    try:
        # 실제 크롤링 실행
        result = crawl_news_sync("AI", 5)
        
        # 추가 CPU 부하 생성 (3초간)
        cpu_start = time.time()
        while time.time() - cpu_start < 3:
            _ = sum(range(100000))
        
        return {
            "statusCode": 200,
            "body": {
                "message": "CPU intensive crawling completed",
                "duration_seconds": round(time.time() - start_time, 2),
                "crawl_result": result,
                "timestamp": datetime.now().isoformat()
            }
        }
        
    except Exception as e:
        return {
            "statusCode": 500,
            "body": {
                "message": "CPU intensive task failed",
                "error": str(e),
                "duration_seconds": round(time.time() - start_time, 2),
                "timestamp": datetime.now().isoformat()
            }
        }

if __name__ == "__main__":
    uvicorn.run(
        app,
        host="0.0.0.0",
        port=int(os.getenv("PORT", 8001)),
        reload=True
    )
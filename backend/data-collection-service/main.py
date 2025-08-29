from fastapi import FastAPI, HTTPException, Query
from fastapi.middleware.cors import CORSMiddleware
import uvicorn
import os
import time
from datetime import datetime
from typing import Optional
import asyncio
import email.utils
import concurrent.futures

from models import CrawlResponse, CrawlStatus
from naver_api import naver_api
from database import db_manager
from image_extractor import image_extractor

# FastAPI 앱 생성
app = FastAPI(
    title="News Data Collection Service",
    description="네이버 API를 활용한 뉴스 데이터 수집 서비스 (간소화 버전)",
    version="2.0.0"
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

def is_news_newer(news_pub_date: str, latest_pub_date: str) -> bool:
    """뉴스 발행일이 기존 최신 뉴스보다 더 늦은지 확인"""
    try:
        # RFC-2822 형식 파싱 (예: "Mon, 09 Sep 2024 14:30:00 +0900")
        news_timestamp = email.utils.parsedate_to_datetime(news_pub_date)
        latest_timestamp = email.utils.parsedate_to_datetime(latest_pub_date)
        
        return news_timestamp > latest_timestamp
        
    except Exception as e:
        print(f"⚠️ 날짜 파싱 오류: {e}, 문자열 비교로 대체")
        # 파싱 실패 시 문자열 비교로 대체
        return news_pub_date > latest_pub_date

@app.on_event("startup")
async def startup_event():
    """앱 시작시 DynamoDB 연결"""
    try:
        db_manager.connect()
        stats = db_manager.get_crawl_statistics()
        crawl_status.total_collected = stats['total_items']
        print(f"📈 기존 수집된 뉴스: {stats['total_items']}개")
        
        if image_extractor.s3_client:
            print(f"🖼️  이미지 수집 기능 활성화")
        else:
            print(f"⚠️  이미지 수집 기능 비활성화")
            
    except Exception as e:
        print(f"❌ 시작 시 오류: {e}")

@app.get("/")
async def root():
    return {
        "service": "News Data Collection Service",
        "version": "2.0.0",
        "description": "뉴스 자동 수집 서비스 (시간 기반 필터링)",
        "collection_logic": "DB 최신 뉴스보다 더 최신 뉴스만 수집",
        "endpoints": [
            "POST /api/collect - 뉴스 수집 실행",
            "GET /api/status - 수집 상태 조회",
            "GET /health - 헬스체크"
        ]
    }

@app.get("/health")
async def health_check():
    return {
        "status": "healthy",
        "timestamp": datetime.now().isoformat(),
        "service": "data-collection-service",
        "version": "2.0.0",
        "naver_api": "connected" if naver_api.client_id else "not_configured",
        "dynamodb": "connected" if db_manager.table else "not_connected",
        "image_service": image_extractor.s3_client is not None
    }

async def process_news_images_concurrently(news_items, max_workers: int = 3):
    """뉴스 이미지 병렬 처리"""
    if not image_extractor.s3_client:
        for item in news_items:
            item['image_url'] = None
            item['cloudfront_image_url'] = None
        return news_items
    
    def process_single_image(news_item):
        try:
            originallink = news_item.get('originallink')
            news_id = news_item.get('id')
            
            if originallink and news_id:
                result = image_extractor.process_news_image(originallink, str(news_id))
                if result:
                    news_item['image_url'] = result['original_url']
                    news_item['cloudfront_image_url'] = result['cloudfront_url']
                    return news_item
            
            news_item['image_url'] = None
            news_item['cloudfront_image_url'] = None
            return news_item
            
        except Exception:
            news_item['image_url'] = None
            news_item['cloudfront_image_url'] = None
            return news_item
    
    loop = asyncio.get_event_loop()
    with concurrent.futures.ThreadPoolExecutor(max_workers=max_workers) as executor:
        tasks = [
            loop.run_in_executor(executor, process_single_image, item)
            for item in news_items
        ]
        return await asyncio.gather(*tasks, return_exceptions=False)

async def collect_news_with_time_filter(query: str, display: int = 10, start: int = 1, sort: str = "date", include_images: bool = True) -> dict:
    """시간 기반 필터링을 적용한 뉴스 수집"""
    crawl_status.is_running = True
    crawl_status.last_query = query
    crawl_status.last_error = None
    
    try:
        start_time = time.time()
        print(f"🚀 뉴스 수집 시작: '{query}' (display={display}, images={'enabled' if include_images else 'disabled'})")
        
        # DB에서 가장 최신 pubDate 조회 (하나만)
        latest_pub_date = db_manager.get_last_collected_time()
        if latest_pub_date:
            print(f"📅 DB 최신 뉴스 시간: {latest_pub_date}")
        else:
            print(f"📅 첫 번째 수집 - 전체 수집을 진행합니다")
        
        # 네이버 API 호출
        news_data = naver_api.search_news(
            query=query, 
            display=display,
            start=start, 
            sort=sort
        )
        
        # DynamoDB 형태로 변환
        db_items = naver_api.format_for_dynamodb(news_data, query)
        
        # 최신 뉴스 시간과 비교하여 더 최신 뉴스만 필터링
        original_count = len(db_items)
        if latest_pub_date and db_items:
            print(f"🔍 최신 뉴스와 날짜 비교 시작: 기준 {latest_pub_date}")
            filtered_items = []
            
            for item in db_items:
                news_pub_date = item.get('pubDate', '')
                if not news_pub_date:
                    # pubDate가 없는 경우는 일단 수집
                    filtered_items.append(item)
                    print(f"  ✅ 수집: {item.get('title', 'Unknown')[:50]}... (pubDate 없음)")
                    continue
                
                # 가장 최신 뉴스와만 비교
                if is_news_newer(news_pub_date, latest_pub_date):
                    filtered_items.append(item)
                    print(f"  ✅ 수집: {item.get('title', 'Unknown')[:50]}... ({news_pub_date})")
                else:
                    print(f"  ⏭️  스킵: {item.get('title', 'Unknown')[:50]}... (기존보다 오래됨)")
            
            db_items = filtered_items
            print(f"🕐 날짜 필터링 완료: {original_count}개 → {len(db_items)}개 (더 최신 뉴스만)")
        else:
            print(f"📊 첫 수집 또는 기존 데이터 없음: {len(db_items)}개 모두 처리")
        
        if not db_items:
            message = "새로운 뉴스가 없습니다" if latest_pub_date else "수집된 뉴스가 없습니다"
            print(f"⚠️ {message}")
            return {
                'message': message,
                'search_query': query,
                'saved_count': 0,
                'latest_db_news_time': latest_pub_date,
                'original_fetched': original_count,
                'filtered_count': len(db_items),
                'duration_seconds': round(time.time() - start_time, 2)
            }
        
        print(f"📊 처리할 뉴스: {len(db_items)}개")
        
        # 이미지 처리 (병렬)
        if include_images and image_extractor.s3_client:
            db_items = await process_news_images_concurrently(db_items)
        else:
            for item in db_items:
                item['image_url'] = None
                item['cloudfront_image_url'] = None
        
        # DynamoDB에 저장
        save_result = db_manager.save_news_items(db_items)
        
        # 상태 업데이트
        crawl_status.total_collected += save_result['saved_count']
        crawl_status.last_run = datetime.now().isoformat()
        
        duration = time.time() - start_time
        
        # 이미지 통계
        image_success = sum(1 for item in db_items if item.get('cloudfront_image_url'))
        
        result = {
            'message': f'Successfully collected {save_result["saved_count"]} new news for "{query}"',
            'search_query': query,
            'collected_at': datetime.now().isoformat(),
            'latest_db_news_time': latest_pub_date,
            'original_fetched': original_count,
            'filtered_count': len(db_items),
            'saved_count': save_result['saved_count'],
            'failed_count': save_result.get('failed_count', 0),
            'images_processed': image_success,
            'duration_seconds': round(duration, 2)
        }
        
        print(f"✅ 수집 완료: {save_result['saved_count']}개 저장, {duration:.2f}초")
        return result
        
    except Exception as e:
        error_msg = f"뉴스 수집 실패: {str(e)}"
        crawl_status.last_error = error_msg
        print(f"❌ {error_msg}")
        raise Exception(error_msg)
    finally:
        crawl_status.is_running = False

@app.post("/api/collect", response_model=CrawlResponse)
async def collect_news(
    query: str = Query("비트코인", description="검색 키워드"),
    display: int = Query(10, ge=1, le=100, description="수집할 뉴스 개수"),
    start: int = Query(1, ge=1, description="검색 시작 위치"),
    sort: str = Query("date", description="정렬 방식 (sim: 정확도순, date: 날짜순)"),
    include_images: bool = Query(True, description="이미지 수집 여부")
):
    """뉴스 수집 실행 (기존 API 호환)"""
    
    if crawl_status.is_running:
        raise HTTPException(status_code=400, detail="뉴스 수집이 이미 실행 중입니다")
    
    try:
        result = await collect_news_with_time_filter(query, display, start, sort, include_images)
        
        return CrawlResponse(
            statusCode=200,
            body=result
        )
        
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/api/status")
async def get_status():
    """수집 상태 조회"""
    stats = db_manager.get_crawl_statistics()
    
    return {
        "statusCode": 200,
        "body": {
            "service_status": {
                "is_running": crawl_status.is_running,
                "last_run": crawl_status.last_run,
                "last_error": crawl_status.last_error
            },
            "collection_stats": {
                "total_collected": stats['total_items']
            },
            "services": {
                "naver_api": "connected" if naver_api.client_id else "not_configured",
                "dynamodb": "connected" if db_manager.table else "not_connected",
                "image_processing": image_extractor.s3_client is not None
            },
            "timestamp": datetime.now().isoformat()
        }
    }

@app.get("/api/stress-test")
async def stress_test():
    """CPU 부하 + 실제 뉴스 수집"""
    start_time = time.time()
    
    try:
        # 실제 뉴스 수집 (기본값 사용)
        result = await collect_news_with_time_filter("AI", 5)
        
        # CPU 부하 추가
        cpu_start = time.time()
        while time.time() - cpu_start < 5:
            _ = sum(range(200000))
        
        return {
            "statusCode": 200,
            "body": {
                "message": "Stress test completed with news collection",
                "duration_seconds": round(time.time() - start_time, 2),
                "collection_result": result,
                "timestamp": datetime.now().isoformat()
            }
        }
        
    except Exception as e:
        return {
            "statusCode": 500,
            "body": {
                "error": str(e),
                "duration_seconds": round(time.time() - start_time, 2)
            }
        }

if __name__ == "__main__":
    uvicorn.run(
        app,
        host="0.0.0.0",
        port=int(os.getenv("PORT", 8001)),
        reload=True
    )
from fastapi import FastAPI, HTTPException, BackgroundTasks, Query
from fastapi.middleware.cors import CORSMiddleware
import uvicorn
import os
import time
from datetime import datetime
from typing import Optional, List
import asyncio
import concurrent.futures

from models import CrawlRequest, CrawlResponse, CrawlStatus
from naver_api import naver_api
from database import db_manager
from image_extractor import image_extractor

# FastAPI 앱 생성
app = FastAPI(
    title="News Data Collection Service",
    description="네이버 API를 활용한 뉴스 데이터 수집 서비스 (이미지 포함)",
    version="1.1.0"
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
        
        # 이미지 추출기 상태 확인
        if image_extractor.s3_client:
            print(f"🖼️  이미지 수집 기능 활성화 (S3: {image_extractor.s3_bucket})")
        else:
            print(f"⚠️  이미지 수집 기능 비활성화 (S3 설정 없음)")
            
    except Exception as e:
        print(f"❌ 시작 시 오류: {e}")

@app.get("/")
async def root():
    return {
        "service": "News Data Collection Service",
        "version": "1.1.0",
        "description": "네이버 API를 활용한 뉴스 데이터 수집 (이미지 포함)",
        "features": {
            "news_collection": True,
            "image_extraction": image_extractor.s3_client is not None,
            "s3_storage": image_extractor.s3_bucket if image_extractor.s3_client else None,
            "cloudfront_cdn": image_extractor.cloudfront_domain if image_extractor.s3_client else None
        },
        "endpoints": [
            "POST /api/crawl/start - 뉴스 수집 시작 (이미지 포함)",
            "POST /api/crawl/batch - 배치 수집 (이미지 포함)",
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
        "version": "1.1.0",
        "naver_api": "connected" if naver_api.client_id else "not_configured",
        "dynamodb": "connected" if db_manager.table else "not_connected",
        "image_service": {
            "enabled": image_extractor.s3_client is not None,
            "s3_bucket": image_extractor.s3_bucket if image_extractor.s3_client else None,
            "cloudfront_domain": image_extractor.cloudfront_domain if image_extractor.s3_client else None
        }
    }

def process_single_news_image(news_item: dict) -> dict:
    """단일 뉴스 아이템의 이미지를 처리"""
    try:
        # 네이버 API 응답에서 올바른 필드 사용
        originallink = news_item.get('originallink')  # 원본 기사 URL (이미지 추출용)
        news_id = news_item.get('id')  # 뉴스 ID
        title = news_item.get('title', '제목없음')
        
        if not originallink or not news_id:
            news_item['image_url'] = None
            news_item['cloudfront_image_url'] = None
            return news_item
            
        print(f"🖼️  이미지 처리: {title[:40]}...")
        
        # originallink에서 이미지 추출
        image_result = image_extractor.process_news_image(originallink, str(news_id))
        
        if image_result:
            # NewsItem 모델에 맞는 필드명으로 저장
            news_item['image_url'] = image_result['original_url']  # 원본 이미지 URL
            news_item['cloudfront_image_url'] = image_result['cloudfront_url']  # CloudFront URL
            print(f"✅ 이미지 완료: CloudFront URL 생성됨")
        else:
            news_item['image_url'] = None
            news_item['cloudfront_image_url'] = None
            print(f"❌ 이미지 없음")
            
        return news_item
        
    except Exception as e:
        print(f"❌ 이미지 오류: {str(e)[:50]}...")
        news_item['image_url'] = None
        news_item['cloudfront_image_url'] = None
        return news_item

async def process_news_images_concurrently(news_items: List[dict], max_workers: int = 3) -> List[dict]:
    """뉴스 아이템들의 이미지를 병렬로 처리"""
    if not image_extractor.s3_client:
        print("⚠️  S3 미설정 - 이미지 처리 건너뜀")
        for item in news_items:
            item['image_url'] = None
            item['cloudfront_image_url'] = None
        return news_items
    
    print(f"🖼️  {len(news_items)}개 뉴스 이미지 처리 시작...")
    
    # ThreadPoolExecutor를 사용하여 병렬 처리
    loop = asyncio.get_event_loop()
    
    with concurrent.futures.ThreadPoolExecutor(max_workers=max_workers) as executor:
        # 각 뉴스 아이템의 이미지 처리를 병렬로 실행
        tasks = [
            loop.run_in_executor(executor, process_single_news_image, news_item)
            for news_item in news_items
        ]
        
        # 모든 작업 완료 대기
        processed_items = await asyncio.gather(*tasks, return_exceptions=True)
        
        # 예외가 발생한 경우 원본 아이템 반환
        final_items = []
        for i, result in enumerate(processed_items):
            if isinstance(result, Exception):
                print(f"❌ 뉴스 #{i} 이미지 처리 실패")
                original_item = news_items[i].copy()
                original_item['image_url'] = None
                original_item['cloudfront_image_url'] = None
                final_items.append(original_item)
            else:
                final_items.append(result)
    
    # 성공한 이미지 처리 개수 계산
    success_count = sum(1 for item in final_items if item.get('cloudfront_image_url') is not None)
    print(f"✅ 이미지 처리 완료: {success_count}/{len(news_items)}개 성공")
    
    return final_items

async def crawl_news_async(query: str, display: int = 10, start: int = 1, sort: str = "date", include_images: bool = True) -> dict:
    """비동기 방식 뉴스 크롤링 - 이미지 포함"""
    crawl_status.is_running = True
    crawl_status.last_query = query
    crawl_status.last_error = None
    
    try:
        start_time = time.time()
        print(f"🚀 뉴스 수집 시작: '{query}' (display={display}, images={'enabled' if include_images else 'disabled'})")
        
        # 네이버 API 호출
        news_data = naver_api.search_news(query=query, display=display, start=start, sort=sort)
        
        # DynamoDB 형태로 변환
        db_items = naver_api.format_for_dynamodb(news_data, query)
        
        # 디버깅: 변환된 데이터 구조 확인 (첫 실행시만)
        if db_items:
            print(f"📊 뉴스 수집: {len(db_items)}개 아이템, API 총 결과: {news_data.get('total', 0)}개")
        
        # 이미지 처리
        if include_images and db_items:
            print(f"🖼️  이미지 처리 시작...")
            db_items = await process_news_images_concurrently(db_items)
        else:
            # 이미지 처리를 하지 않는 경우 image 필드들을 None으로 설정
            for item in db_items:
                item['image_url'] = None
                item['cloudfront_image_url'] = None
        
        # DynamoDB에 저장
        save_result = db_manager.save_news_items(db_items)
        
        # 상태 업데이트
        crawl_status.total_collected += save_result['saved_count']
        crawl_status.last_run = datetime.now().isoformat()
        
        duration = time.time() - start_time
        
        # 이미지 처리 결과 통계
        image_stats = {
            'enabled': include_images,
            'success_count': 0,
            'total_processed': 0
        }
        
        if include_images:
            image_stats['total_processed'] = len(db_items)
            image_stats['success_count'] = sum(1 for item in db_items if item.get('cloudfront_image_url') is not None)
        
        result = {
            'message': f'Successfully saved {save_result["saved_count"]} news items to DynamoDB',
            'search_query': query,
            'collected_at': datetime.now().isoformat(),
            'total_results': news_data.get('total', 0),
            'saved_items': save_result['saved_items'],
            'failed_count': save_result['failed_count'],
            'duration_seconds': round(duration, 2),
            'image_processing': image_stats
        }
        
        print(f"✅ 수집 완료: {save_result['saved_count']}개 저장, 이미지 {image_stats['success_count']}/{image_stats['total_processed']}개 처리, {duration:.2f}초 소요")
        return result
        
    except Exception as e:
        error_msg = f"뉴스 수집 실패: {str(e)}"
        crawl_status.last_error = error_msg
        print(f"❌ {error_msg}")
        raise Exception(error_msg)
    finally:
        crawl_status.is_running = False

def crawl_news_sync(query: str, display: int = 10, start: int = 1, sort: str = "date", include_images: bool = True) -> dict:
    """동기 방식 뉴스 크롤링 (백그라운드 작업용) - 이미지 포함"""
    crawl_status.is_running = True
    crawl_status.last_query = query
    crawl_status.last_error = None
    
    try:
        start_time = time.time()
        print(f"🚀 뉴스 수집 시작: '{query}' (display={display}, images={'enabled' if include_images else 'disabled'})")
        
        # 네이버 API 호출
        news_data = naver_api.search_news(query=query, display=display, start=start, sort=sort)
        
        # DynamoDB 형태로 변환
        db_items = naver_api.format_for_dynamodb(news_data, query)
        
        # 디버깅: 변환된 데이터 구조 확인 (첫 실행시만)
        if db_items:
            print(f"📊 뉴스 수집: {len(db_items)}개 아이템, API 총 결과: {news_data.get('total', 0)}개")
        
        # 이미지 처리 (동기 방식으로 처리)
        if include_images and db_items:
            print(f"🖼️  이미지 처리 시작...")
            processed_items = []
            success_count = 0
            
            for i, item in enumerate(db_items):
                processed_item = process_single_news_image(item)
                processed_items.append(processed_item)
                if processed_item.get('cloudfront_image_url') is not None:
                    success_count += 1
            
            db_items = processed_items
            print(f"✅ 이미지 처리 완료: {success_count}/{len(db_items)}개 성공")
        else:
            # 이미지 처리를 하지 않는 경우 image 필드들을 None으로 설정
            for item in db_items:
                item['image_url'] = None
                item['cloudfront_image_url'] = None
        
        # DynamoDB에 저장
        save_result = db_manager.save_news_items(db_items)
        
        # 상태 업데이트
        crawl_status.total_collected += save_result['saved_count']
        crawl_status.last_run = datetime.now().isoformat()
        
        duration = time.time() - start_time
        
        # 이미지 처리 결과 통계
        image_stats = {
            'enabled': include_images,
            'success_count': 0,
            'total_processed': 0
        }
        
        if include_images:
            image_stats['total_processed'] = len(db_items)
            image_stats['success_count'] = sum(1 for item in db_items if item.get('cloudfront_image_url') is not None)
        
        result = {
            'message': f'Successfully saved {save_result["saved_count"]} news items to DynamoDB',
            'search_query': query,
            'collected_at': datetime.now().isoformat(),
            'total_results': news_data.get('total', 0),
            'saved_items': save_result['saved_items'],
            'failed_count': save_result['failed_count'],
            'duration_seconds': round(duration, 2),
            'image_processing': image_stats
        }
        
        print(f"✅ 수집 완료: {save_result['saved_count']}개 저장, 이미지 {image_stats['success_count']}/{image_stats['total_processed']}개 처리, {duration:.2f}초 소요")
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
    sort: str = Query("date", description="정렬 방식 (sim: 정확도순, date: 날짜순)"),
    include_images: bool = Query(True, description="이미지 수집 여부")
):
    """뉴스 수집 시작 (백그라운드 실행) - 이미지 포함"""
    
    if crawl_status.is_running:
        raise HTTPException(status_code=400, detail="뉴스 수집이 이미 실행 중입니다")
    
    def background_crawl():
        try:
            crawl_news_sync(query, display, start, sort, include_images)
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
            "include_images": include_images,
            "image_service_enabled": image_extractor.s3_client is not None,
            "timestamp": datetime.now().isoformat()
        }
    )

@app.post("/api/crawl/now", response_model=CrawlResponse)
async def crawl_now(
    query: str = Query("비트코인", description="검색 키워드"),
    display: int = Query(10, ge=1, le=100, description="수집할 뉴스 개수"),
    start: int = Query(1, ge=1, description="검색 시작 위치"),
    sort: str = Query("date", description="정렬 방식"),
    include_images: bool = Query(True, description="이미지 수집 여부")
):
    """즉시 뉴스 수집 (비동기 실행) - 이미지 포함"""
    
    if crawl_status.is_running:
        raise HTTPException(status_code=400, detail="뉴스 수집이 이미 실행 중입니다")
    
    try:
        result = await crawl_news_async(query, display, start, sort, include_images)
        
        return CrawlResponse(
            statusCode=200,
            body=result
        )
        
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/api/crawl/batch")
async def batch_crawling(
    queries: List[str] = Query(["비트코인"], description="검색 키워드 목록"),
    display_per_query: int = Query(5, ge=1, le=50, description="키워드당 수집할 뉴스 개수"),
    include_images: bool = Query(True, description="이미지 수집 여부")
):
    """배치 수집 (여러 키워드, CPU 집약적) - 이미지 포함"""
    
    if crawl_status.is_running:
        raise HTTPException(status_code=400, detail="뉴스 수집이 이미 실행 중입니다")
    
    start_time = time.time()
    total_saved = 0
    total_images_processed = 0
    total_images_success = 0
    results = []
    
    try:
        for i, query in enumerate(queries):
            print(f"🔍 배치 수집 [{i+1}/{len(queries)}]: '{query}'")
            
            result = await crawl_news_async(query, display_per_query, include_images=include_images)
            total_saved += result.get('saved_items', 0) if isinstance(result.get('saved_items'), int) else len(result.get('saved_items', []))
            
            # 이미지 통계 누적
            if 'image_processing' in result:
                total_images_processed += result['image_processing'].get('total_processed', 0)
                total_images_success += result['image_processing'].get('success_count', 0)
            
            results.append(result)
            
            # 키워드 간 딜레이 (API 제한 고려)
            if i < len(queries) - 1:  # 마지막이 아니면
                await asyncio.sleep(1)
        
        return CrawlResponse(
            statusCode=200,
            body={
                "message": f"배치 수집 완료: {len(queries)}개 키워드, {total_saved}개 뉴스 저장",
                "total_keywords": len(queries),
                "total_saved": total_saved,
                "duration_seconds": round(time.time() - start_time, 2),
                "image_processing": {
                    "enabled": include_images,
                    "total_processed": total_images_processed,
                    "success_count": total_images_success,
                    "success_rate": round(total_images_success / total_images_processed * 100, 1) if total_images_processed > 0 else 0
                },
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
            "image_service": {
                "enabled": image_extractor.s3_client is not None,
                "s3_bucket": image_extractor.s3_bucket if image_extractor.s3_client else None,
                "cloudfront_domain": image_extractor.cloudfront_domain if image_extractor.s3_client else None
            },
            "timestamp": datetime.now().isoformat()
        }
    }

# Auto Scaling 테스트용 엔드포인트
@app.get("/api/cpu-intensive")
async def cpu_intensive_crawl():
    """CPU 집약적 작업 (실제 크롤링 + 이미지 처리 + CPU 부하)"""
    
    start_time = time.time()
    
    try:
        # 실제 크롤링 + 이미지 처리 실행
        result = await crawl_news_async("AI", 5, include_images=True)
        
        # 추가 CPU 부하 생성 (3초간)
        cpu_start = time.time()
        while time.time() - cpu_start < 3:
            _ = sum(range(100000))
        
        return {
            "statusCode": 200,
            "body": {
                "message": "CPU intensive crawling with image processing completed",
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

# 이미지 관련 테스트 엔드포인트
@app.get("/api/image/test")
async def test_image_extraction(
    url: str = Query(..., description="테스트할 뉴스 기사 URL")
):
    """이미지 추출 테스트"""
    try:
        if not image_extractor.s3_client:
            raise HTTPException(status_code=503, detail="S3가 설정되지 않아 이미지 서비스를 사용할 수 없습니다")
        
        # 임시 UID 생성
        import hashlib
        temp_uid = hashlib.md5(url.encode()).hexdigest()[:10]
        
        # 이미지 처리 테스트
        result = image_extractor.process_news_image(url, f"test_{temp_uid}")
        
        return {
            "statusCode": 200,
            "body": {
                "message": "이미지 추출 테스트 완료",
                "test_url": url,
                "result": result,
                "timestamp": datetime.now().isoformat()
            }
        }
        
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"이미지 추출 테스트 실패: {str(e)}")

if __name__ == "__main__":
    uvicorn.run(
        app,
        host="0.0.0.0",
        port=int(os.getenv("PORT", 8001)),
        reload=True
    )
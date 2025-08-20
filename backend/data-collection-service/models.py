from pydantic import BaseModel
from typing import Optional, List
from datetime import datetime

class NewsItem(BaseModel):
    id: str
    title: str
    description: str
    keyword: str
    pubDate: str
    originallink: str
    link: str
    created_at: str
    collected_at: str
    content_type: str
    source: str

class CrawlRequest(BaseModel):
    query: str = "비트코인"
    display: int = 10
    start: int = 1
    sort: str = "date"  # sim: 정확도순, date: 날짜순

class CrawlResponse(BaseModel):
    statusCode: int
    body: dict

class CrawlStatus(BaseModel):
    is_running: bool
    last_run: Optional[str]
    total_collected: int
    last_query: Optional[str]
    last_error: Optional[str]
from pydantic import BaseModel
from typing import Optional, List, Dict, Any
from datetime import datetime

class NewsItem(BaseModel):
    id: str
    title: str
    description: str
    keyword: str
    originallink: str
    link: str
    pubDate: str
    image_url: Optional[str] = None
    cloudfront_image_url: Optional[str] = None
    collected_at: str
    content_type: str
    source: str

class QueryParams(BaseModel):
    limit: str
    offset: str
    keyword: Optional[str] = None

class APIResponseBody(BaseModel):
    message: str
    news_items: List[NewsItem]
    total_items: int
    query_params: QueryParams
    timestamp: str

class APIResponse(BaseModel):
    statusCode: int
    headers: Dict[str, str]
    body: APIResponseBody

class HealthResponse(BaseModel):
    status: str
    timestamp: datetime
    service: str
# Lambda Layer for BeautifulSoup4

이 디렉토리는 AWS Lambda Layer를 생성하기 위한 파일들을 포함합니다.

## 포함된 패키지
- `beautifulsoup4==4.12.2` - HTML/XML 파싱 라이브러리
- `lxml==4.9.3` - 고성능 XML/HTML 파서
- `html5lib==1.1` - HTML5 파싱 지원

## 빌드 방법

### 1. Linux/Mac 환경
```bash
cd backend/new_data_collect/layer
chmod +x build_layer.sh
./build_layer.sh
```

### 2. Windows 환경
```cmd
cd backend\new_data_collect\layer
build_layer.bat
```

## Layer 생성 및 적용

### 1. AWS CLI로 Layer 생성
```bash
aws lambda publish-layer-version \
  --layer-name beautifulsoup-layer \
  --description "BeautifulSoup4 and dependencies for web scraping" \
  --zip-file fileb://beautifulsoup-layer.zip \
  --compatible-runtimes python3.9 python3.10 python3.11 \
  --region ap-northeast-3
```

### 2. Lambda 함수에 Layer 연결
AWS 콘솔에서:
1. Lambda 함수 → Configuration → Layers
2. "Add a layer" 클릭
3. "Custom layers" 선택
4. 생성한 layer 선택

또는 AWS CLI로:
```bash
aws lambda update-function-configuration \
  --function-name your-function-name \
  --layers arn:aws:lambda:ap-northeast-3:123456789012:layer:beautifulsoup-layer:1 \
  --region ap-northeast-3
```

## 디렉토리 구조
```
layer/
├── python/
│   ├── requirements.txt          # 패키지 의존성
│   └── lib/
│       └── python3.9/
│           └── site-packages/    # 설치된 패키지들
├── build_layer.sh               # Linux/Mac 빌드 스크립트
├── build_layer.bat              # Windows 빌드 스크립트
├── README.md                    # 이 파일
└── beautifulsoup-layer.zip      # 생성된 Layer ZIP 파일
```

## 주의사항
- Lambda Layer 최대 크기: 50MB (압축 후)
- 압축 해제 후 최대 크기: 250MB
- Layer는 `/opt/python/lib/python3.x/site-packages/`에 마운트됩니다
- 빌드 환경과 Lambda 런타임이 호환되어야 합니다 (Linux x86_64)

## 테스트
Layer가 적용된 Lambda 함수에서 다음 코드로 테스트:
```python
from bs4 import BeautifulSoup
import requests

def lambda_handler(event, context):
    # BeautifulSoup이 정상적으로 import되는지 확인
    html = "<html><body><h1>Test</h1></body></html>"
    soup = BeautifulSoup(html, 'html.parser')
    return {
        'statusCode': 200,
        'body': f'Title: {soup.find("h1").text}'
    }
```
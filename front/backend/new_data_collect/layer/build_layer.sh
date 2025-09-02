#!/bin/bash

# Lambda Layer 빌드 스크립트
# BeautifulSoup4와 관련 패키지들을 Lambda Layer로 패키징

echo "=== Lambda Layer 빌드 시작 ==="

# 작업 디렉토리 설정
LAYER_DIR="python"
ZIP_FILE="beautifulsoup-layer.zip"

# 기존 빌드 파일 정리
echo "기존 파일 정리 중..."
rm -rf $LAYER_DIR/lib
rm -f $ZIP_FILE

# Python 패키지 설치 디렉토리 생성
mkdir -p $LAYER_DIR/lib/python3.9/site-packages

echo "패키지 설치 중..."

# 패키지 설치 (Lambda 런타임과 호환되는 버전)
pip install -r $LAYER_DIR/requirements.txt -t $LAYER_DIR/lib/python3.9/site-packages/

echo "불필요한 파일 제거 중..."
# 불필요한 파일들 제거 (Layer 크기 최적화)
find $LAYER_DIR -name "*.pyc" -delete
find $LAYER_DIR -name "__pycache__" -type d -exec rm -rf {} + 2>/dev/null || true
find $LAYER_DIR -name "*.dist-info" -type d -exec rm -rf {} + 2>/dev/null || true
find $LAYER_DIR -name "tests" -type d -exec rm -rf {} + 2>/dev/null || true

echo "ZIP 파일 생성 중..."
# ZIP 파일 생성
cd $LAYER_DIR && zip -r ../$ZIP_FILE . && cd ..

echo "=== 빌드 완료 ==="
echo "생성된 파일: $ZIP_FILE"
echo "파일 크기: $(du -h $ZIP_FILE | cut -f1)"
echo ""
echo "AWS CLI를 사용한 Layer 생성 명령어:"
echo "aws lambda publish-layer-version \\"
echo "  --layer-name beautifulsoup-layer \\"
echo "  --description 'BeautifulSoup4 and dependencies for web scraping' \\"
echo "  --zip-file fileb://$ZIP_FILE \\"
echo "  --compatible-runtimes python3.9 python3.10 python3.11 \\"
echo "  --region ap-northeast-3"
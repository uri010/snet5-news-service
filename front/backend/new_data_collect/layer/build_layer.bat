@echo off
REM Lambda Layer 빌드 스크립트 (Windows용)
REM BeautifulSoup4와 관련 패키지들을 Lambda Layer로 패키징

echo === Lambda Layer 빌드 시작 ===

REM 작업 디렉토리 설정
set LAYER_DIR=python
set ZIP_FILE=beautifulsoup-layer.zip

REM 기존 빌드 파일 정리
echo 기존 파일 정리 중...
if exist %LAYER_DIR%\lib rmdir /s /q %LAYER_DIR%\lib
if exist %ZIP_FILE% del %ZIP_FILE%

REM Python 패키지 설치 디렉토리 생성
mkdir %LAYER_DIR%\lib\python3.9\site-packages

echo 패키지 설치 중...

REM 패키지 설치 (Lambda 런타임과 호환되는 버전)
pip install -r %LAYER_DIR%\requirements.txt -t %LAYER_DIR%\lib\python3.9\site-packages\

echo 불필요한 파일 제거 중...
REM 불필요한 파일들 제거 (Layer 크기 최적화)
for /r %LAYER_DIR% %%i in (*.pyc) do del "%%i"
for /f "delims=" %%i in ('dir /s /b /ad %LAYER_DIR%\*__pycache__*') do rmdir /s /q "%%i" 2>nul

echo ZIP 파일 생성 중...
REM PowerShell을 사용하여 ZIP 파일 생성
powershell -command "Compress-Archive -Path '%LAYER_DIR%\*' -DestinationPath '%ZIP_FILE%' -Force"

echo === 빌드 완료 ===
echo 생성된 파일: %ZIP_FILE%

echo.
echo AWS CLI를 사용한 Layer 생성 명령어:
echo aws lambda publish-layer-version ^
echo   --layer-name beautifulsoup-layer ^
echo   --description "BeautifulSoup4 and dependencies for web scraping" ^
echo   --zip-file fileb://%ZIP_FILE% ^
echo   --compatible-runtimes python3.9 python3.10 python3.11 ^
echo   --region ap-northeast-3

pause
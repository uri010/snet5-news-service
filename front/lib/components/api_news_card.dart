import 'package:flutter/material.dart';
import '../models/api_news_model.dart';

class ApiNewsCard extends StatelessWidget {
  final ApiNewsModel news;

  const ApiNewsCard({
    super.key,
    required this.news,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 이미지 섹션
          Expanded(
            flex: 3,
            child: ClipRRect(
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
              ),
              child: Container(
                width: double.infinity,
                color: Colors.white,
                child: news.hasImage
                    ? Image.network(
                        _getCorsProxyUrl(news.imageUrl!),  // CORS 문제 해결을 위한 프록시 사용
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          print('이미지 로딩 실패: ${news.imageUrl}');
                          print('CloudFront URL: ${news.cloudfrontImageUrl ?? '없음'}');
                          print('오류: $error');
                          // 프록시 실패 시 원본 URL로 재시도
                          return Image.network(
                            news.imageUrl!,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error2, stackTrace2) {
                              print('원본 URL도 실패: $error2');
                              return _buildErrorImage();
                            },
                          );
                        },
                        loadingBuilder: (context, child, loadingProgress) {
                          if (loadingProgress == null) return child;
                          return _buildLoadingImage(loadingProgress);
                        },
                      )
                    : _buildPlaceholderImage(),
              ),
            ),
          ),
          
          // 콘텐츠 섹션
          Expanded(
            flex: 2,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 키워드 태그
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      news.keyword,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ),
                  
                  const SizedBox(height: 6),
                  
                  // 제목
                  Text(
                    news.title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  
                  const SizedBox(height: 4),
                  
                  // 내용
                  Expanded(
                    child: Text(
                      news.description,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                        height: 1.3,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  
                  const SizedBox(height: 6),
                  
                  // 메타 정보 (출처, 시간)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          news.source == 'naver_api' ? '네이버 뉴스' : news.source,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.primary,
                            fontWeight: FontWeight.w500,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        news.timeAgo,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlaceholderImage() {
    return Container(
      width: double.infinity,
      color: Colors.white,
      child: Center(
        child: Image.network(
          'icons/snet.png',
          width: 120,
          height: 80,
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) {
            // 로고 파일이 없으면 텍스트로 대체
            return const Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'SNET',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.blue,
                  ),
                ),
                Text(
                  'GROUP',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: Colors.blueGrey,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildErrorImage() {
    return Container(
      width: double.infinity,
      color: Colors.white,
      child: Center(
        child: Image.network(
          'icons/snet.png',
          width: 120,
          height: 80,
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) {
            // 로고 파일이 없으면 텍스트로 대체
            return const Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'SNET',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey,
                  ),
                ),
                Text(
                  'GROUP',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: Colors.blueGrey,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  /// 이미지 로딩 중 표시할 위젯
  Widget _buildLoadingImage(ImageChunkEvent? loadingProgress) {
    return Container(
      width: double.infinity,
      color: Colors.grey[50],
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // 🌀 회전하는 아이콘 로딩
          SizedBox(
            width: 50,
            height: 50,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // 배경 원
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.blue[50],
                  ),
                ),
                // 회전 애니메이션
                const SizedBox(
                  width: 30,
                  height: 30,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
                  ),
                ),
                // 중앙 아이콘
                const Icon(
                  Icons.image,
                  size: 20,
                  color: Colors.blue,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // 로딩 텍스트 with 점점점 애니메이션
          const Text(
            '불러오는 중',
            style: TextStyle(
              fontSize: 12,
              color: Colors.blueGrey,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 6),
          // 진행률 바
          if (loadingProgress?.expectedTotalBytes != null) ...[
            Container(
              width: 80,
              height: 4,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(2),
                color: Colors.grey[300],
              ),
              child: FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: loadingProgress!.cumulativeBytesLoaded /
                    loadingProgress.expectedTotalBytes!,
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(2),
                    gradient: const LinearGradient(
                      colors: [Colors.blue, Colors.lightBlue],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${((loadingProgress!.cumulativeBytesLoaded / loadingProgress.expectedTotalBytes!) * 100).toInt()}%',
              style: const TextStyle(
                fontSize: 10,
                color: Colors.blueGrey,
                fontWeight: FontWeight.w500,
              ),
            ),
          ] else
            // 진행률을 모를 때는 점점점 애니메이션
            const Text(
              '⏳ 잠시만 기다려주세요...',
              style: TextStyle(
                fontSize: 10,
                color: Colors.blueGrey,
              ),
            ),
        ],
      ),
    );
  }

  /// CORS 문제 해결을 위한 프록시 URL 생성
  /// CloudFront에 CORS 헤더가 설정되지 않은 경우를 위한 대안
  String _getCorsProxyUrl(String cloudFrontUrl) {
    // localhost 개발 환경에서만 프록시 사용
    if (_isLocalhost()) {
      // 여러 CORS 프록시 서비스 중 안정적인 것 사용
      return 'https://api.allorigins.win/raw?url=${Uri.encodeComponent(cloudFrontUrl)}';
      // 대안: return 'https://images.weserv.nl/?url=${Uri.encodeComponent(cloudFrontUrl)}';
    }
    
    // 프로덕션 환경에서는 CloudFront URL 직접 사용
    return cloudFrontUrl;
  }
  
  /// 현재 실행 환경이 localhost인지 확인
  bool _isLocalhost() {
    final currentUrl = Uri.base.toString();
    return currentUrl.contains('localhost') || currentUrl.contains('127.0.0.1');
  }
}
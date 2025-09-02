import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/api_news_model.dart';
import '../components/api_news_card.dart';
import '../services/news_api_service.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  bool isDarkMode = false;
  List<ApiNewsModel> newsList = [];
  bool isLoading = true;
  bool isLoadingMore = false;
  bool hasMoreData = true;
  String? errorMessage;
  final ScrollController _scrollController = ScrollController();
  
  static const int _pageSize = 10; // 한 번에 로드할 뉴스 개수
  int _currentOffset = 0; // 현재 오프셋

  @override
  void initState() {
    super.initState();
    _loadNewsFromApi();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= 
        _scrollController.position.maxScrollExtent - 200) {
      // 스크롤이 끝에서 200px 전에 도달하면 더 많은 데이터 로드
      _loadMoreNews();
    }
  }

  Future<void> _loadNewsFromApi() async {
    setState(() {
      isLoading = true;
      errorMessage = null;
      _currentOffset = 0;
      hasMoreData = true;
    });

    try {
      final fetchedNews = await NewsApiService.getNewsListPaginated(
        limit: _pageSize,
        offset: 0,
      );
      
      setState(() {
        newsList = fetchedNews;
        isLoading = false;
        _currentOffset = _pageSize;
        hasMoreData = fetchedNews.length == _pageSize;
      });
    } catch (e) {
      setState(() {
        errorMessage = '뉴스를 불러오는데 실패했습니다: $e';
        isLoading = false;
      });
      print('뉴스 로딩 오류: $e');
    }
  }

  Future<void> _loadMoreNews() async {
    if (isLoadingMore || !hasMoreData) return;

    setState(() {
      isLoadingMore = true;
    });

    try {
      final moreNews = await NewsApiService.getNewsListPaginated(
        limit: _pageSize,
        offset: _currentOffset,
      );

      setState(() {
        newsList.addAll(moreNews);
        _currentOffset += _pageSize;
        hasMoreData = moreNews.length == _pageSize;
        isLoadingMore = false;
      });

      print('더 많은 뉴스 로드됨: ${moreNews.length}개, 총 ${newsList.length}개');
    } catch (e) {
      setState(() {
        isLoadingMore = false;
      });
      print('추가 뉴스 로딩 오류: $e');
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('추가 뉴스를 불러오는데 실패했습니다: $e'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    }
  }

  void _toggleTheme() {
    setState(() {
      isDarkMode = !isDarkMode;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: isDarkMode ? ThemeData.dark() : ThemeData.light(),
      child: Scaffold(
        appBar: AppBar(
          title: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.newspaper,
                size: 28,
              ),
              const SizedBox(width: 8),
              Text(
                'IOI NEWS Version 0.1',
                style: Theme.of(context).appBarTheme.titleTextStyle,
              ),
            ],
          ),
          actions: [
            IconButton(
              icon: Icon(
                isDarkMode ? Icons.light_mode : Icons.dark_mode,
              ),
              onPressed: _toggleTheme,
              tooltip: isDarkMode ? '라이트 모드로 변경' : '다크 모드로 변경',
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: RefreshIndicator(
          onRefresh: _loadNewsFromApi,
          child: _buildBody(),
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: _loadNewsFromApi,
          child: const Icon(Icons.refresh),
          tooltip: '새로고침',
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('뉴스를 불러오는 중...'),
          ],
        ),
      );
    }

    if (errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: Colors.red.shade300,
            ),
            const SizedBox(height: 16),
            Text(
              errorMessage!,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.red.shade700),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadNewsFromApi,
              child: const Text('다시 시도'),
            ),
          ],
        ),
      );
    }

    if (newsList.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.newspaper,
              size: 64,
              color: Colors.grey,
            ),
            SizedBox(height: 16),
            Text('뉴스가 없습니다'),
          ],
        ),
      );
    }

    return Center(
      child: LayoutBuilder(
        builder: (context, constraints) {
          // 화면 크기에 따라 열 개수 결정
          int crossAxisCount = 2;
          if (constraints.maxWidth > 1200) {
            crossAxisCount = 3;
          } else if (constraints.maxWidth < 600) {
            crossAxisCount = 1;
          }
          
          return Container(
            constraints: const BoxConstraints(maxWidth: 1200),
            margin: EdgeInsets.symmetric(
              horizontal: constraints.maxWidth > 600 ? 32 : 16,
            ),
            child: GridView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(16),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: crossAxisCount,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
                childAspectRatio: 0.75, // 카드 비율 조정
              ),
              itemCount: newsList.length + (isLoadingMore ? 1 : 0),
              itemBuilder: (context, index) {
                // 로딩 인디케이터 표시
                if (index == newsList.length && isLoadingMore) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(16.0),
                      child: CircularProgressIndicator(),
                    ),
                  );
                }
                
                return GestureDetector(
                  onTap: () {
                    _openNewsLink(newsList[index]);
                  },
                  child: ApiNewsCard(news: newsList[index]),
                );
              },
            ),
          );
        },
      ),
    );
  }

  Future<void> _openNewsLink(ApiNewsModel news) async {
    try {
      // 원본 링크가 있으면 원본 링크를, 없으면 네이버 링크를 사용
      String urlToOpen = news.originallink.isNotEmpty ? news.originallink : news.link;
      
      if (urlToOpen.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('링크 정보가 없습니다.'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      // URL이 http:// 또는 https://로 시작하지 않으면 추가
      if (!urlToOpen.startsWith('http://') && !urlToOpen.startsWith('https://')) {
        urlToOpen = 'https://$urlToOpen';
      }

      final Uri url = Uri.parse(urlToOpen);
      
      if (await canLaunchUrl(url)) {
        await launchUrl(
          url,
          mode: LaunchMode.externalApplication, // 새 탭에서 열기
        );
      } else {
        // 링크를 열 수 없는 경우 상세 정보 다이얼로그 표시
        _showNewsDetail(news);
      }
    } catch (e) {
      print('링크 열기 실패: $e');
      // 링크 열기에 실패하면 상세 정보 다이얼로그 표시
      _showNewsDetail(news);
    }
  }

  void _showNewsDetail(ApiNewsModel news) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(
            news.title,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // 키워드 태그
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    news.keyword,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                
                // 이미지
                if (news.hasImage)
                  Container(
                    height: 200,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.network(
                        news.imageUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return Container(
                            height: 200,
                            decoration: BoxDecoration(
                              color: Colors.grey[300],
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Center(
                              child: Icon(
                                Icons.newspaper,
                                size: 60,
                                color: Colors.grey,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                if (news.hasImage) const SizedBox(height: 16),
                
                // 내용
                Text(
                  news.description,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 16),
                
                // 메타 정보
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '출처: ${news.source == 'naver_api' ? '네이버 뉴스' : news.source}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Text(
                      news.timeAgo,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                
                // 원본 링크 버튼
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      // 웹에서 링크 열기 (url_launcher 패키지 필요)
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('원본 링크: ${news.originallink}'),
                          action: SnackBarAction(
                            label: '복사',
                            onPressed: () {
                              // 클립보드에 복사하는 기능 추가 가능
                            },
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.open_in_new),
                    label: const Text('원본 기사 보기'),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text('닫기'),
            ),
          ],
        );
      },
    );
  }
}
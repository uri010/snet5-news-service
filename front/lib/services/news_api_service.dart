import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../models/api_news_model.dart';

class NewsApiService {
  // 환경변수에서 API URL 가져오기 (fallback으로 String.fromEnvironment 사용)
  static String get baseUrl {
    return dotenv.env['API_BASE_URL'] ?? 
           const String.fromEnvironment('API_BASE_URL', 
               defaultValue: 'https://api.ioinews.shop');
  }
  
  static String get contentListEndpoint {
    return dotenv.env['NEWS_LIST_PATH'] ?? 
           const String.fromEnvironment('NEWS_LIST_PATH', 
               defaultValue: '/api/news');
  }
  

  static Map<String, String> get headers => {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      };

  /// 뉴스 목록을 가져오는 메서드
  static Future<List<ApiNewsModel>> getNewsList({
    int limit = 20,
    String? keyword,
  }) async {
    return await getNewsListPaginated(
      limit: limit,
      keyword: keyword,
      offset: 0,
    );
  }

  /// 페이지네이션을 지원하는 뉴스 목록 가져오기 메서드
  static Future<List<ApiNewsModel>> getNewsListPaginated({
    int limit = 10,
    int offset = 0,
    String? keyword,
  }) async {
    try {
      // URL 파라미터 구성
      final uri = Uri.parse('$baseUrl$contentListEndpoint');
      final queryParams = <String, String>{
        'limit': limit.toString(),
        'offset': offset.toString(),
      };

      if (keyword != null && keyword.isNotEmpty) {
        queryParams['keyword'] = keyword;
      }

      final finalUri = uri.replace(queryParameters: queryParams);

      print('API 요청 URL: $finalUri');

      // API 호출
      final response = await http
          .get(
        finalUri,
        headers: headers,
      )
          .timeout(
        const Duration(seconds: 60), // 타임아웃 시간 증가
        onTimeout: () {
          throw Exception('API 요청 시간 초과');
        },
      );

      print('API 응답 상태: ${response.statusCode}');
      print(
          'API 응답 본문: ${response.body.substring(0, response.body.length > 500 ? 500 : response.body.length)}...');

      if (response.statusCode == 200) {
        final jsonData = json.decode(response.body);

        // API 응답 구조에 따라 조정 필요
        List<dynamic> newsListJson;

        if (jsonData is Map<String, dynamic>) {
          // 응답이 객체 형태인 경우
          if (jsonData.containsKey('body')) {
            final body = jsonData['body'];
            if (body is Map<String, dynamic> &&
                body.containsKey('news_items')) {
              newsListJson = body['news_items'] as List<dynamic>;
            } else if (body is List<dynamic>) {
              newsListJson = body;
            } else {
              throw Exception('예상하지 못한 API 응답 구조: body');
            }
          } else if (jsonData.containsKey('news_items')) {
            newsListJson = jsonData['news_items'] as List<dynamic>;
          } else if (jsonData.containsKey('data')) {
            newsListJson = jsonData['data'] as List<dynamic>;
          } else {
            throw Exception('예상하지 못한 API 응답 구조: 최상위');
          }
        } else if (jsonData is List<dynamic>) {
          // 응답이 배열 형태인 경우
          newsListJson = jsonData;
        } else {
          throw Exception('예상하지 못한 API 응답 타입');
        }

        // JSON을 모델로 변환
        final newsList = newsListJson
            .map<ApiNewsModel>((json) => ApiNewsModel.fromJson(json))
            .toList();

        // 실제 발행일 기준으로 최신순 정렬 소팅
        newsList.sort((a, b) {
          final dateA = a.publishedDateTime;
          final dateB = b.publishedDateTime;

          // null 체크 및 최신순 정렬 (최신이 앞으로)
          if (dateA == null && dateB == null) return 0;
          if (dateA == null) return 1; // null은 뒤로
          if (dateB == null) return -1; // null은 뒤로

          return dateB.compareTo(dateA); // 최신순 (내림차순)
        });

        print('변환된 뉴스 개수: ${newsList.length} (발행일 기준 최신순 정렬 완료)');
        return newsList;
      } else {
        throw Exception('API 호출 실패: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      print('뉴스 목록 가져오기 오류: $e');
      rethrow;
    }
  }

  /// 특정 뉴스 상세 정보를 가져오는 메서드 (필요한 경우)
  static Future<ApiNewsModel?> getNewsDetail(String uid) async {
    try {
      final uri = Uri.parse('$baseUrl/content/$uid');

      final response = await http
          .get(
            uri,
            headers: headers,
          )
          .timeout(
            const Duration(seconds: 30),
          );

      if (response.statusCode == 200) {
        final jsonData = json.decode(response.body);
        return ApiNewsModel.fromJson(jsonData);
      } else {
        print('뉴스 상세 정보 가져오기 실패: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      print('뉴스 상세 정보 가져오기 오류: $e');
      return null;
    }
  }

  /// API 연결 테스트
  static Future<bool> testConnection() async {
    try {
      final uri = Uri.parse('$baseUrl$contentListEndpoint');
      final response = await http
          .get(
            uri.replace(queryParameters: {'limit': '1'}),
            headers: headers,
          )
          .timeout(
            const Duration(seconds: 10),
          );

      return response.statusCode == 200;
    } catch (e) {
      print('API 연결 테스트 실패: $e');
      return false;
    }
  }
}

class ApiNewsModel {
  final String id;
  final String title;
  final String description;
  final String keyword;
  final String originallink;
  final String link;
  final String pubDate;
  final String? imageUrl;          // 원본 이미지 URL
  final String? cloudfrontImageUrl; // CloudFront URL
  final String collectedAt;
  final String contentType;
  final String source;

  ApiNewsModel({
    required this.id,
    required this.title,
    required this.description,
    required this.keyword,
    required this.originallink,
    required this.link,
    required this.pubDate,
    this.imageUrl,
    this.cloudfrontImageUrl,
    required this.collectedAt,
    required this.contentType,
    required this.source,
  });

  factory ApiNewsModel.fromJson(Map<String, dynamic> json) {
    return ApiNewsModel(
      id: json['id'] ?? '',
      title: json['title'] ?? '',
      description: json['description'] ?? '',
      keyword: json['keyword'] ?? '',
      originallink: json['originallink'] ?? '',
      link: json['link'] ?? '',
      pubDate: json['pubDate'] ?? '',
      imageUrl: json['image_url'],           // 원본 이미지 URL
      cloudfrontImageUrl: json['cloudfront_image_url'],  // CloudFront URL
      collectedAt: json['collected_at'] ?? '',
      contentType: json['content_type'] ?? '',
      source: json['source'] ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'keyword': keyword,
      'originallink': originallink,
      'link': link,
      'pubDate': pubDate,
      'image_url': imageUrl,              // 원본 이미지 URL
      'cloudfront_image_url': cloudfrontImageUrl,  // CloudFront URL
      'collected_at': collectedAt,
      'content_type': contentType,
      'source': source,
    };
  }

  // 발행일을 DateTime으로 변환
  DateTime? get publishedDateTime {
    try {
      // RFC 822 형식: "Thu, 07 Aug 2025 05:40:00 +0900"
      if (pubDate.isEmpty) return null;
      
      // RFC 822 형식을 ISO 8601 형식으로 변환
      String cleanDate = pubDate.trim();
      
      // 요일과 콤마 제거: "Thu, " -> ""
      cleanDate = cleanDate.replaceFirst(RegExp(r'^[A-Za-z]{3},\s*'), '');
      
      // 월 이름을 숫자로 변환
      final months = {
        'Jan': '01', 'Feb': '02', 'Mar': '03', 'Apr': '04',
        'May': '05', 'Jun': '06', 'Jul': '07', 'Aug': '08',
        'Sep': '09', 'Oct': '10', 'Nov': '11', 'Dec': '12'
      };
      
      // "07 Aug 2025 05:40:00 +0900" 형식 파싱
      final parts = cleanDate.split(' ');
      print('🔍 원본: $pubDate');
      print('🔍 정리된: $cleanDate');
      print('🔍 파싱된 부분들: $parts');
      
      if (parts.length >= 5) {
        final day = parts[0].padLeft(2, '0');
        final month = months[parts[1]] ?? '01';
        final year = parts[2];
        final time = parts[3];
        final timezone = parts[4];
        
        // 타임존 형식 안전하게 처리
        String formattedTimezone = timezone;
        if (timezone.length == 5 && (timezone.startsWith('+') || timezone.startsWith('-'))) {
          // +0900 -> +09:00
          formattedTimezone = '${timezone.substring(0, 3)}:${timezone.substring(3)}';
        }
        
        // ISO 8601 형식으로 변환: "2025-08-07T05:40:00+09:00"
        final isoDate = '$year-$month-${day}T$time$formattedTimezone';
        print('🔍 ISO 변환: $isoDate');
        
        final parsedDate = DateTime.parse(isoDate);
        print('✅ 파싱 성공: $parsedDate');
        return parsedDate;
      }
      
      // 파싱 실패 시 현재 시간 반환
      return DateTime.now();
    } catch (e) {

      print('날짜 파싱 오류: $pubDate -> $e');
      return DateTime.now(); // 파싱 실패 시 현재 시간으로 대체
    }
  }

  // 상대 시간 표시 (몇 시간 전, 며칠 전)
  String get timeAgo {
    final publishedTime = publishedDateTime;
    if (publishedTime == null) return '시간 정보 없음';

    final now = DateTime.now();
    final difference = now.difference(publishedTime);

    if (difference.inDays > 30) {
      return '${(difference.inDays / 30).floor()}개월 전';
    } else if (difference.inDays > 0) {
      return '${difference.inDays}일 전';
    } else if (difference.inHours > 0) {
      return '${difference.inHours}시간 전';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes}분 전';
    } else if (difference.inSeconds > 0) {
      return '${difference.inSeconds}초 전';
    } else {
      return '방금 전';
    }
  }

  // 이미지가 있는지 확인
  bool get hasImage => imageUrl != null && imageUrl!.isNotEmpty;
}
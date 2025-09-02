class NewsModel {
  final String id;
  final String title;
  final String content;
  final String imageUrl;
  final DateTime publishedAt;
  final String author;

  NewsModel({
    required this.id,
    required this.title,
    required this.content,
    required this.imageUrl,
    required this.publishedAt,
    required this.author,
  });

  // 더미 데이터 생성을 위한 factory constructor
  factory NewsModel.dummy(int index) {
    return NewsModel(
      id: 'news_$index',
      title: _getDummyTitle(index),
      content: _getDummyContent(index),
      imageUrl: 'https://flutter.dev/assets/images/shared/brand/flutter/logo/flutter-lockup.png',
      publishedAt: DateTime.now().subtract(Duration(hours: index * 2)),
      author: _getDummyAuthor(index),
    );
  }

  static String _getDummyTitle(int index) {
    final titles = [
      'Flutter 3.0 출시, 웹과 모바일 통합 개발 지원',
      'IOI 2024 국제 정보올림피아드 개최',
      'AI 기술의 미래: 차세대 개발 도구들',
      'Dart 언어 업데이트: 새로운 기능들',
      '웹 개발의 새로운 패러다임 변화',
      '모바일 앱 개발 트렌드 2024',
      '개발자를 위한 최신 도구 소개',
      '소프트웨어 엔지니어링 베스트 프랙티스',
    ];
    return titles[index % titles.length];
  }

  static String _getDummyContent(int index) {
    final contents = [
      '최신 Flutter 버전이 출시되면서 웹과 모바일 플랫폼 간의 완벽한 통합이 가능해졌습니다. 개발자들은 이제 하나의 코드베이스로 다양한 플랫폼을 지원할 수 있습니다.',
      '올해 IOI 대회가 성공적으로 개최되었으며, 전 세계 학생들이 프로그래밍 실력을 겨뤘습니다. 새로운 알고리즘 문제들이 출제되어 참가자들에게 도전이 되었습니다.',
      '인공지능 기술이 소프트웨어 개발 분야에 혁명을 일으키고 있습니다. 자동 코드 생성부터 버그 탐지까지, AI는 개발자들의 생산성을 크게 향상시키고 있습니다.',
      'Dart 언어의 최신 업데이트가 발표되었습니다. 새로운 문법과 기능들이 추가되어 더욱 효율적인 개발이 가능해졌습니다.',
      '웹 개발 분야에서 새로운 패러다임이 등장하고 있습니다. JAMstack, 서버리스 아키텍처 등이 주목받고 있습니다.',
      '2024년 모바일 앱 개발 트렌드를 분석해보면, 크로스 플랫폼 개발과 AI 통합이 주요 키워드로 떠오르고 있습니다.',
      '개발자들의 생산성을 높이는 최신 도구들을 소개합니다. IDE부터 디버깅 도구까지 다양한 솔루션들이 있습니다.',
      '소프트웨어 엔지니어링에서 중요한 베스트 프랙티스들을 정리했습니다. 코드 품질과 유지보수성을 높이는 방법들을 알아보세요.',
    ];
    return contents[index % contents.length];
  }

  static String _getDummyAuthor(int index) {
    final authors = [
      'Flutter 개발팀',
      'IOI 위원회',
      'AI 리서치팀',
      'Dart 언어팀',
      '웹 개발 전문가',
      '모바일 개발자',
      '기술 리뷰어',
      '소프트웨어 아키텍트',
    ];
    return authors[index % authors.length];
  }
}
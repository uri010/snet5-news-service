import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'theme/app_theme.dart';
import 'pages/home_page.dart';

void main() async {
  // Flutter 바인딩 초기화
  WidgetsFlutterBinding.ensureInitialized();
  
  // 환경변수 로드
  try {
    await dotenv.load(fileName: "config.env");
    print('✅ 환경변수 로드 완료');
    print('🔗 API_BASE_URL: ${dotenv.env['API_BASE_URL']}');
  } catch (e) {
    print('⚠️ 환경변수 로드 실패: $e');
    print('📝 기본값 사용');
  }
  
  runApp(const IOINewsApp());
}

class IOINewsApp extends StatelessWidget {
  const IOINewsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'IOI NEWS',
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.system,
      home: const HomePage(),
      debugShowCheckedModeBanner: false,
    );
  }
}



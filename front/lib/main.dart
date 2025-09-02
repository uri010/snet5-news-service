import 'package:flutter/material.dart';
import 'theme/app_theme.dart';
import 'pages/home_page.dart';

void main() {
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



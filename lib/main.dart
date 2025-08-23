import 'package:flutter/material.dart';
import 'package:photomanager_practice/services/auto_upload_service.dart';
import 'package:provider/provider.dart';
import 'package:photomanager_practice/provider/theme_provider.dart';
import 'package:photomanager_practice/screen/splash_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AutoUploadService.instance.init();
  runApp(
    ChangeNotifierProvider(
      create: (_) => ThemeProvider(),
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      themeMode: themeProvider.themeMode,
      theme: themeProvider.lightTheme,
      darkTheme: themeProvider.darkTheme,
      home: SplashScreen(),
    );
  }
}

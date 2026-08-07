import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'package:photomanager_practice/services/auto_upload_service.dart';
import 'package:provider/provider.dart';
import 'package:photomanager_practice/provider/theme_provider.dart';
import 'package:photomanager_practice/screen/splash_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ✅ Your existing auto-upload service stays
  await AutoUploadService.instance.init();

  runApp(
    ChangeNotifierProvider(
      create: (_) => ThemeProvider(),
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  @override
  void initState() {
    super.initState();
  }

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

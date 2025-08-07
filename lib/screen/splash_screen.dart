import 'package:flutter/material.dart';
import 'dart:async';
import 'package:photomanager_practice/screen/welcome_screen.dart';

class SplashScreen extends StatefulWidget {
  @override
  _SplashScreenState createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    // Wait 2 seconds then navigate to WelcomeScreen
    Timer(Duration(seconds: 2), () {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => WelcomeScreen()),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context); // Get the current theme

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset('assets/images/logo1.png', width: 200, height: 150),
            const SizedBox(height: 20),
            CircularProgressIndicator(
              color: theme.colorScheme.primary, // adapt to theme
            ),
          ],
        ),
      ),
    );
  }
}

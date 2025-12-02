import 'package:flutter/material.dart';
import 'package:photomanager_practice/provider/theme_provider.dart';
import 'package:provider/provider.dart';
import 'login_screen.dart';

class WelcomeScreen extends StatefulWidget {
  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final themeData = Theme.of(context);

    return Scaffold(
      backgroundColor: themeData.scaffoldBackgroundColor,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Logo
              Image.asset(
                'assets/images/company_logo.png',
                width: 250,
                height: 150,
              ),
              const SizedBox(height: 10),

              // Welcome Text
              Text(
                'Welcome to ScanVault',
                style: themeData.textTheme.titleLarge, // auto adapts to theme
              ),
              const SizedBox(height: 40),

              // Login Button
              ElevatedButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => LoginScreen()),
                  );
                },
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 80,
                    vertical: 16,
                  ),
                  backgroundColor: themeData.colorScheme.primary, // ORANGE
                  foregroundColor:
                      themeData.colorScheme.onPrimary, // WHITE text auto
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  elevation: 5,
                ),
                child: const Text("Log In", style: TextStyle(fontSize: 20)),
              ),

              const SizedBox(height: 30),

              // Dark Mode Toggle
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    themeProvider.isDarkMode
                        ? Icons.nightlight_round
                        : Icons.wb_sunny,
                    color: themeData.colorScheme.secondary, // BLUE
                  ),
                  const SizedBox(width: 8),
                  Text(
                    themeProvider.isDarkMode ? 'Dark Mode' : 'Light Mode',
                    style: themeData.textTheme.bodyMedium,
                  ),
                  const SizedBox(width: 8),
                  Switch(
                    value: themeProvider.isDarkMode,
                    onChanged: (val) => themeProvider.toggleTheme(val),
                    activeColor: themeData.colorScheme.primary, // ORANGE
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

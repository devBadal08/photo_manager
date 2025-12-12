import 'package:flutter/material.dart';
import 'package:photomanager_practice/screen/folder_screen.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class LoginScreen extends StatefulWidget {
  @override
  _LoginScreenState createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;

  @override
  void initState() {
    super.initState();
    _loadSavedCredentials();
  }

  Future<void> _loadSavedCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    final savedEmail = prefs.getString('email');
    final savedPassword = prefs.getString('password');

    if (savedEmail != null) {
      _emailController.text = savedEmail;
    }
    if (savedPassword != null) {
      _passwordController.text = savedPassword;
    }
  }

  Future<void> login(String email, String password) async {
    try {
      final response = await http.post(
        Uri.parse('http://192.168.1.10:8000/api/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email, 'password': password}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final token = data['token'];
        final userId = data['user']['id'].toString();
        final userName = data['user']['name'];
        final userEmail = data['user']['email'];
        final prefs = await SharedPreferences.getInstance();

        final companies = data['user']['companies'] ?? [];

        // Save full companies list
        prefs.setString("companies", jsonEncode(companies));

        if (companies.isNotEmpty) {
          // Default selected company = first company
          prefs.setInt("selected_company_id", companies[0]["id"]);

          // Save the logo of selected company
          final rawLogo = companies[0]["company_logo"];
          if (rawLogo != null && rawLogo.isNotEmpty) {
            prefs.setString(
              "company_logo",
              "http://192.168.1.10:8000/storage/$rawLogo",
            );
          } else {
            prefs.remove("company_logo");
          }
        } else {
          // No companies assigned
          prefs.remove("selected_company_id");
          prefs.remove("company_logo");
        }

        await prefs.setString('auth_token', token ?? '');
        await prefs.setString('user_id', userId);
        await prefs.setString('user_name', userName ?? '');
        await prefs.setString('email', userEmail ?? '');
        await prefs.setString('password', password);

        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => FolderScreen(userId: userId)),
        );
      } else if (response.statusCode == 403) {
        showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: Text("Access Denied"),
            content: Text("You do not have permission to login."),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text("OK"),
              ),
            ],
          ),
        );
      } else {
        final error = jsonDecode(response.body)['message'] ?? "Login failed";
        showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: Text("Login Failed"),
            content: Text(error),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text("OK"),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      print("Error: $e");

      if (!mounted) return;

      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: Text("Error"),
          content: Text("Network error: $e"),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text("OK"),
            ),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final textTheme = theme.textTheme;
    final colorScheme = theme.colorScheme;

    return Scaffold(
      body: Container(
        color: theme.scaffoldBackgroundColor,
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: theme.cardColor,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  if (!isDark)
                    BoxShadow(
                      color: Colors.black12,
                      blurRadius: 10,
                      offset: Offset(0, 5),
                    ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Image.asset(
                    'assets/images/logo1.png',
                    width: 250,
                    height: 150,
                  ),
                  Text(
                    "Welcome!",
                    style:
                        textTheme.headlineSmall?.copyWith(fontSize: 26) ??
                        const TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.bold,
                          inherit: true,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    "Login to continue",
                    style:
                        textTheme.bodyMedium?.copyWith(fontSize: 16) ??
                        const TextStyle(fontSize: 16, inherit: true),
                  ),
                  const SizedBox(height: 30),

                  // Email
                  TextField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: InputDecoration(
                      labelText: "Email",
                      prefixIcon: const Icon(Icons.email),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: Colors.deepPurple),
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Password
                  TextField(
                    controller: _passwordController,
                    obscureText: _obscurePassword,
                    decoration: InputDecoration(
                      labelText: "Password",
                      prefixIcon: const Icon(Icons.lock),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscurePassword
                              ? Icons.visibility_off
                              : Icons.visibility,
                        ),
                        onPressed: () {
                          setState(() {
                            _obscurePassword = !_obscurePassword;
                          });
                        },
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: Colors.deepPurple),
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),

                  ElevatedButton(
                    onPressed: () {
                      final email = _emailController.text.trim();
                      final password = _passwordController.text.trim();

                      if (email.isNotEmpty && password.isNotEmpty) {
                        login(email, password);
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text("Please enter email and password"),
                          ),
                        );
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: colorScheme.primary,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 80,
                        vertical: 16,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      elevation: 5,
                    ),
                    child: const Text("Login", style: TextStyle(fontSize: 20)),
                  ),
                  const SizedBox(height: 30),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

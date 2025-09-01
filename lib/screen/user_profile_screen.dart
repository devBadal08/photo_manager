import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class UserProfileScreen extends StatefulWidget {
  const UserProfileScreen({Key? key}) : super(key: key);

  @override
  State<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends State<UserProfileScreen> {
  String userName = '';
  String? email;
  String? companyLogo;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      userName = prefs.getString('user_name') ?? 'Guest';
      email = prefs.getString('email');
      companyLogo = prefs.getString('company_logo');
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('User Profile'),
        backgroundColor: theme.appBarTheme.backgroundColor,
        foregroundColor: theme.appBarTheme.foregroundColor,
        elevation: theme.appBarTheme.elevation,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // 🖼️ Big company logo with border
            if (companyLogo != null && companyLogo!.isNotEmpty)
              Container(
                height: 180,
                width: double.infinity,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: Colors.deepPurple, // border color
                    width: 3, // border thickness
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Image.network(
                    companyLogo!,
                    fit: BoxFit.contain, // or BoxFit.cover if you prefer
                  ),
                ),
              )
            else
              Container(
                height: 180,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: theme.colorScheme.secondary.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.deepPurple, width: 3),
                ),
                child: Icon(
                  Icons.business,
                  size: 80,
                  color: theme.iconTheme.color,
                ),
              ),

            const SizedBox(height: 20),

            // 👤 User info card
            Card(
              color: theme.cardColor,
              elevation: 4,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: ListTile(
                title: Text(
                  userName,
                  style: textTheme.headlineSmall?.copyWith(fontSize: 20),
                ),
                subtitle: Text(
                  email ?? 'No email found',
                  style: textTheme.bodyMedium?.copyWith(fontSize: 16),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

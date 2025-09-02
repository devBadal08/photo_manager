import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:photomanager_practice/widgets/diceBearAvatar.dart';

class UserProfileScreen extends StatefulWidget {
  const UserProfileScreen({Key? key}) : super(key: key);

  @override
  State<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends State<UserProfileScreen> {
  String userName = '';
  String? email;
  String? companyLogo;
  String? avatarSeed;

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
      avatarSeed = prefs.getString('user_avatar_seed') ?? 'defaultSeed';
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('User Profile')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // 🖼️ Company Logo
            if (companyLogo != null && companyLogo!.isNotEmpty)
              Container(
                height: 100,
                width: double.infinity,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.deepPurple, width: 3),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Image.network(companyLogo!, fit: BoxFit.contain),
                ),
              )
            else
              Container(
                height: 100,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: theme.colorScheme.secondary.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.deepPurple, width: 3),
                ),
                child: const Icon(Icons.business, size: 60),
              ),

            const SizedBox(height: 20),

            // 👤 Avatar + User Info Card
            Card(
              color: theme.cardColor,
              elevation: 4,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // 👤 Avatar on left
                    DiceBearAvatar(seed: avatarSeed ?? userName, size: 60),

                    const SizedBox(width: 16),

                    // 📛 Name + Email on right (full width)
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            userName,
                            style: textTheme.headlineSmall?.copyWith(
                              fontSize: 20,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            email ?? 'No email found',
                            style: textTheme.bodyMedium?.copyWith(fontSize: 16),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

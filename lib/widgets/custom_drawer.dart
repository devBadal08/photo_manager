import 'dart:io';
import 'package:flutter/material.dart';
import '../screen/login_screen.dart';
import '../screen/user_profile_screen.dart';
import '../services/folder_service.dart';
import '../provider/theme_provider.dart';
import 'package:provider/provider.dart';

class CustomDrawer extends StatefulWidget {
  final String userName;
  final File? avatarImage;
  final BuildContext parentContext; // FolderScreen context

  const CustomDrawer({
    super.key,
    required this.userName,
    required this.avatarImage,
    required this.parentContext,
  });

  @override
  State<CustomDrawer> createState() => _CustomDrawerState();
}

class _CustomDrawerState extends State<CustomDrawer> {
  void _showLogoutDialog(BuildContext context) {
    FolderService().showLogoutDialog(context, () {
      if (mounted) {
        // 1️⃣ Close the logout confirmation dialog
        Navigator.of(context).pop();

        // 2️⃣ Close the custom drawer dialog
        Navigator.of(widget.parentContext).pop();

        // 3️⃣ Navigate to login screen using parent context
        Navigator.pushReplacement(
          widget.parentContext,
          MaterialPageRoute(builder: (_) => LoginScreen()),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topLeft,
      child: Padding(
        padding: const EdgeInsets.only(left: 12.0, top: 50.0),
        child: Material(
          elevation: 12,
          borderRadius: BorderRadius.circular(24),
          color: Theme.of(context).colorScheme.surface,
          child: Container(
            width: MediaQuery.of(context).size.width * 0.75,
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Consumer<ThemeProvider>(
              builder: (context, themeProvider, _) {
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ListTile(
                      leading: CircleAvatar(
                        radius: 24,
                        backgroundColor: Colors.deepPurple,
                        backgroundImage: widget.avatarImage != null
                            ? FileImage(widget.avatarImage!)
                            : null,
                        child: widget.avatarImage == null
                            ? const Icon(Icons.person, color: Colors.white)
                            : null,
                      ),
                      title: Text(
                        widget.userName,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                      ),
                    ),
                    const Divider(),
                    ListTile(
                      leading: const Icon(Icons.person),
                      title: const Text("User Profile"),
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(
                          widget.parentContext,
                          MaterialPageRoute(
                            builder: (_) => const UserProfileScreen(),
                          ),
                        );
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.logout),
                      title: const Text("Logout"),
                      onTap: () {
                        _showLogoutDialog(context);
                      },
                    ),
                    const Divider(),
                    ListTile(
                      leading: Icon(
                        themeProvider.isDarkMode
                            ? Icons.nightlight_round
                            : Icons.wb_sunny,
                      ),
                      title: Text(
                        themeProvider.isDarkMode ? 'Dark Mode' : 'Light Mode',
                      ),
                      trailing: Switch(
                        value: themeProvider.isDarkMode,
                        onChanged: (val) {
                          themeProvider.toggleTheme(val);
                        },
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

import 'dart:async';
import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:photomanager_practice/screen/shared_with_me_screen.dart';
import 'package:photomanager_practice/services/auto_upload_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../screen/login_screen.dart';
import '../screen/user_profile_screen.dart';
import '../services/folder_service.dart';
import '../provider/theme_provider.dart';
import 'package:provider/provider.dart';

class CustomDrawer extends StatefulWidget {
  final String userName;
  final File? avatarImage;
  final BuildContext parentContext; // FolderScreen context
  final VoidCallback? onDelete;

  const CustomDrawer({
    super.key,
    required this.userName,
    required this.avatarImage,
    required this.parentContext,
    this.onDelete,
  });

  @override
  State<CustomDrawer> createState() => _CustomDrawerState();
}

class _CustomDrawerState extends State<CustomDrawer> {
  bool _deleteEnabled = false;
  bool _autoUploadEnabled = false;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;

  @override
  void initState() {
    super.initState();
    // restore saved toggle state
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _autoUploadEnabled = prefs.getBool("auto_upload") ?? false;
    });

    if (_autoUploadEnabled) {
      _startAutoUploadListener();

      final current = await Connectivity().checkConnectivity();
      if (current == ConnectivityResult.wifi ||
          current == ConnectivityResult.mobile) {
        await AutoUploadService.instance.setAutoUpload(true);
      }
    }
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool("auto_upload", _autoUploadEnabled);
  }

  void _startAutoUploadListener() {
    _connectivitySubscription?.cancel();
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((
      results,
    ) async {
      // `results` is a List<ConnectivityResult>
      if (results.isNotEmpty) {
        final result = results.first; // Pick the first available connectivity
        if (_autoUploadEnabled &&
            (result == ConnectivityResult.wifi ||
                result == ConnectivityResult.mobile)) {
          await AutoUploadService.instance.setAutoUpload(true);
        }
      }
    });
  }

  void _stopAutoUploadListener() {
    _connectivitySubscription?.cancel();
    _connectivitySubscription = null;
  }

  @override
  void dispose() {
    _stopAutoUploadListener();
    super.dispose();
  }

  Future<Set<String>> _getUploadedFiles() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList("uploaded_files") ?? [];
    return list.toSet();
  }

  Future<void> _deleteAllImages() async {
    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      String? userId = prefs.getInt('user_id')?.toString();
      final directory = Directory("/storage/emulated/0/Pictures/MyApp/$userId");

      final uploaded = await _getUploadedFiles();

      if (await directory.exists()) {
        int deleted = 0, skipped = 0;

        await for (var entity in directory.list(recursive: true)) {
          if (entity is File) {
            final path = entity.path;

            if (path.endsWith(".jpg") ||
                path.endsWith(".jpeg") ||
                path.endsWith(".png")) {
              if (uploaded.contains(path)) {
                await entity.delete();
                deleted++;
              } else {
                skipped++;
              }
            }
          }
        }

        if (widget.onDelete != null) {
          widget.onDelete!();
        }

        if (mounted) {
          ScaffoldMessenger.of(widget.parentContext).showSnackBar(
            SnackBar(
              content: Text(
                "Deleted $deleted photos. Skipped $skipped not uploaded.",
              ),
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(widget.parentContext).showSnackBar(
            const SnackBar(content: Text("No images found to delete")),
          );
        }
      }
    } catch (e) {
      debugPrint("❌ Error deleting images: $e");
      if (mounted) {
        ScaffoldMessenger.of(widget.parentContext).showSnackBar(
          const SnackBar(content: Text("Failed to delete images")),
        );
      }
    }
  }

  void _confirmDelete() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Delete All Images?"),
        content: const Text(
          "Are you sure you want to delete all images from the app? This action cannot be undo.",
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context); // close dialog
              setState(() {
                _deleteEnabled = false; // reset switch
              });
            },
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context); // close dialog
              await _deleteAllImages();
              // Close the drawer automatically after deleting
              if (mounted) {
                Navigator.of(widget.parentContext).pop();
              }
            },
            child: const Text("Delete"),
          ),
        ],
      ),
    );
  }

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
                      leading: const Icon(Icons.cloud_upload),
                      title: const Text("Auto Upload"),
                      trailing: Switch(
                        value: AutoUploadService.instance.isEnabled,
                        onChanged: (val) async {
                          await AutoUploadService.instance.setAutoUpload(val);
                          setState(() {}); // refresh the toggle UI
                        },
                      ),
                    ),
                    ListTile(
                      leading: const Icon(Icons.delete_forever),
                      title: const Text("Delete All Images"),
                      trailing: Switch(
                        value: _deleteEnabled,
                        onChanged: (val) {
                          setState(() {
                            _deleteEnabled = val;
                          });
                          if (val) {
                            _confirmDelete();
                          }
                        },
                      ),
                    ),
                    ListTile(
                      leading: const Icon(Icons.folder_shared),
                      title: const Text("Shared With Me"),
                      onTap: () {
                        Navigator.pop(context); // close drawer
                        Navigator.push(
                          widget.parentContext,
                          MaterialPageRoute(
                            builder: (_) => const SharedWithMeScreen(),
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

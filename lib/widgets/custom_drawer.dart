import 'dart:async';
import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:photomanager_practice/services/auto_upload_service.dart';
import 'package:photomanager_practice/services/bottom_tabs.dart';
import 'package:photomanager_practice/services/photo_service.dart';
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
        _uploadPendingImages();
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
    ) {
      // `results` is a List<ConnectivityResult>
      if (results.isNotEmpty) {
        final result = results.first; // Pick the first available connectivity
        if (_autoUploadEnabled &&
            (result == ConnectivityResult.wifi ||
                result == ConnectivityResult.mobile)) {
          _uploadPendingImages();
        }
      }
    });
  }

  void _stopAutoUploadListener() {
    _connectivitySubscription?.cancel();
    _connectivitySubscription = null;
  }

  // 🔥 Auto-upload implementation
  Future<void> _uploadPendingImages() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getInt('user_id')?.toString();
      if (userId == null) return;

      final userFolder = Directory(
        "/storage/emulated/0/Pictures/MyApp/$userId",
      );
      if (!await userFolder.exists()) return;

      final files = userFolder
          .listSync(recursive: true)
          .whereType<File>()
          .where(
            (f) =>
                f.path.endsWith(".jpg") ||
                f.path.endsWith(".jpeg") ||
                f.path.endsWith(".png"),
          )
          .toList();

      for (var file in files) {
        if (!BottomTabs.uploadedFiles.value.contains(file.path)) {
          // 🔹 Upload each image
          final photoService = PhotoService();
          final success = await photoService.uploadImagesToServer();
          if (success) {
            // ✅ mark as uploaded
            BottomTabs.uploadedFiles.value = {
              ...BottomTabs.uploadedFiles.value,
              file.path,
            };
          }
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(
          widget.parentContext,
        ).showSnackBar(const SnackBar(content: Text("Auto-upload completed")));
      }
    } catch (e) {
      debugPrint("❌ Auto-upload failed: $e");
    }
  }

  @override
  void dispose() {
    _stopAutoUploadListener();
    super.dispose();
  }

  Future<void> _deleteAllImages() async {
    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      String? userId = prefs.getInt('user_id')?.toString();
      final directory = Directory("/storage/emulated/0/Pictures/MyApp/$userId");

      if (await directory.exists()) {
        // Loop through ALL files in directory + subfolders
        if (widget.onDelete != null) {
          widget.onDelete!(); // 🔥 Tell parent to refresh UI
        }
        await for (var entity in directory.list(
          recursive: true,
          followLinks: false,
        )) {
          if (entity is File) {
            final path = entity.path.toLowerCase();
            if (path.endsWith(".jpg") ||
                path.endsWith(".jpeg") ||
                path.endsWith(".png")) {
              await entity.delete();
            }
          }
        }

        // ✅ now call refresh AFTER files are deleted
        if (widget.onDelete != null) {
          widget.onDelete!();
        }

        if (mounted) {
          ScaffoldMessenger.of(widget.parentContext).showSnackBar(
            const SnackBar(content: Text("All images deleted successfully")),
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

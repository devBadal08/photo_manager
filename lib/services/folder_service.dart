import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FolderService {
  Future<String> loadUserName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('user_name') ?? 'Guest';
  }

  Future<File?> loadAvatar() async {
    final prefs = await SharedPreferences.getInstance();
    final avatarPath = prefs.getString('avatar_path');
    if (avatarPath != null && File(avatarPath).existsSync()) {
      return File(avatarPath);
    }
    return null;
  }

  Future<Map<String, int>> countFoldersAndImages() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getInt('user_id');

    if (userId == null) return {'folders': 0, 'images': 0};

    final Directory rootDir = Directory(
      '/storage/emulated/0/Pictures/MyApp/$userId',
    );
    if (!rootDir.existsSync()) return {'folders': 0, 'images': 0};

    int totalFolders = 0;
    int totalImages = 0;

    void traverse(Directory dir) {
      for (FileSystemEntity entity in dir.listSync()) {
        if (entity is Directory) {
          totalFolders++;
          traverse(entity);
        } else if (entity is File &&
            ['.jpg', '.jpeg', '.png'].any((ext) => entity.path.endsWith(ext))) {
          totalImages++;
        }
      }
    }

    traverse(rootDir);
    return {'folders': totalFolders, 'images': totalImages};
  }

  Future<List<Directory>> loadFolders() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getInt('user_id');
    if (userId == null) return [];

    final baseDir = Directory('/storage/emulated/0/Pictures/MyApp/$userId');
    if (!await baseDir.exists()) await baseDir.create(recursive: true);

    return baseDir
        .listSync()
        .whereType<Directory>()
        .where((dir) => !dir.path.contains('/flutter_assets'))
        .toList();
  }

  Future<bool> createFolder(String folderName) async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getInt('user_id')?.toString();
    if (userId == null) return false;

    final dir = Directory(
      '/storage/emulated/0/Pictures/MyApp/$userId/$folderName',
    );
    if (await dir.exists()) return false;

    await dir.create(recursive: true);
    return true;
  }

  Future<void> logoutUser() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
  }

  Future<File?> pickAndSaveAvatar() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('avatar_path', picked.path);
      return File(picked.path);
    }
    return null;
  }

  void showCameraDisabledMessage(BuildContext context) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text("Camera is disabled")));
  }

  void showLogoutDialog(BuildContext context, VoidCallback onLogout) {
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: Text('Logout'),
          content: Text('Are you sure you want to logout?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
                onLogout(); // trigger logout logic after dialog is dismissed
              },
              child: Text('Logout'),
            ),
          ],
        );
      },
    );
  }
}

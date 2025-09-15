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

  Future<Map<String, int>> countSubfoldersAndImages(Directory folder) async {
    int subfolders = 0;
    int images = 0;

    if (!await folder.exists()) {
      return {'subfolders': 0, 'images': 0}; // or throw a friendly error
    }

    final files = folder.listSync();

    for (var file in files) {
      if (file is Directory) {
        subfolders++;
      } else if (file is File &&
          (file.path.endsWith('.jpg') ||
              file.path.endsWith('.jpeg') ||
              file.path.endsWith('.png'))) {
        images++;
      }
    }

    return {'subfolders': subfolders, 'images': images};
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
    await prefs.remove('auth_token');
    await prefs.remove('email');
    await prefs.remove('password');
    await prefs.remove('user_id');
    await prefs.remove('user_name');
    await prefs.remove('company_logo');
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

  void showLogoutDialog(BuildContext context, VoidCallback onConfirm) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Logout"),
        content: const Text("Are you sure you want to logout?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx), // cancel
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () {
              logoutUser();
              Navigator.pop(ctx); // Close dialog
              onConfirm();
            },
            child: const Text("Logout"),
          ),
        ],
      ),
    );
  }

  Future<bool> renameFolder(String oldPath, String newName) async {
    try {
      final oldDirectory = Directory(oldPath);
      final newPath = "${oldDirectory.parent.path}/$newName";
      final newDirectory = Directory(newPath);

      if (await oldDirectory.exists()) {
        await oldDirectory.rename(newDirectory.path);
        return true;
      }
      return false;
    } catch (e) {
      print("Rename error: $e");
      return false;
    }
  }

  Future<bool> deleteFolder(String path) async {
    try {
      final directory = Directory(path);
      if (await directory.exists()) {
        await directory.delete(recursive: true);
        return true;
      }
      return false;
    } catch (e) {
      print("Delete error: $e");
      return false;
    }
  }
}

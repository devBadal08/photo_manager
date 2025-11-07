import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FolderService {
  Future<String> loadUserId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('userId') ?? '';
  }

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

  Future<Map<String, int>> countFoldersImagesVideos() async {
    int folderCount = 0;
    int imageCount = 0;
    int videoCount = 0;

    final Directory appDir = await getApplicationDocumentsDirectory();
    final List<FileSystemEntity> entities = appDir.listSync(recursive: true);

    for (final entity in entities) {
      if (entity is Directory) {
        folderCount++;
      } else if (entity is File) {
        final path = entity.path.toLowerCase();
        if (path.endsWith('.jpg') ||
            path.endsWith('.jpeg') ||
            path.endsWith('.png')) {
          imageCount++;
        } else if (path.endsWith('.mp4')) {
          videoCount++;
        }
      }
    }

    return {'folders': folderCount, 'images': imageCount, 'videos': videoCount};
  }

  Future<Map<String, int>> countSubfoldersImagesVideos(Directory folder) async {
    int subfolderCount = 0;
    int imageCount = 0;
    int videoCount = 0;
    int pdfCount = 0;

    final List<FileSystemEntity> entities = folder.listSync();

    for (final entity in entities) {
      if (entity is Directory) {
        subfolderCount++;
      } else if (entity is File) {
        final path = entity.path.toLowerCase();
        if (path.endsWith('.jpg') ||
            path.endsWith('.jpeg') ||
            path.endsWith('.png')) {
          imageCount++;
        } else if (path.endsWith('.mp4')) {
          videoCount++;
        } else if (path.endsWith('.pdf')) {
          pdfCount++;
        }
      }
    }

    return {
      'subfolders': subfolderCount,
      'images': imageCount,
      'videos': videoCount,
      'pdfs': pdfCount,
    };
  }

  Future<List<Directory>> loadFolders() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getString('user_id');
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
    final userId = prefs.getString('user_id')?.toString();
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

  Future<String?> getAuthToken() async {
    // Example using SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('auth_token');
  }

  void showCameraDisabledMessage(BuildContext context) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text("Camera is disabled")));
  }

  void showScanDisabledMessage(BuildContext context) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text("Scan is disabled")));
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

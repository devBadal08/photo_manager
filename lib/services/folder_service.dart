import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:photomanager_practice/services/photo_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FolderService {
  Future<String?> loadUserId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('user_id');
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
    int pdfCount = 0;

    final root = await PhotoService.getUserRootDir();
    if (root == null) return {};

    for (final entity in root.listSync(recursive: true)) {
      if (entity is Directory) {
        folderCount++;
      } else if (entity is File) {
        final p = entity.path.toLowerCase();
        if (p.endsWith('.jpg') || p.endsWith('.jpeg') || p.endsWith('.png')) {
          imageCount++;
        } else if (p.endsWith('.mp4')) {
          videoCount++;
        } else if (p.endsWith('.pdf')) {
          pdfCount++;
        }
      }
    }

    return {
      'folders': folderCount,
      'images': imageCount,
      'videos': videoCount,
      'pdfs': pdfCount,
    };
  }

  Future<Map<String, int>> countSubfoldersImagesVideos(Directory folder) async {
    int subfolders = 0;
    int images = 0;
    int videos = 0;
    int pdfs = 0;

    for (final entity in folder.listSync()) {
      if (entity is Directory) {
        subfolders++;
      } else if (entity is File) {
        final p = entity.path.toLowerCase();
        if (p.endsWith('.jpg') || p.endsWith('.jpeg') || p.endsWith('.png')) {
          images++;
        } else if (p.endsWith('.mp4')) {
          videos++;
        } else if (p.endsWith('.pdf')) {
          pdfs++;
        }
      }
    }

    return {
      'subfolders': subfolders,
      'images': images,
      'videos': videos,
      'pdfs': pdfs,
    };
  }

  Future<List<Directory>> loadFolders() async {
    final baseDir = await PhotoService.getUserRootDir();
    if (baseDir == null) return [];

    if (!await baseDir.exists()) {
      await baseDir.create(recursive: true);
    }

    return baseDir.listSync().whereType<Directory>().toList();
  }

  Future<bool> createFolder(String folderName) async {
    final baseDir = await PhotoService.getUserRootDir();
    if (baseDir == null) return false;

    if (!await baseDir.exists()) {
      await baseDir.create(recursive: true);
    }

    final dir = Directory('${baseDir.path}/$folderName');

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

  static Future<int?> getFolderIdFromDisk(Directory folder) async {
    final baseDir = await getExternalStorageDirectory();

    print('🧪 GET FOLDER ID FROM DISK');
    print('➡️ Incoming folder path: ${folder.path}');
    print('➡️ Incoming folder name: ${folder.path.split('/').last}');

    if (baseDir == null) {
      print('❌ baseDir is NULL');
      return null;
    }

    print('➡️ baseDir path: ${baseDir.path}');

    final metaDir = Directory('${baseDir.path}/folder_meta');

    if (!await metaDir.exists()) {
      print('❌ metaDir does NOT exist at: ${metaDir.path}');
      return null;
    }

    print('➡️ metaDir found: ${metaDir.path}');

    for (final file in metaDir.listSync()) {
      print('📄 Reading meta file: ${file.path}');

      try {
        final data = jsonDecode(await File(file.path).readAsString());

        final savedName = data['folder_name'];
        final savedId = data['folder_id'];
        final currentName = folder.path.split('/').last;

        print('🔍 Comparing');
        print('   savedName = $savedName');
        print('   currentName = $currentName');
        print('   savedId = $savedId');

        if (data['folder_path'] == folder.path) {
          print('✅ MATCH FOUND → folder_id = $savedId');
          return savedId;
        }
      } catch (e) {
        print('❌ Failed to read meta file ${file.path}: $e');
      }
    }

    print('⚠️ NO MATCH FOUND → returning null');
    return null;
  }

  static Future<void> updateFolderMetaName(int folderId, String newName) async {
    final baseDir = await getExternalStorageDirectory();
    if (baseDir == null) return;

    final metaFile = File('${baseDir.path}/folder_meta/folder_$folderId.json');

    if (!await metaFile.exists()) return;

    final data = jsonDecode(await metaFile.readAsString());
    data['folder_name'] = newName;

    await metaFile.writeAsString(jsonEncode(data));
  }
}

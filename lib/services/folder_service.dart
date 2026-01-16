import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';

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
    int pdfCount = 0;

    final baseDir = await _getBaseFolder();
    if (baseDir == null || !await baseDir.exists()) {
      return {'folders': 0, 'images': 0, 'videos': 0, 'pdfs': 0};
    }

    for (final entity in baseDir.listSync(recursive: true)) {
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
        } else if (path.endsWith('.pdf')) {
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
    final baseDir = await _getBaseFolder();
    if (baseDir == null) return [];

    if (!await baseDir.exists()) {
      await baseDir.create(recursive: true);
    }

    return baseDir.listSync().whereType<Directory>().toList();
  }

  Future<bool> createFolder(String folderName) async {
    final baseDir = await _getBaseFolder();
    if (baseDir == null) return false;

    if (!await baseDir.exists()) {
      await baseDir.create(recursive: true);
    }

    final dir = Directory('${baseDir.path}/$folderName');

    if (await dir.exists()) return false;

    await dir.create(recursive: true);
    return true;
  }

  Future<Directory?> _getBaseFolder() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getString('user_id');
    final companyId = prefs.getInt('selected_company_id');

    if (userId == null || companyId == null) return null;

    if (Platform.isAndroid) {
      return Directory('/storage/emulated/0/Pictures/MyApp/$companyId/$userId');
    } else {
      final docDir = await getApplicationDocumentsDirectory();
      return Directory('${docDir.path}/MyApp/$companyId/$userId');
    }
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

  Future<bool> renameFolderOnServer({
    required int folderId,
    required String newName,
  }) async {
    final token = await getAuthToken();

    final prefs = await SharedPreferences.getInstance();
    final companyId = prefs.getInt('selected_company_id');

    print('🧪 RENAME API DEBUG');
    print('➡️ folderId = $folderId (${folderId.runtimeType})');
    print('➡️ newName = $newName');
    print('➡️ companyId = $companyId');
    print('➡️ token exists = ${token != null}');
    //print('➡️ URL = $baseUrl/folder/$folderId/rename');

    final response = await http.put(
      Uri.parse('http://192.168.1.11:8000/api/folders/$folderId/rename'),
      headers: {
        'Authorization': 'Bearer $token',
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'name': newName, 'company_id': companyId}),
    );

    print('📝 Rename status: ${response.statusCode}');
    print('📝 Rename response: ${response.body}');

    return response.statusCode == 200;
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

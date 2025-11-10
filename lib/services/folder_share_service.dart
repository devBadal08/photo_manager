import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:photomanager_practice/services/photo_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FolderShareService {
  static const String baseUrl =
      "http://192.168.1.5:8000/api"; // change if needed

  // Helper: get token
  Future<String?> _getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString("auth_token");
  }

  static Future<int?> getFolderId(Directory folder) async {
    final folderName = folder.path.split('/').last;

    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString("auth_token");

    if (token == null) return null;

    final url = "$baseUrl/folders/id?name=$folderName";

    final response = await http.get(
      Uri.parse(url),
      headers: {"Authorization": "Bearer $token", "Accept": "application/json"},
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data['folder_id'];
    }
    return null;
  }

  Future<bool> shareFolderByEmail(int folderId, String email) async {
    final token = await _getToken();
    if (token == null) return false;

    final response = await http.post(
      Uri.parse("$baseUrl/folder/share"),
      headers: {
        "Authorization": "Bearer $token",
        "Accept": "application/json",
        "Content-Type": "application/json",
      },
      body: jsonEncode({'folder_id': folderId, 'shared_with': email}),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data['success'] == true;
    }
    return false;
  }

  // Get folders shared with me
  Future<List<dynamic>> getSharedWithMe() async {
    final token = await _getToken();
    if (token == null) return [];

    final response = await http.get(
      Uri.parse("$baseUrl/folder/my-shared"),
      headers: {"Authorization": "Bearer $token", "Accept": "application/json"},
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      print("📦 Shared API Response: $data");

      if (data is Map && data.containsKey('folders')) {
        // Extract the list of folders
        return data['folders'];
      }

      print("⚠️ Unexpected format: $data");
    } else {
      print(
        "❌ getSharedWithMe failed: ${response.statusCode} ${response.body}",
      );
    }

    return [];
  }

  // Get photos of a folder that was shared with me
  Future<Map<String, dynamic>?> getSharedFolderPhotos(int folderId) async {
    final token = await _getToken();
    if (token == null) return null;

    final response = await http.get(
      Uri.parse("$baseUrl/shared-folder/$folderId/photos"),
      headers: {"Authorization": "Bearer $token", "Accept": "application/json"},
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data; // contains { success: true, photos: [...] }
    } else {
      print("❌ Failed to load shared photos: ${response.body}");
      return null;
    }
  }

  // Upload multiple images to a shared folder
  Future<bool> uploadToSharedFolder(
    BuildContext context,
    int folderId,
    List<File> images,
    List<File> pdfs, // add scanned PDFs here
  ) async {
    final token = await _getToken();
    if (token == null) return false;

    String normalizeFileName(String path) => path.split('/').last.toLowerCase();

    // Step 1: Get already uploaded files from server
    final sharedData = await getSharedFolderPhotos(folderId);
    final Set<String> uploadedBasenames = {};

    if (sharedData != null && sharedData['photos'] != null) {
      for (var p in sharedData['photos']) {
        final path = p['path']?.toString();
        if (path != null) uploadedBasenames.add(normalizeFileName(path));
      }
    }

    // Combine images + PDFs for checking
    final allFiles = [...images, ...pdfs];

    print("Already uploaded: $uploadedBasenames");
    print(
      "Local to upload: ${allFiles.map((f) => normalizeFileName(f.path)).toList()}",
    );

    // Step 2: Filter out already uploaded files
    final List<File> remainingFiles = allFiles.where((file) {
      final name = normalizeFileName(file.path);
      return !uploadedBasenames.any((uploaded) => uploaded.endsWith(name));
    }).toList();

    // Step 3: Show message if nothing left to upload
    if (remainingFiles.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("No new files to upload.")));
      return true;
    }

    // Step 4: Show confirmation dialog
    final bool confirm = await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Confirm Upload"),
        content: Text(
          "${remainingFiles.length} file${remainingFiles.length > 1 ? 's' : ''} will be uploaded.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text("Upload"),
          ),
        ],
      ),
    );

    if (!confirm) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Upload cancelled.")));
      return false;
    }

    // Step 5: Upload remaining files
    final request = http.MultipartRequest(
      "POST",
      Uri.parse("$baseUrl/shared-folders/$folderId/upload"),
    );
    request.headers["Authorization"] = "Bearer $token";

    for (var file in remainingFiles) {
      final isPdf = file.path.toLowerCase().endsWith(".pdf");
      request.files.add(
        await http.MultipartFile.fromPath("files[]", file.path),
      );
    }

    final response = await request.send();
    final resStr = await response.stream.bytesToString();

    if (response.statusCode == 200) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            "Uploaded ${remainingFiles.length} file${remainingFiles.length > 1 ? 's' : ''}.",
          ),
        ),
      );
      return true;
    } else {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Upload failed: $resStr")));
      return false;
    }
  }
}

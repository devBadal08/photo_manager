import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class FolderShareService {
  static const String baseUrl =
      "http://192.168.1.6:8000/api"; // change if needed

  /// 🔑 Helper: get token
  Future<String?> _getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString("auth_token");
  }

  static Future<int?> getFolderId(Directory folder) async {
    final folderName = folder.path.split('/').last;
    print("📂 Getting folder id for: $folderName");

    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString("auth_token");
    print("🔑 Token: $token");

    if (token == null) return null;

    final url = "$baseUrl/folders/id?name=$folderName";
    print("🌐 URL: $url");

    final response = await http.get(
      Uri.parse(url),
      headers: {"Authorization": "Bearer $token", "Accept": "application/json"},
    );

    print("📡 Status: ${response.statusCode}");
    print("📡 Body: ${response.body}");

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
    print("📤 Sharing folder: $folderId with $email");
    print(
      "📡 POST body: ${jsonEncode({'folder_id': folderId, 'shared_with': email})}",
    );
    print("📡 Response: ${response.statusCode} ${response.body}");

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
      return jsonDecode(response.body);
    }
    return [];
  }

  /// 📥 Get folders I have shared with others
  Future<List<dynamic>> getMySharedFolders() async {
    final token = await _getToken();
    if (token == null) return [];

    final response = await http.get(
      Uri.parse("$baseUrl/folder/my-shared"),
      headers: {"Authorization": "Bearer $token", "Accept": "application/json"},
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    return [];
  }

  /// 🗑️ Remove a shared folder (unshare)
  Future<bool> unshareFolder(int folderShareId) async {
    final token = await _getToken();
    if (token == null) return false;

    final response = await http.delete(
      Uri.parse("$baseUrl/folder/unshare/$folderShareId"),
      headers: {"Authorization": "Bearer $token", "Accept": "application/json"},
    );

    return response.statusCode == 200;
  }

  /// 🖼️ Get photos inside a shared folder
  Future<List<dynamic>> getPhotosByFolder(int folderId) async {
    final token = await _getToken();
    if (token == null) return [];

    final response = await http.get(
      Uri.parse("$baseUrl/folders/$folderId/photos"),
      headers: {"Authorization": "Bearer $token", "Accept": "application/json"},
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    return [];
  }
}

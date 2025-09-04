import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:photomanager_practice/services/photo_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FolderShareService {
  static const String baseUrl =
      "http://192.168.1.4:8000/api"; // change if needed

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
      return jsonDecode(response.body);
    }
    return [];
  }

  // Get folders I have shared with others
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

  // Remove a shared folder (unshare)
  Future<bool> unshareFolder(int folderShareId) async {
    final token = await _getToken();
    if (token == null) return false;

    final response = await http.delete(
      Uri.parse("$baseUrl/folder/unshare/$folderShareId"),
      headers: {"Authorization": "Bearer $token", "Accept": "application/json"},
    );

    return response.statusCode == 200;
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

  // Upload photo from gallery to shared folder
  Future<bool> uploadPhoto(int folderId) async {
    final token = await _getToken();
    if (token == null) return false;

    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);

    if (pickedFile == null) return false;

    var request = http.MultipartRequest(
      "POST",
      Uri.parse("$baseUrl/folders/$folderId/upload"),
    );
    request.headers["Authorization"] = "Bearer $token";
    request.files.add(
      await http.MultipartFile.fromPath("photo", pickedFile.path),
    );

    final response = await request.send();
    return response.statusCode == 200;
  }

  // Capture photo with camera & upload
  Future<bool> captureAndUpload(int folderId) async {
    final token = await _getToken();
    if (token == null) return false;

    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.camera);

    if (pickedFile == null) return false;

    var request = http.MultipartRequest(
      "POST",
      Uri.parse("$baseUrl/folders/$folderId/upload"),
    );
    request.headers["Authorization"] = "Bearer $token";
    request.files.add(
      await http.MultipartFile.fromPath("photo", pickedFile.path),
    );

    final response = await request.send();
    return response.statusCode == 200;
  }

  Future<bool> uploadSharedFolderImages() async {
    try {
      return await PhotoService().uploadImagesToServer();
    } catch (e) {
      print("❌ Error uploading shared folder images: $e");
      return false;
    }
  }
}

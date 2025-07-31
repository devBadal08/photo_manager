import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';

class PhotoService {
  static Future<bool> uploadImage({
    required File imageFile,
    required String folderName,
    required String token,
  }) async {
    final url = Uri.parse('https://192.168.1.5:8000/api/photos/uploadAll');

    try {
      final request = http.MultipartRequest('POST', url)
        ..headers['Authorization'] = 'Bearer $token'
        ..fields['folders[]'] = folderName
        ..files.add(
          await http.MultipartFile.fromPath('images[]', imageFile.path),
        );

      final response = await request.send();

      if (response.statusCode == 200) {
        return true;
      } else {
        final errorBody = await response.stream.bytesToString();
        print('❌ Server responded with ${response.statusCode}');
        print('❌ Error Body: $errorBody');
        return false;
      }
    } catch (e) {
      print('❌ Error uploading image: $e');
      return false;
    }
  }

  Future<Directory> getBaseDir() async {
    if (Platform.isAndroid) {
      final dir = Directory('/storage/emulated/0/Pictures/MyApp');
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      return dir;
    } else {
      final baseDir = Directory('/storage/emulated/0/Pictures/MyApp');
      if (!await baseDir.exists()) {
        await baseDir.create(recursive: true);
      }
      return baseDir;
    }
  }

  Future<List<String>> listFolders() async {
    final baseDir = await getBaseDir();
    if (!await baseDir.exists()) return [];
    return baseDir
        .listSync()
        .whereType<Directory>()
        .map((dir) => dir.path.split(Platform.pathSeparator).last)
        .toList();
  }

  Future<List<File>> loadPhotosInFolder(String folderName) async {
    final baseDir = await getBaseDir();
    final folder = Directory('${baseDir.path}/$folderName');

    if (!await folder.exists()) return [];

    return folder
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.jpg') || f.path.endsWith('.png'))
        .toList();
  }

  bool isImage(String path) {
    return path.endsWith('.jpg') ||
        path.endsWith('.jpeg') ||
        path.endsWith('.png') ||
        path.endsWith('.gif');
  }

  Future<void> uploadAllImagesForUser() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    final userId = prefs.getString('user_id'); // if your backend needs it

    if (token == null) {
      print('No token found.');
      return;
    }

    final folders = await listFolders();

    for (final folder in folders) {
      final photos = await loadPhotosInFolder(folder);

      for (final photo in photos) {
        final success = await uploadImage(
          imageFile: photo,
          folderName: folder,
          token: token,
        );

        if (success) {
          try {
            await photo.delete();
            print('Deleted after upload: ${photo.path}');
          } catch (e) {
            print('Failed to delete ${photo.path}: $e');
          }
        } else {
          print('Failed to upload ${photo.path}');
        }
      }
    }
  }

  Future<void> createFolder(String name) async {
    if (name.trim().isEmpty) return;
    final baseDir = await getBaseDir();
    final folder = Directory('${baseDir.path}/$name');

    if (!await folder.exists()) {
      await folder.create(recursive: true);
      print("Folder created at: ${folder.path}");
    } else {
      print("Folder already exists: ${folder.path}");
    }
  }

  Future<void> savePhotoInFolder(String folderName) async {
    if (Platform.isAndroid) {
      final status = await Permission.storage.request();
      if (!status.isGranted) {
        print("Storage permission denied");
        return;
      }
    }

    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.camera);

    if (pickedFile != null) {
      final baseDir = await getBaseDir();
      final folder = Directory('${baseDir.path}/$folderName');

      if (!await folder.exists()) {
        await folder.create(recursive: true);
      }

      final fileName =
          '${DateTime.now().millisecondsSinceEpoch}${path.extension(pickedFile.path)}';
      final savedFile = await File(
        pickedFile.path,
      ).copy('${folder.path}/$fileName');

      print("Photo saved at: ${savedFile.path}");
    }
  }
}

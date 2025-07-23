import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path/path.dart' as p;

class PhotoService {
  static Future<bool> uploadImage(File imageFile, String folderName) async {
    try {
      var uri = Uri.parse("http://192.168.0.134:8000/api/photos");

      var request = http.MultipartRequest('POST', uri);
      request.fields['folder'] = folderName;
      request.files.add(
        await http.MultipartFile.fromPath(
          'image',
          imageFile.path,
          filename: p.basename(imageFile.path),
        ),
      );

      var response = await request.send();

      if (response.statusCode == 200) {
        print('✅ Upload successful');
        return true;
      } else {
        print('❌ Upload failed with code: ${response.statusCode}');
        return false;
      }
    } catch (e) {
      print('❌ Upload failed: $e');
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
          '${DateTime.now().millisecondsSinceEpoch}${p.extension(pickedFile.path)}';
      final savedFile = await File(
        pickedFile.path,
      ).copy('${folder.path}/$fileName');

      print("Photo saved at: ${savedFile.path}");
    }
  }
}

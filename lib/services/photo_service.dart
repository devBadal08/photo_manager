import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';

class PhotoService {
  static ValueNotifier<Set<String>> uploadedFiles = ValueNotifier<Set<String>>(
    {},
  );

  static Future<void> loadUploadedFiles() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList('uploaded_files') ?? [];
    uploadedFiles.value = saved.toSet();
  }

  static Future<void> saveUploadedFiles() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('uploaded_files', uploadedFiles.value.toList());
  }

  bool isImage(String filePath) {
    final imageExtensions = ['jpg', 'jpeg', 'png', 'pdf', 'docx'];
    final extension = filePath.split('.').last.toLowerCase();
    return imageExtensions.contains(extension);
  }

  bool isImageFileType(String path) {
    return path.endsWith('.jpg') ||
        path.endsWith('.jpeg') ||
        path.endsWith('.png');
  }

  static Future<bool> uploadImage({
    required File imageFile,
    required String folderName,
    required String token,
  }) async {
    final url = Uri.parse('http://192.168.1.6:8000/api/photos/uploadAll');

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

  bool isImageFile(String path) {
    return path.endsWith('.jpg') ||
        path.endsWith('.jpeg') ||
        path.endsWith('.png') ||
        path.endsWith('.gif');
  }

  Future<void> uploadAllImagesForUser() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    //final userId = prefs.getString('user_id');

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

  Future<bool> uploadImagesToServer() async {
    await PhotoService.loadUploadedFiles();
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getInt('user_id')?.toString();
    final token = prefs.getString('auth_token');

    if (userId == null || token == null) {
      print("❌ User not logged in");
      return false;
    }

    final baseDir = Directory('/storage/emulated/0/Pictures/MyApp/$userId');
    if (!await baseDir.exists()) {
      print("❌ No folders found to upload");
      return false;
    }

    final imageFiles = <File>[];
    final folderNames = <String>[];

    for (var entity in baseDir.listSync(recursive: true)) {
      if (entity is File && isImage(entity.path)) {
        imageFiles.add(entity);
        final relativePath = entity.parent.path.replaceFirst(
          baseDir.path + '/',
          '',
        );
        folderNames.add(relativePath);
      }
    }

    if (imageFiles.isEmpty) {
      print("⚠️ No images found");
      return false;
    }

    // Pair files with folders
    final fileFolderPairs = <MapEntry<File, String>>[];
    for (int i = 0; i < imageFiles.length; i++) {
      fileFolderPairs.add(MapEntry(imageFiles[i], folderNames[i]));
    }

    // Filter not uploaded
    final notUploadedPairs = fileFolderPairs
        .where(
          (entry) => !PhotoService.uploadedFiles.value.contains(
            entry.key.absolute.path,
          ),
        )
        .toList();

    if (notUploadedPairs.isEmpty) {
      print("⚠️ No new images to upload");
      return false;
    }

    // Upload in batches
    const batchSize = 10;
    bool allSuccess = true;

    for (int start = 0; start < notUploadedPairs.length; start += batchSize) {
      final end = (start + batchSize < notUploadedPairs.length)
          ? start + batchSize
          : notUploadedPairs.length;

      final request = http.MultipartRequest(
        'POST',
        Uri.parse('http://192.168.1.6:8000/api/photos/uploadAll'),
      )..headers['Authorization'] = 'Bearer $token';

      for (int i = start; i < end; i++) {
        final file = notUploadedPairs[i].key;
        final folder = notUploadedPairs[i].value;

        request.fields['folders[${i - start}]'] = folder;
        request.files.add(
          await http.MultipartFile.fromPath('images[${i - start}]', file.path),
        );
      }

      final response = await request.send();

      if (response.statusCode == 200) {
        for (int i = start; i < end; i++) {
          PhotoService.uploadedFiles.value.add(
            notUploadedPairs[i].key.absolute.path,
          );
        }
        await PhotoService.saveUploadedFiles();
        print("✅ Uploaded batch ${start ~/ batchSize + 1}");
      } else {
        allSuccess = false;
        final err = await response.stream.bytesToString();
        print("❌ Batch upload failed: $err");
        break;
      }
    }

    return allSuccess;
  }
}

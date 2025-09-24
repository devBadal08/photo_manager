import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
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

  bool isImageExtension(String filePath) {
    final imageExtensions = ['jpg', 'jpeg', 'png', 'pdf', 'docx'];
    final extension = filePath.split('.').last.toLowerCase();
    return imageExtensions.contains(extension);
  }

  static bool isImageFileType(String path) {
    return path.endsWith('.jpg') ||
        path.endsWith('.jpeg') ||
        path.endsWith('.png');
  }

  static Future<bool> uploadImage({
    required File imageFile,
    required String folderName,
    required String token,
  }) async {
    final url = Uri.parse('http://192.168.1.4:8000/api/photos/uploadAll');

    try {
      final request = http.MultipartRequest('POST', url)
        ..headers['Authorization'] = 'Bearer $token'
        ..fields['folders[0]'] = folderName
        ..files.add(
          await http.MultipartFile.fromPath('images[0]', imageFile.path),
        );

      final response = await request.send();
      final responseBody = await response.stream.bytesToString();
      print("📡 Upload response: ${response.statusCode} -> $responseBody");

      return response.statusCode == 200 && responseBody.contains("Upload");
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

  bool isImage(String filePath) {
    final imageExtensions = ['jpg', 'jpeg', 'png', 'pdf', 'docx'];
    final extension = filePath.split('.').last.toLowerCase();
    return imageExtensions.contains(extension);
  }

  static Future<File> compressImage(File file) async {
    final dir = await getTemporaryDirectory();
    final targetPath = path.join(
      dir.path,
      "${DateTime.now().millisecondsSinceEpoch}_${path.basename(file.path)}",
    );

    final XFile? compressedXFile =
        await FlutterImageCompress.compressAndGetFile(
          file.absolute.path,
          targetPath,
          quality: 60,
        );

    if (compressedXFile == null) {
      throw Exception("Image compression failed");
    }

    return File(compressedXFile.path);
  }

  Future<void> uploadAllImagesForUser() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');
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

  static Future<void> uploadImagesToServer(
    BuildContext? context, {
    bool silent = false,
  }) async {
    await PhotoService.loadUploadedFiles();
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getInt('user_id')?.toString();
    final token = prefs.getString('auth_token');

    if (userId == null || token == null) {
      if (!silent && context != null && context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text("User not logged in")));
      }
      return;
    }

    final baseDir = Directory('/storage/emulated/0/Pictures/MyApp/$userId');
    if (!await baseDir.exists()) {
      if (!silent && context != null && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("No folders found to upload")),
        );
      }
      return;
    }

    // Collect image and video files
    List<File> imageFiles = [];
    List<File> videoFiles = [];
    List<String> folderNames = [];

    for (var entity in baseDir.listSync(recursive: true)) {
      if (entity is File) {
        final relativePath = entity.parent.path.replaceFirst(
          baseDir.path + '/',
          '',
        );
        folderNames.add(relativePath);

        if (isImageFileType(entity.path)) {
          imageFiles.add(entity);
        } else if (isVideoFileType(entity.path)) {
          videoFiles.add(entity);
        }
      }
    }

    if (imageFiles.isEmpty && videoFiles.isEmpty) {
      if (!silent && context != null && context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text("No media found")));
      }
      return;
    }

    final allFiles = [...imageFiles, ...videoFiles];
    final fileFolderPairs = List.generate(
      allFiles.length,
      (i) => MapEntry(allFiles[i], folderNames[i]),
    );

    // Filter only not uploaded
    final notUploadedPairs = fileFolderPairs
        .where(
          (entry) => !PhotoService.uploadedFiles.value.contains(
            File(entry.key.path).absolute.path,
          ),
        )
        .toList();

    if (notUploadedPairs.isEmpty) {
      if (!silent && context != null && context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text("No new media to upload")));
      }
      return;
    }

    final notUploadedFiles = notUploadedPairs.map((e) => e.key).toList();
    final notUploadedFolders = notUploadedPairs.map((e) => e.value).toList();

    // Ask for confirmation
    if (!silent && context != null && context.mounted) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text("Upload Confirmation"),
          content: Text(
            "Do you want to upload ${notUploadedFiles.length} media files to the server?",
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text("No"),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text("Yes"),
            ),
          ],
        ),
      );
      if (confirm != true) return;
    }

    // Show progress dialog
    final uploadedCount = ValueNotifier<int>(0);
    final totalFiles = notUploadedFiles.length;

    if (!silent && context != null && context.mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => AlertDialog(
          backgroundColor: Theme.of(context).colorScheme.surface,
          content: ValueListenableBuilder<int>(
            valueListenable: uploadedCount,
            builder: (_, count, __) {
              return Row(
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(width: 20),
                  Expanded(
                    child: Text(
                      "${((count / totalFiles) * 100).toStringAsFixed(0)}% uploading media",
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      );
    }

    // Start uploading
    try {
      const batchSize = 10;
      bool allSuccess = true;

      for (int start = 0; start < notUploadedFiles.length; start += batchSize) {
        final end = (start + batchSize < notUploadedFiles.length)
            ? start + batchSize
            : notUploadedFiles.length;

        final request = http.MultipartRequest(
          'POST',
          Uri.parse('http://192.168.1.4:8000/api/photos/uploadAll'),
        );
        request.headers['Authorization'] = 'Bearer $token';

        for (int i = start; i < end; i++) {
          request.fields['folders[${i - start}]'] = notUploadedFolders[i];
          final file = notUploadedFiles[i];

          http.MultipartFile multipartFile;
          if (isImageFileType(file.path)) {
            final compressed = await compressImage(file);
            final length = await compressed.length();
            multipartFile = http.MultipartFile(
              'images[${i - start}]',
              http.ByteStream(compressed.openRead()),
              length,
              filename: compressed.path.split('/').last,
            );
          } else {
            // video file
            final length = await file.length();
            multipartFile = http.MultipartFile(
              'videos[${i - start}]',
              http.ByteStream(file.openRead()),
              length,
              filename: file.path.split('/').last,
            );
          }

          request.files.add(multipartFile);
        }

        final response = await request.send();

        if (response.statusCode == 200) {
          for (int i = start; i < end; i++) {
            PhotoService.uploadedFiles.value.add(
              File(notUploadedFiles[i].path).absolute.path,
            );
          }
          PhotoService.uploadedFiles.notifyListeners();
          await PhotoService.saveUploadedFiles();
          uploadedCount.value += (end - start);
        } else {
          allSuccess = false;
          final err = await response.stream.bytesToString();
          debugPrint("Batch upload failed: $err");
          break;
        }
      }

      // Close progress dialog
      if (!silent && context != null && context.mounted) {
        Navigator.pop(context);
      }

      if (!silent && context != null && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              allSuccess ? "Uploaded successfully" : "Some uploads failed",
            ),
          ),
        );
      }
    } catch (e) {
      if (!silent && context != null && context.mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text("Upload failed")));
      }
      debugPrint("❌ Upload error: $e");
    }
  }

  // Helper to check video file types
  static bool isVideoFileType(String path) {
    final ext = path.toLowerCase();
    return ext.endsWith('.mp4');
  }
}

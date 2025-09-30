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
    final url = Uri.parse('http://192.168.1.13:8000/api/photos/uploadAll');

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
    final userId = prefs.getString('user_id');
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

    // Collect media files and folder names
    List<File> files = [];
    List<String> folderNames = [];

    for (var entity in baseDir.listSync(recursive: true)) {
      if (entity is File) {
        final relativeFolder = entity.parent.path.replaceFirst(
          baseDir.path + '/',
          '',
        );
        folderNames.add(relativeFolder);
        files.add(entity);
      }
    }

    if (files.isEmpty) {
      if (!silent && context != null && context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text("No media found")));
      }
      return;
    }

    // Filter only not uploaded
    final notUploadedPairs =
        List.generate(files.length, (i) => MapEntry(files[i], folderNames[i]))
            .where(
              (entry) =>
                  !PhotoService.uploadedFiles.value.contains(entry.key.path),
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

    // Separate images and videos
    final imagePairs = notUploadedPairs
        .where((e) => isImageFileType(e.key.path))
        .toList();
    final videoPairs = notUploadedPairs
        .where((e) => isVideoFileType(e.key.path))
        .toList();
    final pdfPairs = notUploadedPairs
        .where((e) => e.key.path.toLowerCase().endsWith('.pdf'))
        .toList();

    // Ask for confirmation
    if (!silent && context != null && context.mounted) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text("Upload Confirmation"),
          content: Text(
            "Do you want to upload ${notUploadedPairs.length} media files to the server?",
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

    final uploadedCount = ValueNotifier<int>(0);
    final totalFiles = notUploadedPairs.length;

    // Show progress dialog
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

    try {
      const batchSize = 10;
      bool allSuccess = true;

      // Function to upload a batch (generic)
      Future<bool> uploadBatch(
        List<MapEntry<File, String>> batch,
        String type,
      ) async {
        if (batch.isEmpty) return true;

        final request = http.MultipartRequest(
          'POST',
          Uri.parse('http://192.168.1.13:8000/api/photos/uploadAll'),
        );
        request.headers['Authorization'] = 'Bearer $token';

        for (int i = 0; i < batch.length; i++) {
          final file = batch[i].key;
          final folder = batch[i].value;

          // Backend expects folders[0], folders[1], ... for all files
          request.fields['folders[$i]'] = folder;

          request.files.add(
            await http.MultipartFile.fromPath('$type[$i]', file.path),
          );
        }

        final response = await request.send();
        final resStr = await response.stream.bytesToString();

        if (response.statusCode == 200) {
          for (final entry in batch) {
            PhotoService.uploadedFiles.value.add(entry.key.absolute.path);
          }
          PhotoService.uploadedFiles.notifyListeners();
          await PhotoService.saveUploadedFiles();
          uploadedCount.value += batch.length;
          return true;
        } else {
          debugPrint("Batch upload failed ($type): $resStr");
          return false;
        }
      }

      // Upload images in batches
      for (int start = 0; start < imagePairs.length; start += batchSize) {
        final end = (start + batchSize < imagePairs.length)
            ? start + batchSize
            : imagePairs.length;
        final batch = imagePairs.sublist(start, end);
        final success = await uploadBatch(batch, 'images');
        if (!success) {
          allSuccess = false;
          break;
        }
      }

      // Upload videos in batches
      for (int start = 0; start < videoPairs.length; start += batchSize) {
        final end = (start + batchSize < videoPairs.length)
            ? start + batchSize
            : videoPairs.length;
        final batch = videoPairs.sublist(start, end);
        final success = await uploadBatch(batch, 'videos');
        if (!success) {
          allSuccess = false;
          break;
        }
      }

      // Upload PDFs in batches
      for (int start = 0; start < pdfPairs.length; start += batchSize) {
        final end = (start + batchSize < pdfPairs.length)
            ? start + batchSize
            : pdfPairs.length;
        final batch = pdfPairs.sublist(start, end);
        final success = await uploadBatch(batch, 'pdfs'); // type = 'pdfs'
        if (!success) {
          allSuccess = false;
          break;
        }
      }

      // Close progress dialog
      if (!silent && context != null && context.mounted) {
        Navigator.pop(context);
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

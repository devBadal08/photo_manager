import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';

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
    final imageExtensions = ['jpg', 'jpeg', 'png'];
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
    final url = Uri.parse('https://techstrota.cloud/api/photos/uploadAll');

    try {
      final prefs = await SharedPreferences.getInstance();
      final companyId = prefs.getInt('selected_company_id');

      final request = http.MultipartRequest('POST', url)
        ..headers['Authorization'] = 'Bearer $token'
        ..fields['company_id'] = companyId.toString()
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

  static Future<Directory?> getUserRootDir() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getString('user_id');
    final companyId = prefs.getInt('selected_company_id');

    if (userId == null || companyId == null) return null;

    final base = await getExternalStorageDirectory();
    if (base == null) return null;

    final dir = Directory('${base.path}/ScanVaultApp/$companyId/$userId');

    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    return dir;
  }

  Future<List<String>> listFolders() async {
    final baseDir = await PhotoService.getUserRootDir();
    if (baseDir == null) return [];

    if (!await baseDir.exists()) return [];
    return baseDir
        .listSync()
        .whereType<Directory>()
        .map((dir) => dir.path.split(Platform.pathSeparator).last)
        .toList();
  }

  static Future<bool> renameFileOnServer({
    required String oldPath,
    required String newName,
    required String token,
  }) async {
    final response = await http.post(
      Uri.parse('https://techstrota.cloud/api/photos/rename-file'),
      headers: {'Authorization': 'Bearer $token', 'Accept': 'application/json'},
      body: {'old_path': oldPath, 'new_name': newName},
    );

    print("🔄 Rename response: ${response.body}");

    return response.statusCode == 200;
  }

  Future<List<File>> loadPhotosInFolder(String folderName) async {
    final baseDir = await PhotoService.getUserRootDir();
    if (baseDir == null) return [];

    final folder = Directory('${baseDir.path}/$folderName');

    if (!await folder.exists()) return [];

    return folder
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.jpg') || f.path.endsWith('.png'))
        .toList();
  }

  bool isImage(String filePath) {
    final imageExtensions = ['jpg', 'jpeg', 'png'];
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
          quality: 85,
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

      final baseDir = await PhotoService.getUserRootDir();
      if (baseDir == null) return;

      final folder = Directory('${baseDir.path}/$name');

      if (!await folder.exists()) {
        await folder.create(recursive: true);
        debugPrint("Folder created at: ${folder.path}");
      } else {
        debugPrint("Folder already exists: ${folder.path}");
      }
    }
  }

  static Future<bool> isFolderFullyUploadedLocally(Directory folder) async {
    await loadUploadedFiles();

    final files = folder.listSync(recursive: true).whereType<File>().toList();

    if (files.isEmpty) return false;

    for (final file in files) {
      if (!uploadedFiles.value.contains(file.absolute.path)) {
        return false; // at least one file not uploaded
      }
    }

    return true; // all files uploaded
  }

  static Future<void> _saveFolderMetaForBatch(
    List<MapEntry<File, String>> batch,
    int folderId,
    int? parentId,
  ) async {
    final firstFile = batch.first.key;
    final folderDir = firstFile.parent;
    final folderName = folderDir.path.split('/').last;
    final folderPath = folderDir.path;

    final baseDir = await getExternalStorageDirectory();
    if (baseDir == null) return;

    final metaDir = Directory('${baseDir.path}/folder_meta');
    if (!await metaDir.exists()) {
      await metaDir.create(recursive: true);
    }

    final metaFile = File('${metaDir.path}/folder_$folderId.json');

    // 🔁 Update meta if exists (important for rename)
    await metaFile.writeAsString(
      jsonEncode({
        'folder_id': folderId,
        'folder_name': folderName,
        'folder_path': folderPath, // ✅ THIS FIXES EVERYTHING
      }),
    );

    debugPrint('✅ Folder meta saved/updated');
    debugPrint('   id   = $folderId');
    debugPrint('   name = $folderName');
    debugPrint('   path = $folderPath');
  }

  static Future<int?> getFolderIdFromDisk(Directory folder) async {
    final baseDir = await getExternalStorageDirectory();

    print('🧪 GET FOLDER ID FROM DISK photolist');
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

  static Future<bool> canUploadMore({
    bool silent = false,
    BuildContext? context,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');
    final companyId = prefs.getInt('selected_company_id');

    if (token == null || companyId == null) return false;

    final res = await http.get(
      Uri.parse(
        'https://techstrota.cloud/api/storage-usage?company_id=$companyId',
      ),
      headers: {'Authorization': 'Bearer $token', 'Accept': 'application/json'},
    );

    if (res.statusCode != 200) return false;

    final data = jsonDecode(res.body);
    final percent = (data['percent_used'] ?? 0).toDouble();

    if (percent >= 98.5) {
      if (!silent && context != null && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("❌ Storage full. Upload blocked."),
            backgroundColor: Colors.red,
          ),
        );
      }
      return false;
    }

    return true;
  }

  static Future<int?> ensureFolderOnServer({
    required Directory folderDir,
    required int companyId,
    required String userId,
    required String token,
  }) async {
    // 1️⃣ Try meta first
    final existingId = await getFolderIdFromDisk(folderDir);
    if (existingId != null) return existingId;

    final appFilesBase = await getExternalStorageDirectory();
    if (appFilesBase == null) return null;

    final root = '${appFilesBase.path}/ScanVaultApp/$companyId/$userId';

    late final String baseStopPath;

    if (folderDir.path.startsWith(root)) {
      baseStopPath = root;
    } else {
      debugPrint('🚫 Folder outside known roots: ${folderDir.path}');
      return null;
    }

    int? parentId;

    // 2️⃣ Stop ONLY at company/user root
    if (folderDir.path != baseStopPath) {
      final parentDir = folderDir.parent;

      if (parentDir.path != baseStopPath) {
        parentId = await ensureFolderOnServer(
          folderDir: parentDir,
          companyId: companyId,
          userId: userId,
          token: token,
        );
      }
    }

    // 3️⃣ Create current folder
    final folderName = folderDir.path.split('/').last;

    // ✅ build body safely (NO null values)
    final body = <String, String>{
      'name': folderName,
      'company_id': companyId.toString(),
    };

    if (parentId != null) {
      body['parent_id'] = parentId.toString();
    }

    // ✅ single http.post call
    final response = await http.post(
      Uri.parse('https://techstrota.cloud/api/photos/create-folder'),
      headers: {'Authorization': 'Bearer $token', 'Accept': 'application/json'},
      body: body,
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final folderId = data['folder']['id'];

      await _saveFolderMetaForBatch(
        [MapEntry(File('${folderDir.path}/_'), folderDir.path)],
        folderId,
        parentId,
      );

      return folderId;
    }

    return null;
  }

  static Future<void> uploadImagesToServer(
    File? file, {
    BuildContext? context,
    bool silent = false,
  }) async {
    final allowed = await canUploadMore(silent: silent, context: context);

    if (!allowed) {
      debugPrint("🚫 Upload blocked due to storage limit");
      return;
    }

    await PhotoService.loadUploadedFiles();
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getString('user_id');
    final token = prefs.getString('auth_token');
    final companyId = prefs.getInt('selected_company_id');

    if (companyId == null) {
      if (!silent && context != null && context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text("Company not selected")));
      }
      return;
    }

    if (userId == null || token == null) {
      if (!silent && context != null && context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text("User not logged in")));
      }
      return;
    }

    final baseDir = await PhotoService.getUserRootDir();
    if (baseDir == null || !await baseDir.exists()) {
      // show snackbar
      return;
    }

    //final baseDir = await PhotoService.getBaseDir();

    if (!await baseDir.exists()) {
      if (!silent && context != null && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("No folders found to upload")),
        );
      }
      return;
    }

    // Collect media files and folder names
    List<MapEntry<File, Directory>> fileFolderPairs = [];

    for (var entity in baseDir.listSync(recursive: true)) {
      if (entity is File) {
        final p = entity.path.toLowerCase();
        if (p.endsWith('.jpg') ||
            p.endsWith('.jpeg') ||
            p.endsWith('.png') ||
            p.endsWith('.mp4') ||
            p.endsWith('.pdf')) {
          fileFolderPairs.add(MapEntry(entity, entity.parent));
        }
      }
    }

    // Scan app-specific PDF directory
    final root = await PhotoService.getUserRootDir();
    if (root == null) return null;

    final baseStopPath = root.path;

    if (fileFolderPairs.isEmpty) {
      if (!silent && context != null && context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text("No media found")));
      }
      return;
    }

    // Filter only not uploaded
    final notUploadedPairs =
        List.generate(fileFolderPairs.length, (i) => fileFolderPairs[i])
            .where(
              (entry) => !PhotoService.uploadedFiles.value.contains(
                entry.key.absolute.path,
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
            "Do you want to upload total ${notUploadedPairs.length} media files to the server?",
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
      // ✅ STEP 1: Check storage usage BEFORE showing loader
      final prefs = await SharedPreferences.getInstance();
      final selectedCompanyId = prefs.getInt("selected_company_id");

      final checkUrl = Uri.parse(
        'https://techstrota.cloud/api/storage-usage?company_id=$selectedCompanyId',
      );

      final checkResponse = await http.get(
        checkUrl,
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
        },
      );

      if (checkResponse.statusCode == 200) {
        final data = jsonDecode(checkResponse.body);
        final used = data['used_storage_mb'] ?? 0;
        final max = data['max_storage_mb'] ?? 0;
        final percent = data['percent_used'] ?? 0;
        debugPrint("📦 Storage: $used / $max MB used ($percent%)");

        if (max > 0) {
          final percent = (used / max) * 100;

          if (percent >= 99.5 && percent <= 100) {
            // 🚫 Almost full (block upload)
            if (context != null && context.mounted) {
              await showDialog(
                context: context,
                builder: (_) => AlertDialog(
                  title: const Text("⚠️ Storage Almost Full"),
                  content: Text(
                    "You have used ${percent.toStringAsFixed(2)}% of your storage.\n"
                    "Uploads are disabled until you free up space or contact admin.",
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text("OK"),
                    ),
                  ],
                ),
              );
            }
            return; // stop here
          }

          if (percent > 100) {
            // ❌ Completely full
            if (context != null && context.mounted) {
              await showDialog(
                context: context,
                builder: (_) => AlertDialog(
                  title: const Text("❌ Storage Limit Exceeded"),
                  content: Text(
                    "Your storage limit is exceeded.\n"
                    "Please contact admin to increase your storage",
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text("OK"),
                    ),
                  ],
                ),
              );
            }
            return;
          }
        }
      } else {
        debugPrint(
          "⚠️ Failed to check storage usage (${checkResponse.statusCode})",
        );
      }

      const batchSize = 10;
      bool allSuccess = true;

      // Function to upload a batch (generic)
      Future<bool> uploadBatch(
        List<MapEntry<File, Directory>> batch,
        String type,
      ) async {
        final request = http.MultipartRequest(
          'POST',
          Uri.parse('https://techstrota.cloud/api/photos/uploadAll'),
        );

        request.headers['Authorization'] = 'Bearer $token';
        request.fields['company_id'] = companyId.toString();

        for (int i = 0; i < batch.length; i++) {
          final file = batch[i].key;
          final folderDir = batch[i].value; // ✅ FIXED

          final folderId = await ensureFolderOnServer(
            folderDir: folderDir,
            companyId: companyId!,
            userId: userId!,
            token: token!,
          );

          if (folderId == null) {
            throw Exception('Failed to create folder: ${folderDir.path}');
          }

          request.fields['folders[$i][folder_id]'] = folderId.toString();
          request.files.add(
            await http.MultipartFile.fromPath('$type[$i]', file.path),
          );
        }

        final response = await request.send();
        final resStr = await response.stream.bytesToString();

        if (response.statusCode == 200) {
          for (final entry in batch) {
            uploadedFiles.value.add(entry.key.absolute.path);
          }
          await saveUploadedFiles();
          uploadedCount.value += batch.length;
          return true;
        }

        print("Status Code: ${response.statusCode}");
        print("Response: $resStr");
        debugPrint("Upload failed: $resStr");
        return false;
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
          debugPrint("❌ Image batch failed → continuing...");
          continue; // ✅ keep going instead of break
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
          debugPrint("❌ Video batch failed → continuing...");
          continue; // ✅ keep going instead of break
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
          debugPrint("❌ PDF batch failed → continuing...");
          continue; // ✅ keep going instead of break
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
      debugPrint("🔥 Exception during upload: $e");

      if (!silent && context != null && context.mounted) {
        if (Navigator.canPop(context)) Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e.toString().contains('Storage full')
                  ? '❌ Upload blocked: your storage limit is full.'
                  : 'Upload failed. Please try again.',
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
      print("❌ Upload error: $e");
    }
  }

  // Helper to check video file types
  static bool isVideoFileType(String path) {
    final ext = path.toLowerCase();
    return ext.endsWith('.mp4');
  }
}

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

    if (existingId != null) {
      final existsOnServer = await verifyFolderOnServer(
        folderId: existingId,
        companyId: companyId,
        token: token,
      );

      if (existsOnServer) {
        debugPrint('✅ Folder $existingId verified on server');

        return existingId;
      }

      debugPrint(
        '⚠️ Folder $existingId exists locally '
        'but NOT on server. Recreating folder...',
      );
    }

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

  static Future<List<Map<String, dynamic>>> checkPendingFiles({
    required List<Map<String, dynamic>> files,
  }) async {
    final prefs = await SharedPreferences.getInstance();

    final token = prefs.getString('auth_token');
    final companyId = prefs.getInt('selected_company_id');

    if (token == null || companyId == null) {
      throw Exception('Authentication information is missing');
    }

    try {
      final response = await http.post(
        Uri.parse('https://techstrota.cloud/api/photos/check-pending'),
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'company_id': companyId, 'files': files}),
      );

      debugPrint("📡 Pending check response: ${response.statusCode}");

      if (response.statusCode != 200) {
        debugPrint(
          "❌ Pending check failed: "
          "${response.statusCode} -> ${response.body}",
        );

        throw Exception(
          'Pending check failed with status ${response.statusCode}',
        );
      }

      final data = jsonDecode(response.body);

      final missing = data['missing'];

      if (missing is List) {
        return List<Map<String, dynamic>>.from(
          missing.map((e) => Map<String, dynamic>.from(e)),
        );
      }

      throw Exception('Invalid pending check response');
    } catch (e) {
      debugPrint("❌ Pending check error: $e");

      rethrow;
    }
  }

  static Future<bool> verifyFolderOnServer({
    required int folderId,
    required int companyId,
    required String token,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('https://techstrota.cloud/api/photos/verify-folder'),
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'folder_id': folderId, 'company_id': companyId}),
      );

      debugPrint(
        '📡 Verify folder $folderId -> '
        '${response.statusCode}: ${response.body}',
      );

      if (response.statusCode != 200) {
        return false;
      }

      final data = jsonDecode(response.body);

      return data['exists'] == true;
    } catch (e) {
      debugPrint('❌ Folder verification error: $e');
      return false;
    }
  }

  static Future<bool> _uploadPendingBatch({
    required List<MapEntry<File, Directory>> batch,
    required String token,
    required int companyId,
    required String userId,
    required ValueNotifier<int> uploadedCount,
    required Map<String, int> folderIdCache,
  }) async {
    try {
      // Separate by type
      final imageBatch = batch
          .where((e) => isImageFileType(e.key.path))
          .toList();

      final videoBatch = batch
          .where((e) => isVideoFileType(e.key.path))
          .toList();

      final pdfBatch = batch
          .where((e) => e.key.path.toLowerCase().endsWith('.pdf'))
          .toList();

      // Upload one type at a time
      Future<bool> uploadTypeBatch(
        List<MapEntry<File, Directory>> typeBatch,
        String type,
      ) async {
        if (typeBatch.isEmpty) return true;

        final request = http.MultipartRequest(
          'POST',
          Uri.parse('https://techstrota.cloud/api/photos/uploadAll'),
        );

        request.headers['Authorization'] = 'Bearer $token';
        request.headers['Accept'] = 'application/json';

        request.fields['company_id'] = companyId.toString();

        for (int i = 0; i < typeBatch.length; i++) {
          final file = typeBatch[i].key;
          final folderDir = typeBatch[i].value;

          final folderKey = folderDir.path;

          int? folderId = folderIdCache[folderKey];

          if (folderId == null) {
            folderId = await ensureFolderOnServer(
              folderDir: folderDir,
              companyId: companyId,
              userId: userId,
              token: token,
            );

            if (folderId != null) {
              folderIdCache[folderKey] = folderId;
            }
          }

          if (folderId == null) {
            debugPrint("❌ Failed to resolve folder: ${folderDir.path}");
            return false;
          }

          // IMPORTANT:
          // Index starts from 0 separately for images/videos/pdfs
          request.fields['folders[$i][folder_id]'] = folderId.toString();

          request.files.add(
            await http.MultipartFile.fromPath('$type[$i]', file.path),
          );
        }

        final response = await request.send();
        final responseBody = await response.stream.bytesToString();

        debugPrint(
          "📡 Pending $type upload response: "
          "${response.statusCode} -> $responseBody",
        );

        if (response.statusCode == 200) {
          await PhotoService.loadUploadedFiles();

          for (final entry in typeBatch) {
            PhotoService.uploadedFiles.value.add(entry.key.absolute.path);
          }

          await PhotoService.saveUploadedFiles();

          uploadedCount.value += typeBatch.length;

          return true;
        }

        debugPrint("❌ Pending $type batch failed: $responseBody");

        return false;
      }

      bool allSuccess = true;

      // Images
      if (!await uploadTypeBatch(imageBatch, 'images')) {
        allSuccess = false;
      }

      // Videos
      if (!await uploadTypeBatch(videoBatch, 'videos')) {
        allSuccess = false;
      }

      // PDFs
      if (!await uploadTypeBatch(pdfBatch, 'pdfs')) {
        allSuccess = false;
      }

      return allSuccess;
    } catch (e) {
      debugPrint("❌ Pending batch exception: $e");
      return false;
    }
  }

  static Future<void> uploadPendingPhotos({BuildContext? context}) async {
    final prefs = await SharedPreferences.getInstance();

    final token = prefs.getString('auth_token');
    final userId = prefs.getString('user_id');
    final companyId = prefs.getInt('selected_company_id');

    if (token == null || userId == null || companyId == null) {
      if (context != null && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("User/company information not available"),
          ),
        );
      }

      return;
    }

    // ---------------------------------------------------------
    // 1. Check storage
    // ---------------------------------------------------------

    final allowed = await canUploadMore(context: context);

    if (!allowed) {
      return;
    }

    // ---------------------------------------------------------
    // 🔄 Show loader while scanning/checking pending media
    // ---------------------------------------------------------
    bool checkingLoaderShown = false;

    void showCheckingLoader() {
      if (context != null && context.mounted) {
        checkingLoaderShown = true;

        showDialog(
          context: context,
          barrierDismissible: false,
          useRootNavigator: true,
          builder: (_) {
            return const AlertDialog(
              content: Row(
                children: [
                  CircularProgressIndicator(),
                  SizedBox(width: 20),
                  Expanded(child: Text("Checking your media...\nPlease wait.")),
                ],
              ),
            );
          },
        );
      }
    }

    void closeCheckingLoader() {
      if (checkingLoaderShown && context != null && context.mounted) {
        final navigator = Navigator.of(context, rootNavigator: true);

        if (navigator.canPop()) {
          navigator.pop();
        }

        checkingLoaderShown = false;
      }
    }

    showCheckingLoader();

    // ---------------------------------------------------------
    // 2. Get local root
    // ---------------------------------------------------------

    final baseDir = await getUserRootDir();

    if (baseDir == null || !await baseDir.exists()) {
      closeCheckingLoader();

      if (context != null && context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text("No local photos found")));
      }

      return;
    }

    // ---------------------------------------------------------
    // 3. Collect all local media
    // ---------------------------------------------------------

    final List<MapEntry<File, Directory>> localFiles = [];

    for (final entity in baseDir.listSync(recursive: true)) {
      if (entity is! File) continue;

      final lowerPath = entity.path.toLowerCase();

      if (lowerPath.endsWith('.jpg') ||
          lowerPath.endsWith('.jpeg') ||
          lowerPath.endsWith('.png') ||
          lowerPath.endsWith('.mp4') ||
          lowerPath.endsWith('.pdf')) {
        localFiles.add(MapEntry(entity, entity.parent));
      }
    }

    if (localFiles.isEmpty) {
      closeCheckingLoader();
      if (context != null && context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text("No local media found")));
      }

      return;
    }

    // ---------------------------------------------------------
    // 4. Build server-check list
    // ---------------------------------------------------------

    final List<Map<String, dynamic>> checkFiles = [];
    final Map<String, MapEntry<File, Directory>> localFileMap = {};

    // 🔥 Cache folder IDs so the same folder is NOT resolved again
    final Map<String, int> folderIdCache = {};

    for (final entry in localFiles) {
      final file = entry.key;
      final folderDir = entry.value;

      final folderKey = folderDir.path;

      int? folderId = folderIdCache[folderKey];

      // Resolve folder only once
      if (folderId == null) {
        folderId = await ensureFolderOnServer(
          folderDir: folderDir,
          companyId: companyId,
          userId: userId,
          token: token,
        );

        if (folderId != null) {
          folderIdCache[folderKey] = folderId;
        }
      }

      if (folderId == null) {
        debugPrint("❌ Could not resolve folder: ${folderDir.path}");
        continue;
      }

      final filename = path.basename(file.path);

      final key = '$folderId/$filename';

      checkFiles.add({'folder_id': folderId, 'filename': filename});

      localFileMap[key] = entry;
    }

    if (checkFiles.isEmpty) {
      closeCheckingLoader();
      if (context != null && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("No files available for pending check")),
        );
      }

      return;
    }

    // ---------------------------------------------------------
    // 5. Ask server which files are missing
    // ---------------------------------------------------------

    final List<MapEntry<File, Directory>> pendingPairs = [];

    const int checkBatchSize = 500;

    int checkedCount = 0;

    for (int start = 0; start < checkFiles.length; start += checkBatchSize) {
      final end = (start + checkBatchSize < checkFiles.length)
          ? start + checkBatchSize
          : checkFiles.length;

      final batch = checkFiles.sublist(start, end);

      debugPrint(
        "🔍 Checking pending files: $start - $end / ${checkFiles.length}",
      );

      try {
        final missingFiles = await checkPendingFiles(files: batch);

        for (final missing in missingFiles) {
          final folderId = missing['folder_id'];
          final filename = missing['filename'];

          final key = '$folderId/$filename';

          final localEntry = localFileMap[key];

          if (localEntry != null) {
            pendingPairs.add(localEntry);
          }
        }

        checkedCount = end;

        debugPrint(
          "✅ Pending check progress: "
          "$checkedCount / ${checkFiles.length}",
        );
      } catch (e) {
        debugPrint(
          "❌ Pending check batch failed: "
          "$start - $end / ${checkFiles.length}",
        );

        closeCheckingLoader();

        if (context != null && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                "Unable to check pending files. "
                "Please try again.\n"
                "Failed batch: $start - $end",
              ),
              backgroundColor: Colors.red,
            ),
          );
        }

        return;
      }
    }
    if (pendingPairs.isEmpty) {
      closeCheckingLoader();
      if (context != null && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Pending files could not be found locally"),
          ),
        );
      }

      return;
    }

    // ---------------------------------------------------------
    // 🔄 Close checking loader
    // ---------------------------------------------------------
    closeCheckingLoader();

    // ---------------------------------------------------------
    // 7. Confirmation
    // ---------------------------------------------------------

    if (context != null && context.mounted) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            title: const Text("Upload Pending Photos"),
            content: Text(
              "${pendingPairs.length} media files are missing on the server.\n\n"
              "Do you want to upload them again?",
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(dialogContext, false);
                },
                child: const Text("Cancel"),
              ),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(dialogContext, true);
                },
                child: const Text("Upload"),
              ),
            ],
          );
        },
      );

      if (confirm != true) {
        return;
      }
    }

    // ---------------------------------------------------------
    // 8. Progress
    // ---------------------------------------------------------

    final uploadedCount = ValueNotifier<int>(0);
    final totalFiles = pendingPairs.length;

    if (context != null && context.mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) {
          return AlertDialog(
            content: ValueListenableBuilder<int>(
              valueListenable: uploadedCount,
              builder: (_, count, __) {
                final percent = totalFiles == 0
                    ? 0
                    : ((count / totalFiles) * 100).toInt();

                return Row(
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(width: 20),
                    Expanded(
                      child: Text(
                        "$percent% uploading pending media\n"
                        "$count / $totalFiles",
                      ),
                    ),
                  ],
                );
              },
            ),
          );
        },
      );
    }

    // ---------------------------------------------------------
    // 9. Upload in batches
    // ---------------------------------------------------------

    const batchSize = 10;

    bool allSuccess = true;

    try {
      for (int start = 0; start < pendingPairs.length; start += batchSize) {
        final end = (start + batchSize < pendingPairs.length)
            ? start + batchSize
            : pendingPairs.length;

        final batch = pendingPairs.sublist(start, end);

        final success = await _uploadPendingBatch(
          batch: batch,
          token: token,
          companyId: companyId,
          userId: userId,
          uploadedCount: uploadedCount,
          folderIdCache: folderIdCache,
        );

        if (!success) {
          allSuccess = false;
        }
      }

      // Close progress
      if (context != null && context.mounted) {
        if (Navigator.canPop(context)) {
          Navigator.pop(context);
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              allSuccess
                  ? "Pending photos uploaded successfully"
                  : "Some pending photos failed to upload",
            ),
          ),
        );
      }
    } catch (e) {
      debugPrint("🔥 Pending upload error: $e");

      if (context != null && context.mounted) {
        if (Navigator.canPop(context)) {
          Navigator.pop(context);
        }

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Pending upload failed. Please try again."),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
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
    final Map<String, int> folderIdCache = {};

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

          final folderKey = folderDir.path;

          int? folderId = folderIdCache[folderKey];

          if (folderId == null) {
            folderId = await ensureFolderOnServer(
              folderDir: folderDir,
              companyId: companyId!,
              userId: userId!,
              token: token!,
            );

            if (folderId != null) {
              folderIdCache[folderKey] = folderId;
            }
          }

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

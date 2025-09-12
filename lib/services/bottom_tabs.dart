import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path/path.dart' as path;

class BottomTabs extends StatelessWidget {
  final TabController? controller;
  final bool showCamera;
  final bool cameraDisabled;
  final bool scanDisabled;
  final void Function(int)? onCreateFolder;
  final VoidCallback? onCameraTap;
  final VoidCallback? onUploadTap;
  final VoidCallback? onUploadComplete;

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

  BottomTabs({
    super.key,
    this.controller,
    this.showCamera = true,
    this.cameraDisabled = false,
    this.scanDisabled = false,
    this.onCreateFolder,
    this.onCameraTap,
    this.onUploadTap,
    this.onUploadComplete,
  });

  bool isImage(String filePath) {
    final imageExtensions = ['jpg', 'jpeg', 'png', 'pdf', 'docx'];
    final extension = filePath.split('.').last.toLowerCase();
    return imageExtensions.contains(extension);
  }

  Future<File> compressImage(File file) async {
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

  Future<void> uploadImagesToServer(BuildContext context) async {
    await BottomTabs.loadUploadedFiles();
    SharedPreferences prefs = await SharedPreferences.getInstance();
    String? userId = prefs.getInt('user_id')?.toString();
    String? token = prefs.getString('auth_token');

    if (userId == null || token == null) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("User not logged in")));
      return;
    }

    Directory baseDir = Directory('/storage/emulated/0/Pictures/MyApp/$userId');
    if (!await baseDir.exists()) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("No folders found to upload")),
      );
      return;
    }

    List<File> imageFiles = [];
    List<String> folderNames = [];

    for (var entity in baseDir.listSync(recursive: true)) {
      if (entity is File && isImage(entity.path)) {
        imageFiles.add(entity);
        String relativePath = entity.parent.path.replaceFirst(
          baseDir.path + '/',
          '',
        );
        folderNames.add(relativePath);
      }
    }

    if (imageFiles.isEmpty) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("No images found")));
      return;
    }

    // Pair files with their folders
    List<MapEntry<File, String>> fileFolderPairs = [];

    for (int i = 0; i < imageFiles.length; i++) {
      fileFolderPairs.add(MapEntry(imageFiles[i], folderNames[i]));
    }

    // Filter only not uploaded ones
    var notUploadedPairs = fileFolderPairs
        .where(
          (entry) => !BottomTabs.uploadedFiles.value.contains(
            File(entry.key.path).absolute.path,
          ),
        )
        .toList();

    List<File> notUploadedFiles = notUploadedPairs.map((e) => e.key).toList();
    List<String> notUploadedFolders = notUploadedPairs
        .map((e) => e.value)
        .toList();

    if (notUploadedFiles.isEmpty) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("No new images to upload")));
      return;
    }

    ValueNotifier<int> uploadedCount = ValueNotifier<int>(0);
    int totalImages = notUploadedFiles.length;
    int remainingImages = notUploadedFiles.length; // Pending images

    if (!context.mounted) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Upload Confirmation"),
        content: Text(
          "Do you want to upload $remainingImages images to the server?",
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

    if (!context.mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) {
        return AlertDialog(
          backgroundColor: Theme.of(context).colorScheme.surface,
          content: ValueListenableBuilder<int>(
            valueListenable: uploadedCount,
            builder: (_, count, __) {
              //final remaining = totalImages - count;
              return Row(
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(width: 20),
                  Expanded(
                    child: Text(
                      "${((count / totalImages) * 100).toStringAsFixed(0)}% uploading images",
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                ],
              );
            },
          ),
        );
      },
    );

    try {
      const batchSize = 10;
      bool allSuccess = true;

      for (int start = 0; start < notUploadedFiles.length; start += batchSize) {
        final end = (start + batchSize < notUploadedFiles.length)
            ? start + batchSize
            : notUploadedFiles.length;

        var request = http.MultipartRequest(
          'POST',
          Uri.parse('https://test.techstrota.com/api/photos/uploadAll'),
        );
        request.headers['Authorization'] = 'Bearer $token';

        for (int i = start; i < end; i++) {
          request.fields['folders[${i - start}]'] = notUploadedFolders[i];
          File compressed = await compressImage(notUploadedFiles[i]);

          final length = await compressed.length();
          final stream = http.ByteStream(compressed.openRead());

          request.files.add(
            http.MultipartFile(
              'images[${i - start}]',
              stream,
              length,
              filename: compressed.path.split('/').last,
            ),
          );
        }

        var response = await request.send();

        if (response.statusCode == 200) {
          for (int i = start; i < end; i++) {
            BottomTabs.uploadedFiles.value.add(
              File(notUploadedFiles[i].path).absolute.path,
            ); // ✅ use notUploadedFiles
          }
          BottomTabs.uploadedFiles.notifyListeners();
          await BottomTabs.saveUploadedFiles();
          uploadedCount.value += (end - start);
        } else {
          allSuccess = false;
          String err = await response.stream.bytesToString();
          debugPrint("Batch upload failed: $err");
          break;
        }
      }

      if (!context.mounted) return;
      Navigator.pop(context); // Close loader

      if (!context.mounted) return;
      if (allSuccess) {
        if (onUploadComplete != null) onUploadComplete!();
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text("Uploaded successfully")));
      } else {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text("Some uploads failed")));
      }
    } catch (e) {
      if (!context.mounted) return;
      Navigator.pop(context);
      debugPrint("❌ Upload error: $e");
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Upload failed")));
    }
  }

  @override
  Widget build(BuildContext context) {
    final tabController = controller ?? DefaultTabController.of(context);
    final colorScheme = Theme.of(context).colorScheme;

    return Material(
      color: colorScheme.surface,
      child: TabBar(
        controller: tabController,
        onTap: (index) {
          if (index == 1) {
            _resetTab(tabController);
            if (onUploadTap != null) {
              onUploadTap!(); // call parent callback (PhotoListScreen)
            } else {
              uploadImagesToServer(context); // fallback to default
            }
            return;
          }

          if (index == 2) {
            if (cameraDisabled) {
              _resetTab(tabController);
              return;
            }
            if (showCamera && onCameraTap != null) {
              onCameraTap!();
              _resetTab(tabController);
              return;
            }
          }

          if (index == 3 && onCreateFolder != null) {
            onCreateFolder!(index);
            _resetTab(tabController);
            return;
          }

          // if (index == 4) {
          //   // Handle Scan tab click
          //   _resetTab(tabController);
          //   Navigator.push(
          //     context,
          //     MaterialPageRoute(
          //       builder: (_) => const ScanScreen(), // Your scan screen widget
          //     ),
          //   );
          //   return;
          // }

          controller?.index = index;
        },
        labelColor: colorScheme.primary,
        unselectedLabelColor: colorScheme.onSurface,
        indicatorColor: colorScheme.primary,
        tabs: [
          const Tab(icon: Icon(Icons.folder), text: 'Folders'),
          const Tab(icon: Icon(Icons.cloud_upload), text: 'Upload'),
          if (showCamera)
            Tab(
              icon: Icon(
                Icons.camera_alt,
                color: cameraDisabled ? Colors.grey : null,
              ),
              text: 'Camera',
            ),
          const Tab(icon: Icon(Icons.create_new_folder), text: 'Create'),
          // const Tab(
          //   icon: Icon(Icons.document_scanner),
          //   text: 'Scan',
          // ),
        ],
      ),
    );
  }

  void _resetTab(TabController controller) {
    Future.microtask(() {
      controller.index = 0;
    });
  }
}

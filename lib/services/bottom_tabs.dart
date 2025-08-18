import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:photomanager_practice/screen/scan_screen.dart';
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

  const BottomTabs({
    super.key,
    this.controller,
    this.showCamera = true,
    this.cameraDisabled = false,
    this.scanDisabled = false,
    this.onCreateFolder,
    this.onCameraTap,
    this.onUploadTap,
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
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Upload Confirmation"),
        content: const Text(
          "Do you want to upload all folders and images to the server?",
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

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surface,
        content: Row(
          children: [
            const CircularProgressIndicator(),
            const SizedBox(width: 20),
            Expanded(
              child: Text(
                "Uploading images...",
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          ],
        ),
      ),
    );

    SharedPreferences prefs = await SharedPreferences.getInstance();
    String? userId = prefs.getInt('user_id')?.toString();
    String? token = prefs.getString('auth_token');

    if (userId == null || token == null) {
      Navigator.pop(context);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("User not logged in")));
      return;
    }

    Directory baseDir = Directory('/storage/emulated/0/Pictures/MyApp/$userId');
    if (!await baseDir.exists()) {
      Navigator.pop(context);
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
      Navigator.pop(context);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("No images found")));
      return;
    }

    try {
      const batchSize = 10; // You can change this to 10 or another number
      bool allSuccess = true;

      for (int start = 0; start < imageFiles.length; start += batchSize) {
        final end = (start + batchSize < imageFiles.length)
            ? start + batchSize
            : imageFiles.length;

        var request = http.MultipartRequest(
          'POST',
          Uri.parse('https://badal.techstrota.com/api/photos/uploadAll'),
        );
        request.headers['Authorization'] = 'Bearer $token';

        for (int i = start; i < end; i++) {
          request.fields['folders[${i - start}]'] = folderNames[i];
          final length = await imageFiles[i].length();
          final stream = http.ByteStream(imageFiles[i].openRead());
          request.files.add(
            http.MultipartFile(
              'images[${i - start}]',
              stream,
              length,
              filename: imageFiles[i].path.split('/').last,
            ),
          );
        }

        var response = await request.send();

        if (response.statusCode != 200) {
          allSuccess = false;
          String err = await response.stream.bytesToString();
          debugPrint("Batch upload failed: $err");
          break; // Stop on first failure
        }
      }

      Navigator.pop(context); // Close loader

      if (allSuccess) {
        for (var file in imageFiles) {
          await file.delete();
        }
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text("Uploaded successfully")));
      } else {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text("Some uploads failed")));
      }
    } catch (e) {
      Navigator.pop(context);
      debugPrint("\u274C Upload error: $e");
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
            uploadImagesToServer(context);
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

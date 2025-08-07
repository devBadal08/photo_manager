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
  final void Function(int)? onCreateFolder;
  final VoidCallback? onCameraTap;
  final VoidCallback? onUploadTap;

  const BottomTabs({
    super.key,
    this.controller,
    this.showCamera = true,
    this.cameraDisabled = false,
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
      var request = http.MultipartRequest(
        'POST',
        Uri.parse('https://badal.techstrota.com/api/photos/uploadAll'),
      );
      request.headers['Authorization'] = 'Bearer $token';

      for (int i = 0; i < imageFiles.length; i++) {
        request.fields['folders[$i]'] = folderNames[i];
        request.files.add(
          await http.MultipartFile.fromPath('images[$i]', imageFiles[i].path),
        );
      }

      var response = await request.send();

      Navigator.pop(context); // Close loader

      if (response.statusCode == 200) {
        for (var file in imageFiles) {
          await file.delete();
        }
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text("Uploaded successfully")));
      } else {
        String err = await response.stream.bytesToString();
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Failed: $err")));
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
    final textTheme = Theme.of(context).textTheme;

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
          controller?.index = index;
        },
        labelColor: colorScheme.primary,
        unselectedLabelColor: colorScheme.onSurface,
        indicatorColor: colorScheme.primary,
        tabs: [
          Tab(icon: const Icon(Icons.folder), text: 'Folders'),
          Tab(icon: const Icon(Icons.cloud_upload), text: 'Upload'),
          if (showCamera)
            Tab(
              icon: Icon(
                Icons.camera_alt,
                color: cameraDisabled ? Colors.grey : null,
              ),
              text: 'Camera',
            ),
          const Tab(icon: Icon(Icons.create_new_folder), text: 'Create'),
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

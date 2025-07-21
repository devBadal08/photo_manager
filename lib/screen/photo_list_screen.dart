import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:photomanager_practice/services/photo_service.dart';
import 'package:permission_handler/permission_handler.dart';

class PhotoListScreen extends StatefulWidget {
  final Directory folder;
  const PhotoListScreen({super.key, required this.folder});

  @override
  State<PhotoListScreen> createState() => _PhotoListScreenState();
}

class _PhotoListScreenState extends State<PhotoListScreen> {
  List<FileSystemEntity> items = [];

  @override
  void initState() {
    super.initState();
    requestPermissions(); // Ask for storage access
    _loadItems();
  }

  Future<void> requestPermissions() async {
    if (Platform.isAndroid) {
      final androidInfo = await DeviceInfoPlugin().androidInfo;
      if (androidInfo.version.sdkInt >= 33) {
        final photosStatus = await Permission.photos.request();
        if (!photosStatus.isGranted) {
          print("❌ Permission.photos denied");
          return;
        }
      } else {
        final storageStatus = await Permission.storage.request();
        if (!storageStatus.isGranted) {
          print("❌ Permission.storage denied");
          return;
        }
      }
    }
  }

  Future<void> _pickAndUploadImage() async {
    final pickedFile = await ImagePicker().pickImage(
      source: ImageSource.gallery,
    );

    if (pickedFile != null) {
      final File imageFile = File(pickedFile.path);

      // ✅ Extract folder name from widget.folder path
      final folderName = widget.folder.path.split('/').last;

      // ✅ Upload to server
      bool success = await PhotoService.uploadImage(imageFile, folderName);

      if (success) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Photo uploaded')));
        _loadItems();
      } else {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Upload failed')));
      }
      //await _loadItems();
    }
  }

  Future<void> _takePhoto() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.camera);

    if (pickedFile != null) {
      // Save to local folder
      Directory targetFolder = widget.folder;
      if (Platform.isAndroid) {
        targetFolder = Directory(
          '/storage/emulated/0/Pictures/MyApp/${widget.folder.path.split('/').last}',
        );
      }

      if (!await targetFolder.exists()) {
        await targetFolder.create(recursive: true);
      }

      final imageName = '${DateTime.now().millisecondsSinceEpoch}.jpg';
      final savedPath = '${targetFolder.path}/$imageName';
      final savedFile = await File(pickedFile.path).copy(savedPath);
      print("✅ Image exists: ${await File(savedPath).exists()}");

      print("📸 Photo saved at: ${savedFile.path}");

      // ✅ Upload to server
      final folderName = widget.folder.path.split('/').last;

      bool success = await PhotoService.uploadImage(savedFile, folderName);
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ Photo uploaded from camera')),
        );
      } else {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('❌ Upload failed')));
      }

      _loadItems(); // refresh local UI
    }
  }

  Future<void> _loadItems() async {
    Directory currentFolder = widget.folder;

    if (Platform.isAndroid) {
      final folderName = widget.folder.path.split('/').last;
      currentFolder = Directory(
        '/storage/emulated/0/Pictures/MyApp/$folderName',
      );
    }

    print("📁 Trying to load from folder: ${currentFolder.path}");

    if (!await currentFolder.exists()) {
      print("❌ Folder does not exist: ${currentFolder.path}");
      return;
    }

    final entries = await currentFolder.list().toList();
    final dirs = entries.whereType<Directory>().toList();
    final files = entries
        .whereType<File>()
        .where((f) => f.path.endsWith('.jpg') || f.path.endsWith('.png'))
        .toList();

    print("📂 Found ${files.length} image files in ${currentFolder.path}");

    setState(() {
      items = [...dirs, ...files];
    });
  }

  Future<void> _showCreateSubFolderDialog() async {
    String folderName = '';

    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Enter Subfolder Name'),
          content: TextField(
            autofocus: true,
            decoration: const InputDecoration(hintText: 'MySubFolder'),
            onChanged: (value) {
              folderName = value;
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                _createSubFolder(folderName);
              },
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _createSubFolder(String name) async {
    if (name.isEmpty) return;

    final newFolder = Directory('${widget.folder.path}/$name');

    if (!await newFolder.exists()) {
      await newFolder.create();
      print("📁 Subfolder created at: ${newFolder.path}");
    } else {
      print("⚠️ Subfolder already exists at: ${newFolder.path}");
    }

    _loadItems();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.folder.path.split('/').last),
        actions: [
          IconButton(
            icon: const Icon(Icons.file_upload),
            onPressed: _pickAndUploadImage,
            tooltip: "Upload from Gallery",
          ),
        ],
      ),
      body: items.isEmpty
          ? const Center(child: Text("No files or subfolders yet"))
          : GridView.builder(
              padding: const EdgeInsets.all(12),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                childAspectRatio: 1,
              ),
              itemCount: items.length,
              itemBuilder: (context, index) {
                final item = items[index];
                final name = item.path.split('/').last;

                if (item is Directory) {
                  return GestureDetector(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => PhotoListScreen(folder: item),
                        ),
                      );
                    },
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          height: 80,
                          width: 80,
                          decoration: BoxDecoration(
                            color: Colors.deepPurple.shade100,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.folder,
                            size: 40,
                            color: Colors.deepPurple,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          name,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  );
                } else {
                  return ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.file(File(item.path), fit: BoxFit.cover),
                  );
                }
              },
            ),
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          FloatingActionButton(
            heroTag: 'createFolder',
            onPressed: _showCreateSubFolderDialog,
            child: const Icon(Icons.create_new_folder),
          ),
          const SizedBox(height: 16),
          FloatingActionButton(
            heroTag: 'takePhoto',
            onPressed: _takePhoto,
            child: const Icon(Icons.camera_alt),
          ),
        ],
      ),
    );
  }
}

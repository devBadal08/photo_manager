import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';

import 'package:photomanager_practice/services/bottom_tabs.dart';
import 'package:photomanager_practice/services/photo_service.dart';

class PhotoListScreen extends StatefulWidget {
  final Directory folder;
  const PhotoListScreen({super.key, required this.folder});

  @override
  State<PhotoListScreen> createState() => _PhotoListScreenState();
}

class _PhotoListScreenState extends State<PhotoListScreen> {
  List<FileSystemEntity> items = [];
  bool uploadEnabled = false;
  bool selectionMode = false;
  List<File> selectedImages = [];
  int totalSubfolders = 0;
  int totalImages = 0;

  @override
  void initState() {
    super.initState();
    requestPermissions();
    _loadItems();
    countSubfoldersAndImages(widget.folder.path);
  }

  Future<void> requestPermissions() async {
    if (Platform.isAndroid) {
      final androidInfo = await DeviceInfoPlugin().androidInfo;
      if (androidInfo.version.sdkInt >= 33) {
        await Permission.photos.request();
      } else {
        await Permission.storage.request();
      }
    }
  }

  Future<void> countSubfoldersAndImages(String folderPath) async {
    final Directory selectedDir = Directory(folderPath);
    int subfolderCount = 0;
    int imageCount = 0;

    final List<FileSystemEntity> entities = selectedDir.listSync();

    for (FileSystemEntity entity in entities) {
      if (entity is Directory) {
        subfolderCount++;
        final List<FileSystemEntity> subFiles = entity.listSync();
        for (FileSystemEntity subEntity in subFiles) {
          if (subEntity is File &&
              (subEntity.path.endsWith('.jpg') ||
                  subEntity.path.endsWith('.jpeg') ||
                  subEntity.path.endsWith('.png'))) {
            imageCount++;
          }
        }
      } else if (entity is File &&
          (entity.path.endsWith('.jpg') ||
              entity.path.endsWith('.jpeg') ||
              entity.path.endsWith('.png'))) {
        imageCount++;
      }
    }

    setState(() {
      totalSubfolders = subfolderCount;
      totalImages = imageCount;
    });
  }

  Future<void> _takePhoto() async {
    final pickedFile = await ImagePicker().pickImage(
      source: ImageSource.camera,
    );

    if (pickedFile != null) {
      final targetFolder = widget.folder;
      if (!await targetFolder.exists()) {
        await targetFolder.create(recursive: true);
      }

      final fileName = 'IMG_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final savedFile = await File(
        pickedFile.path,
      ).copy('${targetFolder.path}/$fileName');

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('📥 Photo saved locally')));

      _loadItems(); // Refresh the UI
    }
  }

  Future<void> _loadItems() async {
    final folder = widget.folder;
    if (!await folder.exists()) return;

    final entries = await folder.list().toList();
    final files = entries.whereType<File>().where((f) {
      final ext = f.path.toLowerCase();
      return ext.endsWith('.jpg') ||
          ext.endsWith('.jpeg') ||
          ext.endsWith('.png');
    }).toList();

    final dirs = entries.whereType<Directory>().toList();

    setState(() {
      items = [...dirs, ...files];
    });
  }

  Future<void> _showCreateSubFolderDialog() async {
    String folderName = '';

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Enter Subfolder Name'),
        content: TextField(
          autofocus: true,
          decoration: const InputDecoration(hintText: 'MySubFolder'),
          onChanged: (value) => folderName = value,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _createSubFolder(folderName);
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _createSubFolder(String name) async {
    if (name.isEmpty) return;
    final newFolder = Directory('${widget.folder.path}/$name');
    if (!await newFolder.exists()) {
      await newFolder.create(recursive: true);
    }
    _loadItems();
  }

  @override
  Widget build(BuildContext context) {
    //final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const SizedBox(width: 8),
                  Center(
                    child: Text(
                      widget.folder.path.split('/').last,
                      style: textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const Spacer(),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const Text('📁'),
                      const SizedBox(width: 4),
                      Text(totalSubfolders.toString()),
                    ],
                  ),
                  Row(
                    children: [
                      const Text('🖼️'),
                      const SizedBox(width: 4),
                      Text(totalImages.toString()),
                    ],
                  ),
                ],
              ),
            ],
          ),
          centerTitle: true,
          backgroundColor: Theme.of(context).appBarTheme.backgroundColor,
          foregroundColor: Theme.of(context).appBarTheme.foregroundColor,
          actions: [
            PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'select') {
                  setState(() {
                    selectionMode = true;
                    selectedImages.clear();
                  });
                }
              },
              itemBuilder: (_) => [
                const PopupMenuItem(
                  value: 'select',
                  child: Text('Select Photos to Upload'),
                ),
              ],
              icon: const Icon(Icons.more_vert),
            ),
          ],
          elevation: 4,
        ),
        body: items.isEmpty
            ? Center(
                child: Text(
                  "No files or subfolders yet",
                  style: textTheme.bodyMedium,
                ),
              )
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
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => PhotoListScreen(folder: item),
                        ),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Expanded(
                            child: Container(
                              height: 80,
                              width: 80,
                              decoration: BoxDecoration(
                                color: Theme.of(context).cardColor,
                                borderRadius: BorderRadius.circular(15),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.1),
                                    spreadRadius: 1,
                                    blurRadius: 4,
                                    offset: const Offset(2, 4),
                                  ),
                                ],
                              ),
                              child: const Center(
                                child: Icon(
                                  Icons.folder,
                                  size: 40,
                                  color: Color(0xFFF9A825),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            name,
                            style: textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    );
                  } else {
                    final file = File(item.path);
                    final isSelected = selectedImages.contains(file);

                    return GestureDetector(
                      onTap: () {
                        if (selectionMode) {
                          setState(() {
                            isSelected
                                ? selectedImages.remove(file)
                                : selectedImages.add(file);
                          });
                        }
                      },
                      child: Stack(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.file(
                              file,
                              fit: BoxFit.cover,
                              width: double.infinity,
                              height: double.infinity,
                            ),
                          ),
                          if (selectionMode)
                            Positioned(
                              top: 5,
                              right: 5,
                              child: CircleAvatar(
                                radius: 12,
                                backgroundColor: isSelected
                                    ? Colors.blue
                                    : Colors.grey.shade400,
                                child: Icon(
                                  isSelected ? Icons.check : Icons.circle,
                                  size: 14,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                        ],
                      ),
                    );
                  }
                },
              ),
        bottomNavigationBar: Builder(
          builder: (context) => BottomTabs(
            controller: DefaultTabController.of(context),
            showCamera: true,
            onCreateFolder: (int index) {
              if (index == 3) _showCreateSubFolderDialog();
            },
            onCameraTap: _takePhoto,
            onUploadTap: () async {
              final photoService = PhotoService();
              await photoService.uploadAllImagesForUser();
            },
          ),
        ),
      ),
    );
  }
}

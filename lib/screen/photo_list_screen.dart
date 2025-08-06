import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:photomanager_practice/services/bottom_tabs.dart';
import 'package:photomanager_practice/services/photo_service.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  @override
  void initState() {
    super.initState();
    requestPermissions();
    _loadItems();
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

  Future<void> _uploadSelectedImages() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');

    if (token == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('❌ No auth token found')));
      return;
    }

    final folderName = widget.folder.path.split('/').last;
    int successCount = 0;

    for (var image in selectedImages) {
      final success = await PhotoService.uploadImage(
        imageFile: image,
        folderName: folderName,
        token: token,
      );

      if (success) {
        successCount++;
      }
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '✅ Uploaded $successCount of ${selectedImages.length} selected photo(s)',
        ),
      ),
    );

    setState(() {
      selectionMode = false;
      selectedImages.clear();
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

      final imageName = '${DateTime.now().millisecondsSinceEpoch}.jpg';
      final savedFile = await File(
        pickedFile.path,
      ).copy('${targetFolder.path}/$imageName');

      final basePath = '/storage/emulated/0/Pictures/MyApp';
      final relativePath = widget.folder.path.replaceFirst('$basePath/', '');

      if (uploadEnabled) {
        final prefs = await SharedPreferences.getInstance();
        final token = prefs.getString('auth_token');

        if (token == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('❌ No auth token found')),
          );
          return;
        }

        // final success = await PhotoService.uploadImage(
        //   imageFile: savedFile,
        //   folderName: relativePath,
        //   token: token,
        // );

        // if (success) {
        //   await savedFile.delete();
        //   ScaffoldMessenger.of(context).showSnackBar(
        //     const SnackBar(content: Text('✅ Photo uploaded & deleted locally')),
        //   );
        // } else {
        //   ScaffoldMessenger.of(
        //     context,
        //   ).showSnackBar(const SnackBar(content: Text('❌ Upload failed')));
        // }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('📥 Photo saved locally only')),
        );
      }

      _loadItems();
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

    // Count total images including subfolders
    int totalImageCount = files.length;

    for (var dir in dirs) {
      totalImageCount += await _countImagesInDirectory(dir);
    }

    print("📸 Total images (including subfolders): $totalImageCount");

    setState(() {
      items = [...dirs, ...files];
    });
  }

  Future<int> _countImagesInDirectory(Directory dir) async {
    int count = 0;

    if (!await dir.exists()) return 0;

    final contents = await dir.list(recursive: true).toList();

    for (var item in contents) {
      if (item is File) {
        final ext = item.path.toLowerCase();
        if (ext.endsWith('.jpg') ||
            ext.endsWith('.jpeg') ||
            ext.endsWith('.png')) {
          count++;
        }
      }
    }

    return count;
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
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.folder.path.split('/').last),
          centerTitle: true,
          backgroundColor: const Color(0xFF1F1F1F),
          foregroundColor: Colors.white,
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
              itemBuilder: (BuildContext context) => [
                const PopupMenuItem<String>(
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
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(15),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.grey.withOpacity(0.3),
                                  spreadRadius: 2,
                                  blurRadius: 5,
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
                    final file = File(item.path);
                    final isSelected = selectedImages.contains(file);

                    return GestureDetector(
                      onTap: () {
                        if (selectionMode) {
                          setState(() {
                            if (isSelected) {
                              selectedImages.remove(file);
                            } else {
                              selectedImages.add(file);
                            }
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
              if (index == 3) {
                _showCreateSubFolderDialog();
              }
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

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
  String selectedSegment = 'Folders';
  List<Directory> folderItems = [];
  List<File> imageItems = [];

  @override
  void initState() {
    super.initState();
    //requestPermissions();
    _loadItems();
    countSubfoldersAndImages(widget.folder.path);
  }

  // Future<void> requestPermissions() async {
  //   if (!Platform.isAndroid) return;

  //   final androidInfo = await DeviceInfoPlugin().androidInfo;
  //   final sdkInt = androidInfo.version.sdkInt;

  //   if (sdkInt >= 33) {
  //     // Android 13 and above
  //     await [Permission.photos, Permission.videos, Permission.audio].request();
  //   } else if (sdkInt == 30 || sdkInt == 31 || sdkInt == 32) {
  //     // Android 11 and 12
  //     await Permission.manageExternalStorage.request();
  //   } else {
  //     // Android 10 and below
  //     await Permission.storage.request();
  //   }
  // }

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
    final dirs = entries.whereType<Directory>().toList();
    final files = entries.whereType<File>().where((f) {
      final ext = f.path.toLowerCase();
      return ext.endsWith('.jpg') ||
          ext.endsWith('.jpeg') ||
          ext.endsWith('.png');
    }).toList();

    setState(() {
      folderItems = dirs;
      imageItems = files;
      items = [...dirs, ...files]; // optional if still needed elsewhere
    });
  }

  Future<void> _renameFolder(Directory folder) async {
    final TextEditingController controller = TextEditingController();

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename Folder'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(hintText: 'New folder name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final newName = controller.text.trim();
              Navigator.pop(context); // Close dialog

              if (newName.isNotEmpty) {
                final newPath = '${folder.parent.path}/$newName';
                final newDir = Directory(newPath);

                if (!await newDir.exists()) {
                  await folder.rename(newPath);
                  _loadItems(); // Refresh UI
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Folder already exists')),
                  );
                }
              }
            },
            child: const Text('Rename'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteFolder(Directory folder) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Folder'),
        content: const Text('Are you sure you want to delete this folder?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (shouldDelete == true) {
      try {
        await folder.delete(recursive: true);
        _loadItems(); // Refresh UI
      } catch (e) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error deleting folder: $e')));
      }
    }
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
          title: Text(
            widget.folder.path.split('/').last,
            style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
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

        body: Column(
          children: [
            SegmentedButton<String>(
              segments: const <ButtonSegment<String>>[
                ButtonSegment<String>(
                  value: 'Folders',
                  label: Text('Folders'),
                  icon: Icon(Icons.folder), // required in newer versions
                ),
                ButtonSegment<String>(
                  value: 'Images',
                  label: Text('Images'),
                  icon: Icon(Icons.image), // required
                ),
              ],
              selected: {selectedSegment},
              onSelectionChanged: (Set<String> newSelection) {
                setState(() {
                  selectedSegment = newSelection.first;
                });
              },
            ),
            const SizedBox(height: 10),

            Expanded(
              child:
                  (selectedSegment == 'Folders' && folderItems.isEmpty) ||
                      (selectedSegment == 'Images' && imageItems.isEmpty)
                  ? Center(
                      child: Text(
                        "No ${selectedSegment.toLowerCase()} yet",
                        style: textTheme.bodyMedium,
                      ),
                    )
                  : selectedSegment == 'Folders'
                  ? _buildFolderListCards() // ✅ Use the new list card builder
                  : _buildImageGrid(imageItems),
            ),
          ],
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

  Widget _buildFolderListCards() {
    if (folderItems.isEmpty) {
      return const Center(
        child: Text("No folders yet", style: TextStyle(color: Colors.white70)),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: folderItems.length,
      itemBuilder: (context, index) {
        final folder = folderItems[index];
        final folderName = folder.path.split('/').last;

        return Card(
          margin: const EdgeInsets.symmetric(vertical: 8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: 4,
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(
              vertical: 12,
              horizontal: 16,
            ),
            leading: const Icon(Icons.folder, size: 40, color: Colors.orange),
            title: Text(
              folderName,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            subtitle: FutureBuilder<Map<String, int>>(
              future: _countSingleFolder(folder), // Custom method below
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Text('Loading...');
                }
                final subfolderCount = snapshot.data?['subfolders'] ?? 0;
                final imageCount = snapshot.data?['images'] ?? 0;

                return Text(
                  'Subfolders: $subfolderCount\nImages: $imageCount',
                  style: Theme.of(context).textTheme.bodySmall,
                );
              },
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.edit, color: Colors.blueAccent),
                  onPressed: () => _renameFolder(folder),
                ),
                IconButton(
                  icon: const Icon(Icons.delete, color: Colors.redAccent),
                  onPressed: () => _deleteFolder(folder),
                ),
              ],
            ),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => PhotoListScreen(folder: folder),
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildImageGrid(List<File> images) {
    return GridView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: images.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 4,
        mainAxisSpacing: 4,
      ),
      itemBuilder: (context, index) {
        return Image.file(images[index], fit: BoxFit.cover);
      },
    );
  }

  Future<Map<String, int>> _countSingleFolder(Directory folder) async {
    int subfolderCount = 0;
    int imageCount = 0;

    final List<FileSystemEntity> entities = folder.listSync();
    for (FileSystemEntity entity in entities) {
      if (entity is Directory) {
        subfolderCount++;
        final subEntities = entity.listSync();
        for (FileSystemEntity sub in subEntities) {
          if (sub is File &&
              (sub.path.endsWith('.jpg') ||
                  sub.path.endsWith('.jpeg') ||
                  sub.path.endsWith('.png'))) {
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

    return {'subfolders': subfolderCount, 'images': imageCount};
  }
}

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:image_picker/image_picker.dart';
import 'package:photomanager_practice/screen/camera_screen.dart';
import 'package:photomanager_practice/screen/gallery_screen.dart';
import 'package:photomanager_practice/screen/scan_screen.dart';
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
  late PageController _pageController;
  bool uploadEnabled = false;
  bool selectionMode = false;
  List<File> selectedImages = [];
  int totalSubfolders = 0;
  int totalImages = 0;
  String selectedSegment = 'Folders';
  List<Directory> folderItems = [];
  List<File> imageItems = [];
  bool isSearching = false;
  String searchQuery = '';
  List<Directory> filteredFolders = [];
  //List<File> filteredImages = [];

  String get _mainFolderName => widget.folder.path.split('/').last;

  @override
  void initState() {
    super.initState();
    //requestPermissions();
    _pageController = PageController();
    _loadItems();
    countSubfoldersAndImages(widget.folder.path);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
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
    final List<CameraDescription> cameras = await availableCameras();
    final capturedImagePath =
        await Navigator.push<String>(
          context,
          MaterialPageRoute(
            builder: (_) => CameraScreen(
              saveFolder: widget.folder,
              cameras: cameras,
            ), // Pass params if needed
          ),
        ).then((_) {
          _loadItems(); // Refresh after coming back
        });

    if (capturedImagePath != null && capturedImagePath.isNotEmpty) {
      final File capturedImage = File(capturedImagePath);
      final String newPath =
          '${widget.folder.path}/${DateTime.now().millisecondsSinceEpoch}.jpg';
      await capturedImage.copy(newPath); // Save into current folder
      _loadItems(); // Refresh the list
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

    // ✅ remove subfolders that match parent folder name (case-insensitive)
    final validDirs = dirs.where((d) {
      final sub = d.path.split('/').last;
      return sub.toLowerCase() != _mainFolderName.toLowerCase();
    }).toList();

    // (optional) keep your "latest first" sort
    validDirs.sort(
      (a, b) => b.statSync().changed.compareTo(a.statSync().changed),
    );

    setState(() {
      folderItems = validDirs;
      imageItems = files;
      items = [...validDirs, ...files];
      filteredFolders = List.from(folderItems);
    });
  }

  void _filterItems(String query) {
    setState(() {
      searchQuery = query.toLowerCase();
      filteredFolders = folderItems
          .where(
            (folder) =>
                folder.path.split('/').last.toLowerCase().contains(searchQuery),
          )
          .toList();
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
              Navigator.pop(context);

              if (newName.isEmpty) return;

              // ❌ block rename to match parent folder name
              if (newName.toLowerCase() == _mainFolderName.toLowerCase()) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      "Folder name cannot be the same as the parent folder.",
                    ),
                  ),
                );
                return;
              }

              final newPath = '${folder.parent.path}/$newName';
              final newDir = Directory(newPath);

              if (!await newDir.exists()) {
                await folder.rename(newPath);
                _loadItems();
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Folder already exists')),
                );
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
          onChanged: (value) => folderName = value.trim(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              if (folderName.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Folder name cannot be empty')),
                );
                return;
              }

              if (folderName.length > 20) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Folder name must be 20 characters or less'),
                  ),
                );
                return;
              }

              Navigator.pop(context); // Close dialog if validation passes
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
    final candidate = name.trim();
    if (candidate.isEmpty) return;

    // ❌ prevent subfolder name equal to main folder name (case-insensitive)
    if (candidate.toLowerCase() == _mainFolderName.toLowerCase()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "Subfolder name cannot be the same as the parent folder.",
          ),
        ),
      );
      return;
    }

    if (!await newFolder.exists()) {
      await newFolder.create(recursive: true);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Subfolder "$name" created')));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Subfolder "$name" already exists')),
      );
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
          title: isSearching
              ? TextField(
                  autofocus: true,
                  decoration: InputDecoration(
                    hintText: selectedSegment == 'Folders'
                        ? 'Search folders...'
                        : 'Search images...',
                    hintStyle: TextStyle(
                      color: Theme.of(context).hintColor, // ✅ theme-aware
                    ),
                    border: InputBorder.none,
                  ),
                  style: TextStyle(
                    color: Theme.of(
                      context,
                    ).textTheme.bodyLarge?.color, // ✅ adapts to light/dark
                    fontSize: 18,
                  ),
                  onChanged: _filterItems,
                )
              : Text(
                  widget.folder.path.split('/').last,
                  style: textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
          centerTitle: true,
          backgroundColor: Theme.of(context).appBarTheme.backgroundColor,
          foregroundColor: Theme.of(context).appBarTheme.foregroundColor,
          actions: [
            if (!isSearching)
              IconButton(
                icon: const Icon(Icons.search),
                onPressed: () {
                  setState(() {
                    isSearching = true;
                    searchQuery = '';
                  });
                },
              ),
            if (isSearching)
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () {
                  setState(() {
                    isSearching = false;
                    searchQuery = '';
                    filteredFolders = List.from(folderItems);
                  });
                },
              ),
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
                  icon: Icon(Icons.folder),
                ),
                ButtonSegment<String>(
                  value: 'Images',
                  label: Text('Images'),
                  icon: Icon(Icons.image),
                ),
              ],
              selected: {selectedSegment},
              onSelectionChanged: (Set<String> newSelection) {
                setState(() {
                  selectedSegment = newSelection.first;
                });
                // Animate PageView when segment changes
                _pageController.animateToPage(
                  selectedSegment == 'Folders' ? 0 : 1,
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOut,
                );
              },
            ),

            const SizedBox(height: 10),

            Expanded(
              child: PageView(
                controller: _pageController,
                onPageChanged: (index) {
                  setState(() {
                    selectedSegment = index == 0 ? 'Folders' : 'Images';
                  });
                },
                children: [
                  // --- Folders Page ---
                  folderItems.isEmpty
                      ? Center(
                          child: Text(
                            "No folders yet",
                            style: textTheme.bodyMedium,
                          ),
                        )
                      : _buildFolderListCards(filteredFolders),

                  // --- Images Page ---
                  imageItems.isEmpty
                      ? Center(
                          child: Text(
                            "No images yet",
                            style: textTheme.bodyMedium,
                          ),
                        )
                      : _buildImageGrid(imageItems),
                ],
              ),
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

  Widget _buildFolderListCards(List<Directory> folders) {
    if (folders.isEmpty) {
      return const Center(
        child: Text("No folders yet", style: TextStyle(color: Colors.white70)),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: folders.length,
      itemBuilder: (context, index) {
        final folder = folders[index];
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
        return GestureDetector(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => GalleryScreen(
                  images: images.map((file) => File(file.path)).toList(),
                ),
              ),
            );
          },
          child: Image.file(images[index], fit: BoxFit.cover),
        );
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

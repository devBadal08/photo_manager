import 'dart:io';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:photomanager_practice/screen/camera_screen.dart';
import 'package:photomanager_practice/screen/gallery_screen.dart';
import 'package:photomanager_practice/services/auto_upload_service.dart';
import 'package:photomanager_practice/services/bottom_tabs.dart';
import 'package:photomanager_practice/services/folder_share_service.dart';
import 'package:photomanager_practice/services/photo_service.dart';

class PhotoListScreen extends StatefulWidget {
  final Directory? folder;
  final int? sharedFolderId; // backend folder
  final String? sharedFolderName;
  final bool isShared;

  const PhotoListScreen({
    super.key,
    this.folder,
    this.sharedFolderId,
    this.sharedFolderName,
    this.isShared = false,
  });

  @override
  State<PhotoListScreen> createState() => _PhotoListScreenState();
}

class _PhotoListScreenState extends State<PhotoListScreen> {
  List<FileSystemEntity> items = [];
  late PageController _pageController;
  bool uploadEnabled = false;
  bool selectionMode = false;
  List<String> selectedImages = [];
  int totalSubfolders = 0;
  int totalImages = 0;
  String selectedSegment = 'Folders';
  List<Directory> folderItems = [];
  List<File> imageItems = [];
  List<Map<String, dynamic>> apiPhotos = [];
  bool isSearching = false;
  String searchQuery = '';
  List<Directory> filteredFolders = [];
  //List<File> filteredImages = [];
  List<Map<String, dynamic>> _newlyTakenPhotos = [];

  String get _mainFolderName => widget.isShared
      ? (widget.sharedFolderName ?? "Shared Folder")
      : (widget.folder?.path.split('/').last ?? "Unnamed Folder");

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: 0);

    print(
      "🔍 isShared=${widget.isShared}, sharedFolderId=${widget.sharedFolderId}",
    );

    if (widget.isShared && widget.sharedFolderId != null) {
      _loadSharedPhotos(widget.sharedFolderId!);
    } else if (widget.folder != null) {
      _loadItems();
      countSubfoldersAndImages(widget.folder!.path);
    }
  }

  List<dynamic> images = [];

  bool isMedia(String filePath) {
    final mediaExtensions = ['jpg', 'jpeg', 'png', 'mp4'];
    final extension = filePath.split('.').last.toLowerCase();
    return mediaExtensions.contains(extension);
  }

  bool isVideo(String filePath) {
    final videoExtensions = ['mp4'];
    final extension = filePath.split('.').last.toLowerCase();
    return videoExtensions.contains(extension);
  }

  Future<void> _loadSharedPhotos(int folderId) async {
    final dir = Directory(
      '/storage/emulated/0/Pictures/MyApp/Shared/$folderId',
    );
    if (!await dir.exists()) await dir.create(recursive: true);

    // 🔄 Get uploaded files
    final uploadedSet = PhotoService.uploadedFiles.value;

    // 📂 Local images & videos (only pending)
    final localFiles = dir
        .listSync()
        .whereType<File>()
        .where((f) => isMedia(f.path) && !uploadedSet.contains(f.path))
        .toList();

    final localPhotos = localFiles
        .map((f) => {"path": f.path, "local": true})
        .toList();

    // 🌐 Server images (not uploaded by this device)
    final service = FolderShareService();
    final data = await service.getSharedFolderPhotos(folderId);

    List<Map<String, dynamic>> serverPhotos = [];
    if (data != null && data['success'] == true) {
      serverPhotos = List<Map<String, dynamic>>.from(
        data['photos'],
      ).map((p) => {"path": p['path'], "local": false}).toList();
    }

    // 🔹 Remove uploaded files from _newlyTakenPhotos
    _newlyTakenPhotos = _newlyTakenPhotos
        .where((p) => !uploadedSet.contains(p['path']))
        .toList();

    // ✅ Merge all photos
    final allPhotos = [..._newlyTakenPhotos, ...localPhotos, ...serverPhotos];

    // ✅ Remove duplicates by filename
    final uniquePhotos = <String, Map<String, dynamic>>{};
    for (var photo in allPhotos) {
      final filename = photo['path'].split('/').last;
      uniquePhotos[filename] = photo;
    }

    setState(() {
      apiPhotos = uniquePhotos.values.toList();
    });
  }

  @override
  void dispose() {
    imageCache.clear();
    imageCache.clearLiveImages();
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

    final capturedImagePaths = await Navigator.push<List<String>>(
      context,
      MaterialPageRoute(
        builder: (_) => CameraScreen(
          saveFolder: widget.isShared ? null : widget.folder,
          sharedFolderId: widget.isShared ? widget.sharedFolderId : null,
          cameras: cameras,
        ),
      ),
    );

    if (capturedImagePaths != null && capturedImagePaths.isNotEmpty) {
      await Future.delayed(
        const Duration(milliseconds: 500),
      ); // wait for OS write
      if (widget.isShared) {
        for (var path in capturedImagePaths) {
          // ✅ Only add if not uploaded yet
          if (!PhotoService.uploadedFiles.value.contains(path)) {
            _newlyTakenPhotos.add({"path": path, "local": true});
          }
        }

        _loadSharedPhotos(widget.sharedFolderId!);
      } else {
        _loadItems();
      }
    }

    // Auto-upload if enabled
    if (AutoUploadService.instance.isEnabled) {
      await AutoUploadService.instance.uploadNow();

      // Do NOT reload shared photos to avoid showing uploaded ones
      if (!widget.isShared) _loadItems();
    }
  }

  Future<void> _loadItems() async {
    final folder = widget.folder;
    if (folder == null || !await folder.exists()) return;

    final dirs = <Directory>[];
    final files = <File>[];

    await for (final entity in folder.list()) {
      if (entity is Directory) {
        final sub = entity.path.split('/').last;
        if (sub.toLowerCase() != _mainFolderName.toLowerCase()) {
          dirs.add(entity);
        }
      } else if (entity is File && isMedia(entity.path)) {
        files.add(entity);
      }
    }

    dirs.sort((a, b) => b.statSync().changed.compareTo(a.statSync().changed));
    if (!mounted) return;

    setState(() {
      folderItems = dirs;
      imageItems = files; // now contains images + videos
      items = [...dirs, ...files];
      filteredFolders = List.from(dirs);
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

              if (folderName.length > 50) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Folder name must be 50 characters or less'),
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
    if (name.isEmpty || widget.folder == null) return;

    final newFolder = Directory('${widget.folder!.path}/$name');
    final candidate = name.trim();
    if (candidate.isEmpty) return;

    if (candidate.toLowerCase() == _mainFolderName.toLowerCase()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Subfolder name cannot be same as parent"),
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

  Future<void> _deleteSelectedImages() async {
    if (selectedImages.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("No images selected")));
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Delete Uploaded Images"),
        content: Text(
          "Delete ${selectedImages.length} selected images?\n\n"
          "Only images that are uploaded will be deleted.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text("Delete"),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final uploadedSet = PhotoService.uploadedFiles.value;
      int deletedCount = 0;

      for (final file in selectedImages) {
        if (uploadedSet.contains(file)) {
          // ✅ only delete uploaded ones
          try {
            await File(file).delete();
            deletedCount++;
          } catch (e) {
            debugPrint("Error deleting ${file}: $e");
          }
        }
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Deleted $deletedCount uploaded images")),
      );

      setState(() {
        selectionMode = false;
        selectedImages.clear();
      });

      _loadItems(); // refresh grid
    }
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
                  _mainFolderName,
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
            // ✅ New Delete button in selection mode
            if (selectionMode)
              // IconButton(
              //   icon: const Icon(Icons.delete, color: Colors.red),
              //   onPressed: _deleteSelectedImages,
              // ),
              PopupMenuButton<String>(
                // onSelected: (value) {
                //   if (value == 'select') {
                //     setState(() {
                //       selectionMode = true;
                //       selectedImages.clear();
                //     });
                //   }
                // },
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
                  widget.isShared
                      ? Center(
                          child: Text(
                            "No folders in shared view",
                            style: textTheme.bodyMedium,
                          ),
                        )
                      : (folderItems.isEmpty
                            ? Center(
                                child: Text(
                                  "No folders yet",
                                  style: textTheme.bodyMedium,
                                ),
                              )
                            : _buildFolderListCards(filteredFolders)),

                  // --- Images Page ---
                  widget.isShared
                      ? (apiPhotos.isEmpty
                            ? Center(
                                child: Text(
                                  "No images yet in shared folder",
                                  style: textTheme.bodyMedium,
                                ),
                              )
                            : _buildApiImageGrid(apiPhotos))
                      : (imageItems.isEmpty
                            ? Center(
                                child: Text(
                                  "No images yet",
                                  style: textTheme.bodyMedium,
                                ),
                              )
                            : _buildImageGrid(imageItems)),
                ],
              ),
            ),
          ],
        ),

        bottomNavigationBar: SafeArea(
          child: Builder(
            builder: (context) => BottomTabs(
              controller: DefaultTabController.of(context),
              showCamera: true,
              onCreateFolder: (int index) {
                if (index == 3) _showCreateSubFolderDialog();
              },
              onCameraTap: _takePhoto,
              onUploadTap: () async {
                if (widget.isShared && widget.sharedFolderId != null) {
                  // 🔄 Upload shared folder photos
                  final dir = Directory(
                    '/storage/emulated/0/Pictures/MyApp/Shared/${widget.sharedFolderId}',
                  );

                  if (await dir.exists()) {
                    final imageFiles = <File>[];

                    for (var entity in dir.listSync(recursive: true)) {
                      if (entity is File && isMedia(entity.path)) {
                        imageFiles.add(entity);
                      }
                    }

                    print(
                      "📸 Found ${imageFiles.length} images: ${imageFiles.map((f) => f.path).toList()}",
                    );

                    if (imageFiles.isNotEmpty) {
                      final service = FolderShareService();
                      final success = await service.uploadToSharedFolder(
                        context,
                        widget.sharedFolderId!,
                        imageFiles,
                      );

                      if (success) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text("Shared folder uploaded"),
                          ),
                        );
                        _loadSharedPhotos(widget.sharedFolderId!);
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text("Upload failed")),
                        );
                      }
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text("No images found to upload"),
                        ),
                      );
                    }
                  }
                } else {
                  // 🔄 Upload personal photos
                  await PhotoService.uploadImagesToServer(context);
                  _loadItems();
                }
              },
              onUploadComplete: () {
                setState(() {
                  _loadItems(); // ✅ re-scan folders and update counts
                });
              },
            ),
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
                // IconButton(
                //   icon: const Icon(Icons.delete, color: Colors.redAccent),
                //   onPressed: () => _deleteFolder(folder),
                // ),
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

  Widget _buildImageGrid(List<File> files) {
    return ValueListenableBuilder<Set<String>>(
      valueListenable: PhotoService.uploadedFiles,
      builder: (context, uploadedSet, _) {
        return GridView.builder(
          padding: const EdgeInsets.all(8),
          itemCount: files.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            crossAxisSpacing: 4,
            mainAxisSpacing: 4,
          ),
          itemBuilder: (context, index) {
            final file = files[index];
            final isUploaded = uploadedSet.contains(file.path);
            final isSelected = selectedImages.contains(file.path);

            return GestureDetector(
              onLongPress: () {
                setState(() {
                  selectionMode = true;
                  selectedImages.add(file.path);
                });
              },
              onTap: () {
                if (selectionMode) {
                  setState(() {
                    if (isSelected) {
                      selectedImages.remove(file.path);
                    } else {
                      selectedImages.add(file.path);
                    }
                  });
                } else {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          GalleryScreen(images: files, startIndex: index),
                    ),
                  );
                }
              },
              child: Stack(
                children: [
                  Positioned.fill(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: isVideo(file.path)
                          ? Stack(
                              fit: StackFit.expand,
                              children: [
                                Container(color: Colors.black12),
                                const Center(
                                  child: Icon(
                                    Icons.videocam,
                                    color: Colors.white70,
                                    size: 40,
                                  ),
                                ),
                              ],
                            )
                          : Image.file(
                              file,
                              fit: BoxFit.cover,
                              cacheWidth: 300,
                              cacheHeight: 300,
                              errorBuilder: (_, __, ___) =>
                                  const Icon(Icons.broken_image),
                            ),
                    ),
                  ),
                  if (selectionMode)
                    Positioned(
                      top: 6,
                      left: 6,
                      child: Checkbox(
                        value: isSelected,
                        onChanged: (checked) {
                          setState(() {
                            if (checked == true) {
                              selectedImages.add(file.path);
                            } else {
                              selectedImages.remove(file.path);
                            }
                          });
                        },
                        activeColor: Colors.blue,
                        checkColor: Colors.white,
                      ),
                    ),
                  if (isUploaded)
                    Positioned(
                      right: 6,
                      top: 6,
                      child: Container(
                        decoration: const BoxDecoration(
                          color: Colors.green,
                          shape: BoxShape.circle,
                        ),
                        padding: const EdgeInsets.all(4),
                        child: const Icon(
                          Icons.check,
                          color: Colors.white,
                          size: 18,
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildApiImageGrid(List<Map<String, dynamic>> photos) {
    return ValueListenableBuilder<Set<String>>(
      valueListenable: PhotoService.uploadedFiles,
      builder: (context, uploadedSet, _) {
        // Filter newly taken photos to exclude uploaded ones
        final displayedPhotos = photos.where((p) {
          final filename = p['path'].split('/').last;
          return !uploadedSet.any((uploaded) => uploaded.endsWith(filename));
        }).toList();

        if (displayedPhotos.isEmpty) {
          return Center(
            child: Text(
              "No images yet in shared folder",
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          );
        }

        return GridView.builder(
          padding: const EdgeInsets.all(8),
          itemCount: displayedPhotos.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            crossAxisSpacing: 4,
            mainAxisSpacing: 4,
          ),
          itemBuilder: (context, index) {
            final photo = displayedPhotos[index];
            final isLocal = photo['local'] == true;
            final localPath = photo['path'];
            final serverPath =
                "http://192.168.1.4:8000/storage/${photo['path']}";
            final filename = localPath.split('/').last;
            final isUploaded = uploadedSet.any((p) => p.endsWith(filename));
            final isSelected = selectedImages.contains(localPath);

            return GestureDetector(
              onLongPress: () {
                setState(() {
                  selectionMode = true;
                  if (!selectedImages.contains(localPath)) {
                    selectedImages.add(localPath);
                  }
                });
              },
              onTap: () {
                if (selectionMode) {
                  setState(() {
                    if (isSelected) {
                      selectedImages.remove(localPath);
                    } else {
                      selectedImages.add(localPath);
                    }
                  });
                } else {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => GalleryScreen(
                        images: displayedPhotos
                            .map((p) => File(p['path']))
                            .toList(),
                        startIndex: index,
                      ),
                    ),
                  );
                }
              },
              child: Stack(
                children: [
                  Positioned.fill(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: isVideo(localPath)
                          ? Stack(
                              fit: StackFit.expand,
                              children: [
                                Container(color: Colors.black12),
                                const Center(
                                  child: Icon(
                                    Icons.videocam,
                                    color: Colors.white70,
                                    size: 40,
                                  ),
                                ),
                              ],
                            )
                          : (isLocal
                                ? Image.file(
                                    File(localPath),
                                    fit: BoxFit.cover,
                                    cacheWidth: 300,
                                    cacheHeight: 300,
                                    errorBuilder: (_, __, ___) =>
                                        const Icon(Icons.broken_image),
                                  )
                                : Image.network(
                                    serverPath,
                                    fit: BoxFit.cover,
                                    cacheWidth: 300,
                                    cacheHeight: 300,
                                    errorBuilder: (_, __, ___) =>
                                        const Icon(Icons.broken_image),
                                  )),
                    ),
                  ),
                  // Selection checkbox
                  if (selectionMode)
                    Positioned(
                      top: 6,
                      left: 6,
                      child: Checkbox(
                        value: isSelected,
                        onChanged: (checked) {
                          setState(() {
                            if (checked == true) {
                              selectedImages.add(localPath);
                            } else {
                              selectedImages.remove(localPath);
                            }
                          });
                        },
                        activeColor: Colors.blue,
                        checkColor: Colors.white,
                      ),
                    ),
                  // Uploaded tick
                  if (isUploaded)
                    Positioned(
                      right: 6,
                      top: 6,
                      child: Container(
                        decoration: const BoxDecoration(
                          color: Colors.green,
                          shape: BoxShape.circle,
                        ),
                        padding: const EdgeInsets.all(4),
                        child: const Icon(
                          Icons.check,
                          color: Colors.white,
                          size: 18,
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
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

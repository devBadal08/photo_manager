import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:path_provider/path_provider.dart';
import 'package:photomanager_practice/helpers/dialog_helpers.dart';
import 'package:photomanager_practice/screen/camera_screen.dart';
import 'package:photomanager_practice/screen/gallery_screen.dart';
import 'package:photomanager_practice/screen/pdf_viewer_screen.dart';
import 'package:photomanager_practice/screen/scan_screen.dart';
import 'package:photomanager_practice/services/auto_upload_service.dart';
import 'package:photomanager_practice/services/backup_service.dart';
import 'package:photomanager_practice/services/bottom_tabs.dart';
import 'package:photomanager_practice/services/folder_service.dart';
import 'package:photomanager_practice/services/folder_share_service.dart';
import 'package:photomanager_practice/services/folder_stat_service.dart';
import 'package:photomanager_practice/services/photo_service.dart';
import 'package:photomanager_practice/widgets/pdf_grid_cards.dart';
import 'package:photomanager_practice/widgets/pdf_list_cards.dart';
import 'package:photomanager_practice/widgets/shared_folder_list.dart';
import 'package:photomanager_practice/widgets/video_thumb_widget.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';
import 'package:video_thumbnail/video_thumbnail.dart' as vt;
import 'package:photomanager_practice/widgets/image_grid.dart';
import 'package:photomanager_practice/widgets/api_image_grid.dart';
import 'package:photomanager_practice/widgets/folder_list_cards.dart';
import 'package:photomanager_practice/screen/video_player_screen.dart';
import 'package:photomanager_practice/screen/video_network_player_screen.dart';
import 'package:file_picker/file_picker.dart';

class PhotoListScreen extends StatefulWidget {
  final Directory? folder;
  final int? sharedFolderId; // backend folder
  final String? sharedFolderName;
  final bool isShared;
  final String userId;
  final Directory? selectedFolder;
  final int? folderBackendId; // ✅ ADD THIS
  final bool canWrite;

  const PhotoListScreen({
    super.key,
    this.folder,
    this.sharedFolderId,
    this.sharedFolderName,
    this.isShared = false,
    required this.userId,
    this.selectedFolder,
    this.folderBackendId,
    this.canWrite = true,
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
  List<File> pdfFiles = [];
  List<Map<String, dynamic>> apiPhotos = [];
  List<Map<String, dynamic>> apiPdfFiles = [];
  bool isSearching = false;
  String searchQuery = '';
  List<Directory> filteredFolders = [];
  List<Map<String, dynamic>> _sharedPendingFiles = [];
  List<Map<String, dynamic>> apiFolders = [];
  bool _isImporting = false;
  int _importedCount = 0;
  int _totalImportCount = 0;
  final ValueNotifier<int> _importProgress = ValueNotifier(0);

  String get _mainFolderName => widget.isShared
      ? (widget.sharedFolderName?.split('/').last ?? "Shared Folder")
      : (widget.folder?.path.split('/').last ?? "Unnamed Folder");

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: 0);

    print(
      "🔍 isShared=${widget.isShared}, sharedFolderId=${widget.sharedFolderId}",
    );

    if (widget.isShared && widget.sharedFolderId != null) {
      _loadSharedPhotos(
        widget.sharedFolderId!,
        subfolderPath: widget.sharedFolderName,
      );
    } else {
      _loadItems(); // ✅ THIS WAS MISSING
    }

    _triggerAutoUploadIfEnabled();
  }

  Future<void> _pickImagesFromGallery() async {
    if (widget.folder == null) return;

    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.image,
    );

    if (result == null) return;

    _totalImportCount = result.files.length;
    _importedCount = 0;
    _isImporting = true;

    _showImportDialog();
    try {
      const int batchSize = 5;

      for (int i = 0; i < result.files.length; i += batchSize) {
        final batch = result.files.skip(i).take(batchSize).toList();

        final copiedFiles = <File>[];

        await Future.wait(
          batch.map((file) async {
            if (file.path == null) {
              return;
            }

            final sourceFile = File(file.path!);

            final targetPath = '${widget.folder!.path}/${file.name}';

            await sourceFile.openRead().pipe(File(targetPath).openWrite());

            copiedFiles.add(File(targetPath));

            _importedCount++;
            _importProgress.value = _importedCount;
          }),
        );

        if (mounted) {
          imageItems.addAll(copiedFiles);
          setState(() {});
        }
      }
    } finally {
      //ImportService.instance.finishImport();
    }

    if (mounted && Navigator.canPop(context)) {
      Navigator.pop(context);
    }

    _isImporting = false;
    _importedCount = 0;
    _importProgress.value = 0;
    _totalImportCount = 0;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${result.files.length} images imported successfully'),
      ),
    );
  }

  Future<void> _triggerAutoUploadIfEnabled() async {
    if (!AutoUploadService.instance.isEnabled) return;

    // Small delay so UI is ready
    await Future.delayed(const Duration(milliseconds: 300));

    if (!mounted) return;

    await AutoUploadService.instance.uploadNow();

    if (!widget.isShared) {
      _loadItems();
    }
  }

  List<dynamic> images = [];

  bool isMedia(String filePath) {
    final mediaExtensions = ['jpg', 'jpeg', 'png', 'mp4'];
    final extension = filePath.split('.').last.toLowerCase();
    return mediaExtensions.contains(extension);
  }

  bool isPdf(String path) {
    return path.toLowerCase().endsWith('.pdf');
  }

  bool isVideo(String filePath) {
    final videoExtensions = ['mp4'];
    final extension = filePath.split('.').last.toLowerCase();
    return videoExtensions.contains(extension);
  }

  void _addSharedPendingFile(String path) {
    final exists = _sharedPendingFiles.any((e) => e['path'] == path);
    if (!exists) {
      _sharedPendingFiles.add({"path": path, "local": true});
    }
  }

  void _showImportDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) {
        return AlertDialog(
          title: const Text("Importing Photos"),
          content: ValueListenableBuilder<int>(
            valueListenable: _importProgress,
            builder: (_, value, __) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 20),

                  Text("$value / $_totalImportCount"),

                  const SizedBox(height: 15),

                  LinearProgressIndicator(
                    value: _totalImportCount == 0
                        ? 0
                        : value / _totalImportCount,
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  Future<void> _loadSharedPhotos(int folderId, {String? subfolderPath}) async {
    setState(() {
      apiPhotos = [];
      apiPdfFiles = [];
      apiFolders = [];
    });

    final uploadedSet = PhotoService.uploadedFiles.value;

    final filteredNewPhotos = _sharedPendingFiles.where((p) {
      final name = p['path'].split('/').last.toLowerCase();
      return p['local'] == true &&
          !uploadedSet.any((u) => u.toLowerCase().endsWith(name));
    }).toList();

    final service = FolderShareService();
    final data = await service.getSharedFolderPhotos(folderId);

    // Declare list BEFORE using
    final imagesAndVideos = <Map<String, dynamic>>[];
    final pdfs = <Map<String, dynamic>>[];

    if (data != null && data['success'] == true) {
      // images & videos
      if (data['photos'] != null) {
        imagesAndVideos.addAll(
          List<Map<String, dynamic>>.from(
            data['photos'],
          ).map((p) => {"path": p['path'], "url": p['url'], "local": false}),
        );
      }

      // videos
      if (data['videos'] != null) {
        imagesAndVideos.addAll(
          List<Map<String, dynamic>>.from(data['videos']).map(
            (v) => {
              "path": v['path'],
              "url": v['url'],
              "local": false,
              "type": "video", // helpful later
            },
          ),
        );
      }

      // PDFs (backend should return "pdfs" or update endpoint)
      if (data['pdfs'] != null) {
        pdfs.addAll(
          List<Map<String, dynamic>>.from(
            data['pdfs'],
          ).map((p) => {"path": p['path'], "url": p['url'], "local": false}),
        );
      }

      // subfolders
      if (data['folders'] != null) {
        apiFolders = List<Map<String, dynamic>>.from(data['folders']).map((
          item,
        ) {
          return {
            'id': item['id'], // REAL folder id
            'name': item['name'],
            'path': item['path'], // FULL path from backend
            'access_type': item['access_type'],
          };
        }).toList();
      }
    }

    // Add new local photos (not uploaded yet)
    for (var photo in filteredNewPhotos) {
      final ext = photo['path'].split('.').last.toLowerCase();
      if (ext == 'pdf') {
        pdfs.add(photo);
      } else {
        imagesAndVideos.add(photo);
      }
    }

    // Remove duplicates (prefer local)
    final unique = <String, Map<String, dynamic>>{};
    for (var item in [...imagesAndVideos, ...pdfs]) {
      final filename = item['path'].split('/').last.toLowerCase();
      if (!unique.containsKey(filename) || item['local'] == true) {
        unique[filename] = item;
      }
    }

    // Re-split after unique filtering
    final finalImagesAndVideos = <Map<String, dynamic>>[];
    final finalPdfs = <Map<String, dynamic>>[];

    for (var item in unique.values) {
      final ext = item['path'].split('.').last.toLowerCase();
      if (ext == 'pdf') {
        finalPdfs.add(item);
      } else {
        finalImagesAndVideos.add(item);
      }
    }

    print("📂 sharedFolderId = $folderId");
    print("📂 subfolderPath = $subfolderPath");

    setState(() {
      apiPhotos = finalImagesAndVideos;
      apiPdfFiles = finalPdfs;
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

    final capturedPaths = await Navigator.push<List<String>>(
      context,
      MaterialPageRoute(
        builder: (_) => CameraScreen(
          saveFolder: widget.isShared ? null : widget.folder,
          sharedFolderId: widget.isShared ? widget.sharedFolderId : null,
          cameras: cameras,
        ),
      ),
    );

    if (capturedPaths != null && capturedPaths.isNotEmpty) {
      await Future.delayed(const Duration(milliseconds: 500));

      if (widget.isShared) {
        for (var path in capturedPaths) {
          if (!PhotoService.uploadedFiles.value.contains(path)) {
            _addSharedPendingFile(path);
          }
        }
        _loadSharedPhotos(widget.sharedFolderId!);
      } else {
        setState(() {
          final newFiles = capturedPaths.map((p) => File(p)).toList();
          imageItems.insertAll(0, newFiles); // insert at top
          items = [...folderItems, ...imageItems];
        });
      }
    }

    // Auto-upload if enabled
    if (AutoUploadService.instance.isEnabled) {
      await AutoUploadService.instance.uploadNow();
      if (!widget.isShared) _loadItems();
    }
  }

  Future<void> _loadItems() async {
    final folder = widget.folder;
    if (folder == null || !await folder.exists()) return;

    print("📂 Current Folder = ${folder.path}");

    final dirs = <Directory>[];
    final images = <File>[];
    final pdfs = <File>[];

    for (final entity in folder.listSync()) {
      print("➡ ${entity.path}");

      if (entity is Directory) {
        print("   DIR");
        dirs.add(entity);
      } else if (entity is File) {
        print("   FILE");

        final p = entity.path.toLowerCase();

        if (p.endsWith('.pdf')) {
          pdfs.add(entity);
        } else if (p.endsWith('.jpg') ||
            p.endsWith('.jpeg') ||
            p.endsWith('.png') ||
            p.endsWith('.mp4')) {
          print("   ✅ IMAGE FOUND");
          images.add(entity);
        }
      }
    }

    print("Images found = ${images.length}");

    if (!mounted) return;

    setState(() {
      folderItems = dirs;
      imageItems = images;
      pdfFiles = pdfs;
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
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Text(
              'Do not use: /  \\  :  *  ?  "  <  >  |',
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),
            SizedBox(height: 12),
            TextField(decoration: InputDecoration(hintText: 'New folder name')),
          ],
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

              // ✅ BLOCK invalid characters
              final invalidChars = RegExp(r'[\\/:*?"<>|]');
              if (invalidChars.hasMatch(newName)) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Folder name cannot contain: /  \\  :  *  ?  "  <  >  |',
                    ),
                  ),
                );
                return;
              }

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
                final folderId = await PhotoService.getFolderIdFromDisk(folder);

                print('🧪 PHOTO LIST RENAME DEBUG');
                print('➡️ Folder path = ${folder.path}');
                print('➡️ Folder name = ${folder.path.split('/').last}');
                print('➡️ Returned folderId = $folderId');

                // rename locally only AFTER server success
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
    final canDelete = await PhotoService.isFolderFullyUploadedLocally(folder);

    if (!canDelete) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Some photos are not uploaded yet. Upload first.'),
        ),
      );
      return;
    }

    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove from device'),
        content: const Text(
          'All photos are uploaded.\n'
          'This will remove the folder only from your phone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (shouldDelete != true) return;

    try {
      if (await folder.exists()) {
        await folder.delete(recursive: true);
      } else {
        debugPrint('⚠️ Folder already deleted: ${folder.path}');
      }
    } catch (e) {
      debugPrint('❌ Folder delete failed: $e');
    }

    _loadItems();
    countSubfoldersAndImages(widget.folder!.path);
  }

  Future<void> _shareSubFolder(Directory subfolder) async {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => Wrap(
        children: [
          // ======================= EMAIL SHARE =======================
          ListTile(
            leading: Icon(
              Icons.email,
              color: Theme.of(context).colorScheme.secondary,
            ),
            title: const Text("Share Subfolder via Email"),
            onTap: () async {
              Navigator.pop(ctx);

              final TextEditingController controller = TextEditingController();

              await showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Share Subfolder'),
                  content: TextField(
                    controller: controller,
                    decoration: const InputDecoration(
                      hintText: 'Enter user email',
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                    ElevatedButton(
                      onPressed: () async {
                        final email = controller.text.trim();

                        if (email.isEmpty || !email.contains("@")) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Invalid email')),
                          );
                          return;
                        }

                        final folderId = await FolderShareService.getFolderId(
                          folderName: subfolder.path.split('/').last,
                          parentId: widget.folderBackendId,
                        );

                        if (folderId == null) {
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'This subfolder hasn’t been uploaded yet. Upload it first.',
                              ),
                            ),
                          );
                          return;
                        }

                        final success = await FolderShareService()
                            .shareFolderByEmail(folderId, email);

                        if (!mounted) return;
                        Navigator.pop(context);

                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              success
                                  ? 'Subfolder shared successfully ✅'
                                  : 'Failed to share subfolder',
                            ),
                          ),
                        );
                      },
                      child: const Text('Share'),
                    ),
                  ],
                ),
              );
            },
          ),

          // ======================= WHATSAPP / BLUETOOTH SHARE =======================
          ListTile(
            leading: Icon(
              Icons.share,
              color: Theme.of(context).colorScheme.primary,
            ),
            title: const Text("Share via WhatsApp / Bluetooth"),
            onTap: () async {
              Navigator.pop(ctx); // close bottom sheet

              final files = subfolder
                  .listSync()
                  .whereType<File>()
                  .where(
                    (f) =>
                        f.path.endsWith(".jpg") ||
                        f.path.endsWith(".jpeg") ||
                        f.path.endsWith(".png"),
                  )
                  .map((f) => XFile(f.path))
                  .toList();

              if (files.isNotEmpty) {
                await Share.shareXFiles(
                  files,
                  text:
                      "📂 Sharing subfolder: ${subfolder.path.split('/').last}",
                );
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text("No images found in this subfolder"),
                  ),
                );
              }
            },
          ),
        ],
      ),
    );
  }

  Future<void> _showCreateSubFolderDialog() async {
    String folderName = '';

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Enter Subfolder Name'),

        // ✅ UPDATED CONTENT (Option 3 - minimal rule UI)
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Do not use: /  \\  :  *  ?  "  <  >  |',
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),

            const SizedBox(height: 12),

            TextField(
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'Enter subfolder name',
                border: UnderlineInputBorder(),
              ),
              onChanged: (value) => folderName = value.trim(),
            ),
          ],
        ),

        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),

          // ✅ UPDATED OK BUTTON
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

              // ✅ BLOCK these characters: / \ : * ? " < > |
              final invalidChars = RegExp(r'[\\/:*?"<>|]');
              if (invalidChars.hasMatch(folderName)) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Subfolder name cannot contain: /  \\  :  *  ?  "  <  >  |',
                    ),
                  ),
                );
                return;
              }

              Navigator.pop(context); // Close dialog
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

    final uploadedSet = PhotoService.uploadedFiles.value;

    // ✅ only allow deletion of uploaded images
    final uploadedImages = selectedImages
        .where((path) => uploadedSet.contains(path))
        .toList();

    final notUploadedImages = selectedImages
        .where((path) => !uploadedSet.contains(path))
        .toList();

    // ❌ nothing uploaded → block delete
    if (uploadedImages.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Please upload images before deleting them."),
        ),
      );
      return;
    }

    // confirmation message
    final confirm = await DialogHelpers.showConfirmDialog(
      context,
      title: "Delete Images",
      message: notUploadedImages.isEmpty
          ? "Delete ${uploadedImages.length} uploaded images?"
          : "Only ${uploadedImages.length} uploaded images will be deleted.\n"
                "${notUploadedImages.length} images are not uploaded yet.",
    );

    if (!confirm) return;

    // ✅ delete only uploaded images
    for (final path in uploadedImages) {
      try {
        final file = File(path);
        if (await file.exists()) {
          await file.delete();
        }
      } catch (e) {
        debugPrint("Delete failed for $path: $e");
      }
    }

    setState(() {
      selectedImages.clear();
      selectionMode = false;
    });

    await _loadItems();

    // info message if some were skipped
    if (notUploadedImages.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            "${notUploadedImages.length} images were not deleted because they are not uploaded yet.",
          ),
        ),
      );
    }
  }

  Future<void> _openScanScreen() async {
    final pdfFile = await Navigator.push<File?>(
      context,
      MaterialPageRoute(
        builder: (_) => ScanScreen(
          userId: widget.userId,
          saveFolder: widget.folder,
          folderName: widget.folder != null
              ? widget.folder!.path.split('/').last
              : '',
          sharedFolderId: widget.sharedFolderId, // pass shared folder ID if any
          onPdfCreated: (pdf) {
            if (widget.isShared) {
              _addSharedPendingFile(pdf.path);

              _loadSharedPhotos(widget.sharedFolderId!);
            } else {
              _loadItems();
            }

            setState(() {
              pdfFiles.insert(0, pdf);
            });
          },
        ),
      ),
    );

    if (pdfFile != null) {
      print("📄 Got PDF back in PhotoListScreen: ${pdfFile.path}");
    }
  }

  Future<void> _renamePdf(File pdfFile) async {
    if (!await pdfFile.exists()) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("PDF file not found")));
      return;
    }

    String currentName = pdfFile.path.split('/').last.replaceAll('.pdf', '');

    final result = await showDialog<String>(
      context: context,
      builder: (context) {
        final controller = TextEditingController(text: currentName);

        return AlertDialog(
          title: const Text('Rename PDF'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(hintText: 'Enter new PDF name'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, null),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                final input = controller.text.trim();
                if (input.isNotEmpty) Navigator.pop(context, input);
              },
              child: const Text('Rename'),
            ),
          ],
        );
      },
    );

    if (result == null) return;

    // ✅ BLOCK invalid characters
    final invalidChars = RegExp(r'[\\/:*?"<>|]');
    if (invalidChars.hasMatch(result)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('PDF name cannot contain: / \\ : * ? " < > |'),
        ),
      );
      return;
    }

    final newNameLower = result.toLowerCase().trim();
    final parentDir = pdfFile.parent;

    // ✅ Get all PDFs in same folder
    final existingPdfs = parentDir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.toLowerCase().endsWith('.pdf'))
        .toList();

    // ✅ Check for duplicate names
    for (final file in existingPdfs) {
      final existingName = file.path
          .split('/')
          .last
          .replaceAll('.pdf', '')
          .toLowerCase()
          .trim();

      if (existingName == newNameLower && file.path != pdfFile.path) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("A PDF with this name already exists in this folder"),
          ),
        );
        return;
      }
    }

    final newPath = '${parentDir.path}/$result.pdf';

    try {
      final oldPath = pdfFile.path;

      String serverPath = oldPath.replaceAll(RegExp(r'.*ScanVaultApp/'), '');

      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token');

      if (token != null) {
        final success = await PhotoService.renameFileOnServer(
          oldPath: serverPath,
          newName: result,
          token: token,
        );

        if (success) {
          // ✅ rename locally (correct way)
          await File(oldPath).rename(newPath);

          // ✅ update tracking
          PhotoService.uploadedFiles.value.remove(oldPath);
          PhotoService.uploadedFiles.value.add(newPath);

          await _loadItems();

          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('PDF renamed successfully')));
        }
      }
      print("🧠 OLD LOCAL PATH: $oldPath");
      print("🧠 SERVER PATH: $serverPath");
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to rename PDF: $e')));
    }
  }

  Future<void> _shareSelectedFiles() async {
    if (selectedImages.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("No files selected")));
      return;
    }

    final List<XFile> files = selectedImages.map((path) {
      if (path.startsWith("http")) {
        return XFile(path);
      } else {
        return XFile(File(path).path);
      }
    }).toList();

    await Share.shareXFiles(files, text: "📁 Shared from ${_mainFolderName}");

    setState(() {
      selectionMode = false;
      selectedImages.clear();
    });
  }

  void _toggleSelectAll() {
    setState(() {
      if (selectedSegment == 'Images') {
        final allItems = widget.isShared
            ? apiPhotos.map((e) => e['path'] as String).toList()
            : imageItems.map((e) => e.path).toList();

        if (selectedImages.length == allItems.length) {
          selectedImages.clear();
          selectionMode = false;
        } else {
          selectionMode = true;
          selectedImages = List.from(allItems);
        }
      }

      if (selectedSegment == 'PDF') {
        final allItems = widget.isShared
            ? apiPdfFiles.map((e) => e['path'] as String).toList()
            : pdfFiles.map((e) => e.path).toList();

        if (selectedImages.length == allItems.length) {
          selectedImages.clear();
          selectionMode = false;
        } else {
          selectionMode = true;
          selectedImages = List.from(allItems);
        }
      }
    });
  }

  bool get _isAllSelected {
    if (selectedSegment == 'Images') {
      final total = widget.isShared ? apiPhotos.length : imageItems.length;
      return total > 0 && selectedImages.length == total;
    }

    if (selectedSegment == 'PDF') {
      final total = widget.isShared ? apiPdfFiles.length : pdfFiles.length;
      return total > 0 && selectedImages.length == total;
    }

    return false;
  }

  @override
  Widget build(BuildContext context) {
    //final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return DefaultTabController(
      length: 5,
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
              IconButton(
                icon: Icon(
                  Icons.delete,
                  color: Theme.of(context).colorScheme.error,
                ),
                onPressed: _deleteSelectedImages,
              ),

            if (selectionMode)
              IconButton(
                icon: Icon(
                  Icons.share,
                  color: Theme.of(context).colorScheme.primary,
                ),
                onPressed: _shareSelectedFiles,
              ),

            if (selectionMode)
              IconButton(
                icon: const Icon(Icons.backup),
                onPressed: () async {
                  await BackupService.backupSelectedPhotos(
                    context,
                    selectedImages,
                  );

                  setState(() {
                    selectionMode = false;
                    selectedImages.clear();
                  });
                },
              ),

            PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'select_all') {
                  _toggleSelectAll();
                }
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'select_all',
                  child: Row(
                    children: [
                      Icon(_isAllSelected ? Icons.deselect : Icons.select_all),
                      const SizedBox(width: 10),
                      Text(_isAllSelected ? 'Deselect All' : 'Select All'),
                    ],
                  ),
                ),
              ],
            ),
          ],
          elevation: 4,
        ),

        body: Stack(
          children: [
            Column(
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
                    ButtonSegment<String>(
                      value: 'PDF',
                      label: Text('PDF'),
                      icon: Icon(Icons.picture_as_pdf),
                    ),
                  ],
                  selected: {selectedSegment},
                  onSelectionChanged: (Set<String> newSelection) {
                    setState(() {
                      selectedSegment = newSelection.first;
                    });
                    // Animate PageView when segment changes
                    _pageController.animateToPage(
                      selectedSegment == 'Folders'
                          ? 0
                          : selectedSegment == 'Images'
                          ? 1
                          : 2, // PDF page index
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
                        selectedSegment = index == 0
                            ? 'Folders'
                            : index == 1
                            ? 'Images'
                            : 'PDF';
                      });
                    },
                    children: [
                      // --- Folders Page ---
                      widget.isShared
                          ? SharedFolderList(
                              folders: apiFolders,
                              userId: widget.userId,
                              currentPath: widget.sharedFolderName,
                            )
                          : (folderItems.isEmpty
                                ? Center(
                                    child: Text(
                                      "No folders yet",
                                      style: textTheme.bodyMedium,
                                    ),
                                  )
                                : FolderListCards(
                                    folders: filteredFolders,
                                    userId: widget.userId,
                                    selectedFolder: widget.selectedFolder,
                                    folderBackendId: widget.folderBackendId,
                                    countFolderStats:
                                        FolderStatService.getFolderStats,
                                    onRename: _renameFolder,
                                    onDelete: _deleteFolder,
                                    onShare: _shareSubFolder,
                                  )),

                      // --- Images Page ---
                      widget.isShared
                          ? (apiPhotos.isEmpty
                                ? Center(
                                    child: Text(
                                      "No images yet in shared folder",
                                      style: textTheme.bodyMedium,
                                    ),
                                  )
                                : ApiImageGrid(
                                    photos: apiPhotos,
                                    uploadedSet:
                                        PhotoService.uploadedFiles.value,
                                    selectionMode: selectionMode,
                                    selectedImages: selectedImages,
                                    onToggleSelect: (path) {
                                      setState(() {
                                        if (selectedImages.contains(path)) {
                                          selectedImages.remove(path);
                                        } else {
                                          selectedImages.add(path);
                                        }
                                      });
                                    },
                                    sharedFolderId: widget.sharedFolderId,
                                  ))
                          : (imageItems.isEmpty
                                ? Center(
                                    child: Text(
                                      "No images yet",
                                      style: textTheme.bodyMedium,
                                    ),
                                  )
                                : ImageGrid(
                                    files: imageItems
                                        .where((f) => !isPdf(f.path))
                                        .toList(),
                                    selectionMode: selectionMode,
                                    selectedImages: selectedImages,
                                    uploadedSet: PhotoService.uploadedFiles,
                                    onToggleSelect: (path) {
                                      setState(() {
                                        if (selectedImages.contains(path)) {
                                          selectedImages.remove(path);
                                        } else {
                                          selectedImages.add(path);
                                        }

                                        if (selectedImages.isEmpty) {
                                          selectionMode = false; // ✅ auto-exit
                                        }
                                      });
                                    },
                                    onEnterSelectionMode: (path) {
                                      setState(() {
                                        selectionMode = true;
                                        selectedImages = [
                                          path,
                                        ]; // ✅ first selected item
                                      });
                                    },
                                  )),

                      // --- PDF Page ---
                      widget.isShared
                          ? (apiPdfFiles.isEmpty
                                ? Center(
                                    child: Text(
                                      "No PDFs yet in shared folder",
                                      style: textTheme.bodyMedium,
                                    ),
                                  )
                                : PDFGridCards(
                                    pdfFiles: apiPdfFiles,
                                    selectionMode: selectionMode,
                                    selectedImages: selectedImages,
                                    onSelectToggle: (path) {
                                      setState(() {
                                        if (selectedImages.contains(path)) {
                                          selectedImages.remove(path);
                                        } else {
                                          selectedImages.add(path);
                                        }
                                      });
                                    },
                                  ))
                          : PDFListCards(
                              pdfFiles: pdfFiles,
                              selectionMode: selectionMode,
                              selectedImages: selectedImages,
                              onSelectToggle: (path) {
                                setState(() {
                                  if (selectedImages.contains(path)) {
                                    selectedImages.remove(path);
                                  } else {
                                    selectedImages.add(path);
                                  }

                                  if (selectedImages.isEmpty) {
                                    selectionMode = false;
                                  }
                                });
                              },
                              onEnterSelectionMode: (path) {
                                setState(() {
                                  selectionMode = true;
                                  selectedImages = [path];
                                });
                              },
                              onRename: _renamePdf,
                            ),
                    ],
                  ),
                ),
              ],
            ),

            //const ImportProgressCard(),
          ],
        ),

        floatingActionButton: FloatingActionButton(
          onPressed: _pickImagesFromGallery,
          tooltip: 'Import Images',
          child: const Icon(Icons.photo_library),
        ),

        bottomNavigationBar: SafeArea(
          child: Builder(
            builder: (context) => BottomTabs(
              controller: DefaultTabController.of(context),
              userId: widget.userId, // or actual userId from prefs/auth
              folderName: widget.selectedFolder != null
                  ? widget.selectedFolder!.path.split('/').last
                  : (widget.folder != null
                        ? widget.folder!.path.split('/').last
                        : ""),
              showCamera: true,
              scanDisabled: false,
              onCreateFolder: (int index) {
                if (widget.isShared && !widget.canWrite) return;
                if (index == 4) _showCreateSubFolderDialog();
              },
              onCameraTap: widget.isShared && !widget.canWrite
                  ? null
                  : _takePhoto,
              onScanTap: () async {
                await _openScanScreen(); // call the async function, but closure itself is not async
              },
              onUploadTap: () async {
                // ================= SHARED FOLDER =================
                if (widget.isShared) {
                  if (!widget.canWrite) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          "You have read-only access to this folder",
                        ),
                      ),
                    );
                    return;
                  }

                  // ✅ Collect new local files created in shared folder
                  final imageFiles = <File>[];
                  final pdfFiles = <File>[];

                  for (final item in _sharedPendingFiles) {
                    final path = item['path'] as String;
                    final file = File(path);

                    if (!file.existsSync()) continue;

                    if (path.toLowerCase().endsWith('.pdf')) {
                      pdfFiles.add(file);
                    } else {
                      imageFiles.add(file);
                    }
                  }

                  if (imageFiles.isEmpty && pdfFiles.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text("No new files to upload")),
                    );
                    return;
                  }

                  // ✅ Upload to shared folder
                  final success = await FolderShareService()
                      .uploadToSharedFolder(
                        context,
                        widget.sharedFolderId!,
                        imageFiles,
                        pdfFiles,
                      );

                  if (success) {
                    _sharedPendingFiles.clear(); // ✅ important
                    await _loadSharedPhotos(widget.sharedFolderId!);
                  }

                  return;
                }

                // ================= PERSONAL FOLDER =================
                await PhotoService.uploadImagesToServer(null, context: context);

                _loadItems();
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
}

import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:photomanager_practice/helpers/dialog_helpers.dart';
import 'package:photomanager_practice/screen/camera_screen.dart';
import 'package:photomanager_practice/screen/gallery_screen.dart';
import 'package:photomanager_practice/screen/pdf_viewer_screen.dart';
import 'package:photomanager_practice/screen/scan_screen.dart';
import 'package:photomanager_practice/services/auto_upload_service.dart';
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
import 'package:video_player/video_player.dart';
import 'package:video_thumbnail/video_thumbnail.dart' as vt;
import 'package:photomanager_practice/widgets/image_grid.dart';
import 'package:photomanager_practice/widgets/api_image_grid.dart';
import 'package:photomanager_practice/widgets/folder_list_cards.dart';
import 'package:photomanager_practice/screen/video_player_screen.dart';
import 'package:photomanager_practice/screen/video_network_player_screen.dart';

class PhotoListScreen extends StatefulWidget {
  final Directory? folder;
  final int? sharedFolderId; // backend folder
  final String? sharedFolderName;
  final bool isShared;
  final String userId;
  final Directory? selectedFolder;
  final int? folderBackendId; // ✅ ADD THIS

  const PhotoListScreen({
    super.key,
    this.folder,
    this.sharedFolderId,
    this.sharedFolderName,
    this.isShared = false,
    required this.userId,
    this.selectedFolder,
    this.folderBackendId,
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
  List<Map<String, dynamic>> _newlyTakenPhotos = [];
  List<Map<String, dynamic>> apiFolders = [];

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

    if (widget.isShared) {
      if (widget.sharedFolderName != null &&
          widget.sharedFolderName!.contains('/')) {
        _loadSharedPhotos(
          widget.sharedFolderId ?? 0,
          subfolderPath: widget.sharedFolderName,
        );
      } else if (widget.sharedFolderId != null) {
        _loadSharedPhotos(widget.sharedFolderId!);
      }
    } else if (widget.folder != null) {
      _loadItems();
      countSubfoldersAndImages(widget.folder!.path);
    }

    _triggerAutoUploadIfEnabled();
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
    final mediaExtensions = ['jpg', 'jpeg', 'png', 'mp4', 'pdf'];
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

  Future<void> _loadSharedPhotos(int folderId, {String? subfolderPath}) async {
    final dir = Directory(
      '/storage/emulated/0/Pictures/MyApp/Shared/$folderId',
    );
    if (!await dir.exists()) await dir.create(recursive: true);

    final uploadedSet = PhotoService.uploadedFiles.value;

    final filteredNewPhotos = _newlyTakenPhotos.where((p) {
      return p['local'] == true && !uploadedSet.contains(p['path']);
    }).toList();

    final service = FolderShareService();
    final data = subfolderPath != null
        ? await service.getSharedFolderByPath(subfolderPath)
        : await service.getSharedFolderPhotos(folderId);

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
        apiFolders = List<Map<String, dynamic>>.from(data['folders']);
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
            _newlyTakenPhotos.add({"path": path, "local": true});
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

    final dirs = <Directory>[];
    final files = <File>[];

    await for (final entity in folder.list()) {
      if (entity is Directory) {
        final sub = entity.path.split('/').last;
        if (sub.toLowerCase() != _mainFolderName.toLowerCase()) {
          dirs.add(entity);
        }
      } else if (entity is File) {
        if (isMedia(entity.path) || isPdf(entity.path)) {
          files.add(entity);
        }
      }
      if (isPdf(entity.path)) {
        print("📘 Found PDF: ${entity.path}");
      }
    }

    dirs.sort((a, b) => b.statSync().changed.compareTo(a.statSync().changed));
    if (!mounted) return;

    setState(() {
      folderItems = dirs;
      imageItems = files; // now contains images + videos + PDFs
      pdfFiles = files.where((f) => isPdf(f.path)).toList();
      items = [...dirs, ...files];
      filteredFolders = List.from(dirs);
      print("📑 Found PDFs: ${pdfFiles.map((f) => f.path).toList()}");
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

                if (folderId != null) {
                  final success = await FolderService().renameFolderOnServer(
                    folderId: folderId,
                    newName: newName,
                  );

                  if (!success) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Server rename failed')),
                    );
                    return;
                  }

                  await FolderService.updateFolderMetaName(folderId, newName);
                }

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
    final shouldDelete = await DialogHelpers.showConfirmDialog(
      context,
      title: "Delete Folder",
      message: "Are you sure you want to delete this folder?",
    );

    if (!mounted || !shouldDelete) return;

    try {
      await folder.delete(recursive: true);
      _loadItems();
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error deleting folder: $e')));
    }
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
          saveFolder: widget.folder,
          userId: widget.userId,
          folderName: widget.folder != null
              ? widget.folder!.path.split('/').last
              : '',
          sharedFolderId: widget.sharedFolderId, // pass shared folder ID if any
          onPdfCreated: (pdf) {
            // Refresh UI depending on folder type
            if (widget.sharedFolderId != null) {
              _loadSharedPhotos(widget.sharedFolderId!);
            } else {
              _loadItems();
            }

            // Optionally insert PDF locally for immediate view
            setState(() {
              imageItems.insert(0, pdf);
              pdfFiles.insert(0, pdf);
              items = [...folderItems, ...imageItems];
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
      await pdfFile.rename(newPath);

      if (widget.isShared) {
        _loadSharedPhotos(widget.sharedFolderId!);
      } else {
        await _loadItems();
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('PDF renamed to $result.pdf')));
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
                  child: Text('Select Files to Share'),
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
                                uploadedSet: PhotoService.uploadedFiles.value,
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
                if (index == 4) _showCreateSubFolderDialog();
              },
              onCameraTap: _takePhoto,
              onScanTap: () async {
                await _openScanScreen(); // call the async function, but closure itself is not async
              },
              onUploadTap: () async {
                if (widget.isShared && widget.sharedFolderId != null) {
                  final dir = Directory(
                    '/storage/emulated/0/Pictures/MyApp/${widget.sharedFolderId}',
                  );

                  if (!await dir.exists()) return;

                  final uploadImages = <File>[];
                  final uploadPdfs = <File>[];

                  for (var entity in dir.listSync(recursive: true)) {
                    if (entity is File) {
                      if (isMedia(entity.path)) {
                        uploadImages.add(entity);
                      } else if (isPdf(entity.path)) {
                        uploadPdfs.add(entity);
                      }
                    }
                  }

                  if (uploadImages.isEmpty && uploadPdfs.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text("No images or PDFs found to upload"),
                      ),
                    );
                    return;
                  }

                  final service = FolderShareService();
                  final success = await service.uploadToSharedFolder(
                    context,
                    widget.sharedFolderId!,
                    uploadImages, // only images
                    uploadPdfs, // only PDFs
                  );

                  if (success) {
                    for (var file in [...uploadImages, ...uploadPdfs]) {
                      final index = _newlyTakenPhotos.indexWhere(
                        (p) => p['path'] == file.path,
                      );
                      if (index != -1)
                        _newlyTakenPhotos[index]['local'] = false;
                    }

                    await _loadSharedPhotos(widget.sharedFolderId!);
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text("Upload failed")),
                    );
                  }
                } else {
                  // Personal folder upload
                  await PhotoService.uploadImagesToServer(
                    null,
                    context: context,
                  );
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
}

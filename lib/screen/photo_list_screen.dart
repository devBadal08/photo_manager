import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:photomanager_practice/screen/camera_screen.dart';
import 'package:photomanager_practice/screen/gallery_screen.dart';
import 'package:photomanager_practice/screen/pdf_viewer_screen.dart';
import 'package:photomanager_practice/screen/scan_screen.dart';
import 'package:photomanager_practice/services/auto_upload_service.dart';
import 'package:photomanager_practice/services/bottom_tabs.dart';
import 'package:photomanager_practice/services/folder_share_service.dart';
import 'package:photomanager_practice/services/photo_service.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';
import 'package:video_thumbnail/video_thumbnail.dart' as vt;

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

    // Get uploaded files set
    final uploadedSet = PhotoService.uploadedFiles.value;

    // Filter newly taken photos: keep all local photos that are not yet uploaded
    final filteredNewPhotos = _newlyTakenPhotos.where((p) {
      return p['local'] == true && !uploadedSet.contains(p['path']);
    }).toList();

    // Server photos
    final service = FolderShareService();
    final data = subfolderPath != null
        ? await service.getSharedFolderByPath(subfolderPath)
        : await service.getSharedFolderPhotos(folderId);

    List<Map<String, dynamic>> serverPhotos = [];
    if (data != null && data['success'] == true) {
      // ✅ MAIN FOLDER FILES
      if (data['photos'] != null) {
        serverPhotos = List<Map<String, dynamic>>.from(data['photos'])
            .map((p) => {"path": p['path'], "url": p['url'], "local": false})
            .toList();
      }

      // ✅ SUBFOLDERS
      if (data['folders'] != null) {
        apiFolders = List<Map<String, dynamic>>.from(data['folders']);
      }
      print("📁 Shared subfolders: ${apiFolders.length}");
    }

    // Merge newly taken + server photos
    final allPhotos = [...filteredNewPhotos, ...serverPhotos];

    // Deduplicate by filename to avoid duplicates, prefer local
    final uniquePhotos = <String, Map<String, dynamic>>{};
    for (var photo in allPhotos) {
      final filename = photo['path'].split('/').last.toLowerCase();
      if (!uniquePhotos.containsKey(filename) || photo['local'] == true) {
        uniquePhotos[filename] = photo;
      }
    }

    // Split into apiPhotos (images/videos) and apiPdfFiles (pdfs)
    final tempList = uniquePhotos.values.toList();
    final imagesAndVideos = <Map<String, dynamic>>[];
    final pdfs = <Map<String, dynamic>>[];

    for (var p in tempList) {
      final path = p['path'] as String;
      final ext = path.split('.').last.toLowerCase();
      if (ext == 'pdf') {
        pdfs.add(p);
      } else {
        imagesAndVideos.add(p);
      }
    }

    setState(() {
      apiPhotos = imagesAndVideos;
      apiPdfFiles = pdfs;
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

  Widget _buildPdfListCards(List<File> pdfFiles) {
    if (pdfFiles.isEmpty) {
      return const Center(
        child: Text("No PDFs yet", style: TextStyle(color: Colors.white70)),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: pdfFiles.length,
      itemBuilder: (context, index) {
        final pdfFile = pdfFiles[index];
        final pdfName = pdfFile.path.split('/').last;

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
            leading: const Icon(
              Icons.picture_as_pdf,
              size: 40,
              color: Colors.redAccent,
            ),
            title: Text(
              pdfName,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            trailing: IconButton(
              icon: const Icon(Icons.edit_note, color: Colors.blueAccent),
              onPressed: () => _renamePdf(pdfFile),
            ),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => PdfViewerScreen(pdfFile: pdfFile),
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildPdfGridCards(List<dynamic> pdfFiles) {
    if (pdfFiles.isEmpty) {
      return const Center(
        child: Text("No PDFs found", style: TextStyle(color: Colors.white70)),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: pdfFiles.length,
      itemBuilder: (context, index) {
        final pdf = pdfFiles[index];
        final pdfName = pdf is File
            ? pdf.path.split('/').last
            : pdf['name'] ?? pdf['path'].split('/').last;
        final pdfPath = pdf is File ? pdf.path : pdf['url'] ?? pdf['path'];

        // Detect whether it's a shared (server) PDF or a local file
        final bool isShared =
            pdf is Map &&
            ((pdf['url'] != null &&
                    (pdf['url'] as String).startsWith('http')) ||
                !(pdfPath.toString().startsWith('/storage')));

        // Build correct URL if shared
        final String? pdfUrl = isShared
            ? (pdf['url'] ?? "http://192.168.1.13:8000/storage/${pdf['path']}")
            : null;

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
            leading: const Icon(
              Icons.picture_as_pdf,
              size: 40,
              color: Colors.redAccent,
            ),
            title: Text(
              pdfName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.edit_note, color: Colors.blueAccent),
                  onPressed: pdf is File ? () => _renamePdf(pdf) : null,
                ),
              ],
            ),
            onTap: () {
              print("📄 Opening PDF: $pdfName");
              print("🧠 isShared=$isShared | pdfPath=$pdfPath");

              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => PdfViewerScreen(
                    pdfFile: isShared ? pdfUrl! : File(pdfPath),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
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
            leading: const Icon(Icons.email, color: Colors.blue),
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
            leading: const Icon(Icons.share, color: Colors.green),
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
                icon: const Icon(Icons.delete, color: Colors.red),
                onPressed: _deleteSelectedImages,
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
                      ? _buildSharedFolders()
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
                            : _buildImageGrid(
                                imageItems
                                    .where((f) => !isPdf(f.path))
                                    .toList(),
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
                            : _buildPdfGridCards(apiPdfFiles))
                      : _buildPdfListCards(pdfFiles),
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

  Widget _buildApiImageGrid(List<Map<String, dynamic>> photos) {
    print("🔍 Initial photos received: ${photos.length}");
    return ValueListenableBuilder<Set<String>>(
      valueListenable: PhotoService.uploadedFiles,
      builder: (context, uploadedSet, _) {
        print("📦 Uploaded files (count: ${uploadedSet.length})");
        // Step 1: Remove uploaded photos
        final filteredPhotos = photos.where((p) {
          final filename = p['path'].split('/').last.toLowerCase();
          return !uploadedSet.any(
            (uploaded) => uploaded.toLowerCase().endsWith(filename),
          );
        }).toList();

        // Step 2: Remove duplicate filenames, prefer local copies
        final Map<String, Map<String, dynamic>> uniquePhotos = {};
        for (var p in filteredPhotos) {
          final filename = p['path'].split('/').last.toLowerCase();
          if (!uniquePhotos.containsKey(filename) || p['local'] == true) {
            uniquePhotos[filename] = p;
          }
        }

        final displayedPhotos = uniquePhotos.values.toList();

        if (displayedPhotos.isEmpty) {
          return Center(
            child: Text(
              "No files yet in shared folder",
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
                "http://192.168.1.13:8000/storage/${photo['path']}";
            final filename = localPath.split('/').last;
            final isUploaded = uploadedSet.any((p) => p.endsWith(filename));
            final isSelected = selectedImages.contains(localPath);

            // Detect file type
            final ext = localPath.split('.').last.toLowerCase();
            final isPdf = ext == 'pdf';
            final isVideoFile = isVideo(localPath);

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
                print("👆 Tapped: $filename | selectionMode: $selectionMode");
                if (selectionMode) {
                  setState(() {
                    if (isSelected) {
                      selectedImages.remove(localPath);
                    } else {
                      selectedImages.add(localPath);
                    }
                  });
                } else {
                  if (isPdf) {
                    final isShared = widget.sharedFolderId != null;
                    final fileName = localPath.split('/').last;
                    print(
                      "📄 Opening PDF -> Shared: $isShared | File: $fileName",
                    );

                    if (isShared) {
                      // 🟩 OPEN PDF DIRECTLY FROM SERVER (not local)
                      final pdfUrl =
                          "http://192.168.1.13:8000/storage/${photo['path']}";
                      print("🌐 Opening shared PDF from server: $pdfUrl");

                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => PdfViewerScreen(
                            pdfFile: pdfUrl,
                            sharedFolderId: widget.sharedFolderId,
                          ),
                        ),
                      );

                      // You’ll modify PdfViewerScreen to accept URLs (next step)
                    } else {
                      final fullPath =
                          '/storage/emulated/0/Pictures/MyApp/${widget.userId}/${widget.folder}/$fileName';
                      final exists = File(fullPath).existsSync();
                      print("📂 Local PDF path: $fullPath | Exists: $exists");

                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => PdfViewerScreen(
                            pdfFile: File(fullPath),
                            sharedFolderId: widget.sharedFolderId,
                          ),
                        ),
                      );
                    }
                  } else if (isVideoFile) {
                    if (isLocal) {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              VideoPlayerScreen(videoFile: File(localPath)),
                        ),
                      );
                    } else {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              VideoNetworkPlayerScreen(videoUrl: serverPath),
                        ),
                      );
                    }
                  } else {
                    final galleryItems = displayedPhotos.map<dynamic>((p) {
                      if (p['local'] == true) {
                        return File(p['path']); // local image / video / pdf
                      } else {
                        return "http://192.168.1.13:8000/storage/${p['path']}"; // server
                      }
                    }).toList();

                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => GalleryScreen(
                          images: galleryItems,
                          startIndex: galleryItems.indexWhere((item) {
                            final itemPath = item is File
                                ? item.path
                                : item.toString();
                            return itemPath.endsWith(
                              photo['path'].split('/').last,
                            );
                          }),
                        ),
                      ),
                    );
                  }
                }
              },
              child: Stack(
                children: [
                  Positioned.fill(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: isPdf
                          ? Container(
                              color: Colors.grey[200],
                              child: const Center(
                                child: Icon(
                                  Icons.picture_as_pdf,
                                  size: 40,
                                  color: Colors.red,
                                ),
                              ),
                            )
                          : isVideoFile
                          ? (isLocal
                                ? VideoThumbWidget(videoPath: localPath)
                                // ✅ SERVER VIDEO → NO Image.network → show custom video thumbnail box
                                : Stack(
                                    fit: StackFit.expand,
                                    children: [
                                      Container(color: Colors.black54),

                                      const Center(
                                        child: Icon(
                                          Icons.play_circle_fill,
                                          size: 50,
                                          color: Colors.white,
                                        ),
                                      ),

                                      Positioned(
                                        bottom: 6,
                                        right: 6,
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 6,
                                            vertical: 3,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.black.withOpacity(
                                              0.7,
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              6,
                                            ),
                                          ),
                                          child: const Text(
                                            "VIDEO",
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ))
                          : (isLocal
                                ? Image.file(File(localPath), fit: BoxFit.cover)
                                : Image.network(serverPath, fit: BoxFit.cover)),
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
                  // PDF rename button
                  if (isPdf && isLocal) // ✅ only local PDFs can be renamed
                    Positioned(
                      right: 6,
                      bottom: 6,
                      child: GestureDetector(
                        onTap: () => _renamePdf(File(localPath)),
                        child: Container(
                          decoration: const BoxDecoration(
                            color: Colors.blueAccent,
                            shape: BoxShape.circle,
                          ),
                          padding: const EdgeInsets.all(4),
                          child: const Icon(
                            Icons.edit_note,
                            color: Colors.white,
                            size: 18,
                          ),
                        ),
                      ),
                    ),

                  // Optional: show lock icon for shared
                  if (isPdf && !isLocal)
                    Positioned(
                      right: 6,
                      bottom: 6,
                      child: Container(
                        decoration: const BoxDecoration(
                          color: Colors.black54,
                          shape: BoxShape.circle,
                        ),
                        padding: const EdgeInsets.all(4),
                        child: const Icon(
                          Icons.lock,
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
            final extension = file.path.split('.').last.toLowerCase();

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
                  if (extension == 'pdf') {
                    // Open PDF
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => PdfViewerScreen(pdfFile: file),
                      ),
                    );
                  } else {
                    // Open image/video in gallery
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            GalleryScreen(images: files, startIndex: index),
                      ),
                    );
                  }
                }
              },
              child: Stack(
                children: [
                  Positioned.fill(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: isVideo(file.path)
                          ? VideoThumbWidget(videoPath: file.path)
                          : extension == 'pdf'
                          ? Container(
                              color: Colors.grey[200],
                              child: const Center(
                                child: Icon(
                                  Icons.picture_as_pdf,
                                  size: 40,
                                  color: Colors.red,
                                ),
                              ),
                            )
                          : Image.file(
                              file,
                              fit: BoxFit.cover,
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
                  // PDF rename button
                  if (extension == 'pdf')
                    Positioned(
                      right: 6,
                      bottom: 6,
                      child: GestureDetector(
                        onTap: () => _renamePdf(file),
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.blueAccent,
                            shape: BoxShape.circle,
                          ),
                          padding: const EdgeInsets.all(4),
                          child: const Icon(
                            Icons.edit_note,
                            color: Colors.white,
                            size: 18,
                          ),
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
                final videoCount = snapshot.data?['videos'] ?? 0;
                final pdfCount = snapshot.data?['pdfs'] ?? 0;

                return Text(
                  'Subfolders: $subfolderCount\n'
                  'Images: $imageCount   Videos: $videoCount   PDFs: $pdfCount',
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
                if (!widget.isShared)
                  IconButton(
                    icon: const Icon(Icons.share, color: Colors.green),
                    onPressed: () => _shareSubFolder(folder),
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
                  builder: (_) => PhotoListScreen(
                    folder: folder,
                    userId: widget.userId,
                    selectedFolder: widget.selectedFolder,
                    folderBackendId: widget.folderBackendId,
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  Future<Map<String, int>> _countSingleFolder(Directory folder) async {
    int subfolderCount = 0;
    int imageCount = 0;
    int videoCount = 0;
    int pdfCount = 0;

    final List<FileSystemEntity> entities = folder.listSync();

    for (FileSystemEntity entity in entities) {
      if (entity is Directory) {
        subfolderCount++;

        final subEntities = entity.listSync();
        for (FileSystemEntity sub in subEntities) {
          if (sub is File) {
            final path = sub.path.toLowerCase();

            if (path.endsWith('.jpg') ||
                path.endsWith('.jpeg') ||
                path.endsWith('.png')) {
              imageCount++;
            } else if (path.endsWith('.mp4')) {
              videoCount++;
            } else if (path.endsWith('.pdf')) {
              pdfCount++;
            }
          }
        }
      } else if (entity is File) {
        final path = entity.path.toLowerCase();

        if (path.endsWith('.jpg') ||
            path.endsWith('.jpeg') ||
            path.endsWith('.png')) {
          imageCount++;
        } else if (path.endsWith('.mp4')) {
          videoCount++;
        } else if (path.endsWith('.pdf')) {
          pdfCount++;
        }
      }
    }

    return {
      'subfolders': subfolderCount,
      'images': imageCount,
      'videos': videoCount,
      'pdfs': pdfCount,
    };
  }

  Widget _buildSharedFolders() {
    if (apiFolders.isEmpty) {
      return const Center(
        child: Text(
          "No shared subfolders found",
          style: TextStyle(color: Colors.white70),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: apiFolders.length,
      itemBuilder: (context, index) {
        final folder = apiFolders[index];

        final folderName = folder['name'] ?? 'Unnamed';

        final subfolderCount = folder['subfolders_count'] ?? 0;
        final imageCount = folder['images_count'] ?? 0;
        final videoCount = folder['videos_count'] ?? 0;
        final pdfCount = folder['pdfs_count'] ?? 0;

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

            // ❌ removed trailing icons
            leading: const Icon(Icons.folder, size: 40, color: Colors.orange),

            title: Text(
              folderName,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),

            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => PhotoListScreen(
                    isShared: true,
                    sharedFolderId: folder['id'], // ✅ IMPORTANT
                    sharedFolderName: folder['path'], // ✅ optional
                    userId: widget.userId,
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class VideoThumbWidget extends StatelessWidget {
  final String videoPath;

  const VideoThumbWidget({super.key, required this.videoPath});

  Future<Uint8List?> _getThumb() async {
    return await vt.VideoThumbnail.thumbnailData(
      video: videoPath,
      imageFormat: vt.ImageFormat.JPEG,
      maxWidth: 300,
      quality: 65,
    );
  }

  Future<String> _getDuration() async {
    VideoPlayerController controller;

    if (videoPath.startsWith('http')) {
      controller = VideoPlayerController.network(videoPath);
    } else {
      controller = VideoPlayerController.file(File(videoPath));
    }

    await controller.initialize();
    final duration = controller.value.duration;
    controller.dispose();

    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');

    if (duration.inHours > 0) {
      return "${duration.inHours.toString().padLeft(2, '0')}:$minutes:$seconds";
    }

    return "$minutes:$seconds";
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: Future.wait([_getThumb(), _getDuration()]),
      builder: (context, AsyncSnapshot<List<dynamic>> snap) {
        if (!snap.hasData) {
          return Container(color: Colors.black26);
        }

        final Uint8List imageData = snap.data![0];
        final String duration = snap.data![1];

        return Stack(
          fit: StackFit.expand,
          children: [
            // Thumbnail image
            Image.memory(imageData, fit: BoxFit.cover),

            // Play icon
            const Center(
              child: Icon(
                Icons.play_circle_fill,
                color: Colors.white,
                size: 40,
              ),
            ),

            // ⏱ Duration Badge
            Positioned(
              bottom: 6,
              right: 6,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.75),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  duration,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class VideoNetworkPlayerScreen extends StatefulWidget {
  final String videoUrl;
  const VideoNetworkPlayerScreen({super.key, required this.videoUrl});

  @override
  State<VideoNetworkPlayerScreen> createState() =>
      _VideoNetworkPlayerScreenState();
}

class _VideoNetworkPlayerScreenState extends State<VideoNetworkPlayerScreen> {
  late VideoPlayerController _controller;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.network(widget.videoUrl)
      ..initialize().then((_) {
        setState(() {});
        _controller.play();
      });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Video")),
      body: Center(
        child: _controller.value.isInitialized
            ? AspectRatio(
                aspectRatio: _controller.value.aspectRatio,
                child: VideoPlayer(_controller),
              )
            : const CircularProgressIndicator(),
      ),
    );
  }
}

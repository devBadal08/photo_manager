import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:http/http.dart' as http;
import 'package:photomanager_practice/screen/scan_screen.dart';
import 'package:photomanager_practice/services/bottom_tabs.dart';
import 'package:photomanager_practice/services/folder_share_service.dart';
import 'package:photomanager_practice/widgets/custom_drawer.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'photo_list_screen.dart';
import 'package:photomanager_practice/services/folder_service.dart';

class FolderScreen extends StatefulWidget {
  final String userId;
  const FolderScreen({super.key, required this.userId});

  @override
  State<FolderScreen> createState() => _FolderScreenState();
}

class _FolderScreenState extends State<FolderScreen>
    with SingleTickerProviderStateMixin {
  List<Directory> folders = [];
  String searchQuery = '';
  List<Directory> filteredFolders = []; // filtered list
  bool isSearching = false; // toggle search
  late TabController _tabController;
  bool isAutoUploadEnabled = false;
  bool isUploading = false;
  String userName = '';
  File? _avatarImage;
  int folderCount = 0;
  int imageCount = 0;
  int totalImages = 0;
  int videoCount = 0;
  int pdfCount = 0;
  bool isStorageNearLimit = false;
  String storageMessage = '';
  double percentUsed = 0.0;
  String appBarTitle = "Folders";

  // late final StreamSubscription _statusCheckSub;
  Directory? selectedFolder;

  final FolderService folderService = FolderService();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
    _loadInitialData();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkCompanyStorageUsage();
    });
  }

  Future<void> _loadInitialData() async {
    await _loadFolders();
    await _loadUserName();
    await _loadAvatar();
    await _countFoldersAndImages();
    await _loadSelectedCompanyName();
  }

  @override
  void dispose() {
    _tabController.dispose();
    //_statusCheckSub.cancel();
    super.dispose();
  }

  Future<void> _loadSelectedCompanyName() async {
    final prefs = await SharedPreferences.getInstance();
    final companiesJson = prefs.getString("companies");
    final selectedId = prefs.getInt("selected_company_id");

    if (companiesJson == null || selectedId == null) return;

    final list = List<Map<String, dynamic>>.from(jsonDecode(companiesJson));

    final selectedCompany = list.firstWhere(
      (c) => c["id"] == selectedId,
      orElse: () => {},
    );

    if (!mounted) return;
    setState(() {
      appBarTitle = selectedCompany["company_name"] ?? "Folders";
    });
  }

  Future<void> _loadUserName() async {
    final name = await folderService.loadUserName();
    if (!mounted) return;
    setState(() {
      userName = name;
    });
  }

  Future<void> _loadAvatar() async {
    final avatar = await folderService.loadAvatar();
    if (!mounted) return;
    setState(() {
      _avatarImage = avatar;
    });
  }

  Future<void> _countFoldersAndImages() async {
    final result = await folderService.countFoldersImagesVideos();
    if (!mounted) return;
    setState(() {
      folderCount = result['folders'] ?? 0;
      imageCount = result['images'] ?? 0;
      totalImages = imageCount; // keep your old variable if used elsewhere
      videoCount = result['videos'] ?? 0;
      pdfCount = result['pdfs'] ?? 0;
    });
  }

  Future<void> _checkCompanyStorageUsage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final companyId = prefs.getInt("selected_company_id");

      if (companyId == null) {
        debugPrint("❌ No selected_company_id found");
        return;
      }

      final url = Uri.parse(
        'https://techstrota.cloud/api/storage-usage?company_id=$companyId',
      );

      final token = await folderService.getAuthToken();
      if (token == null || token.isEmpty) return;

      final response = await http.get(
        url,
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        final usedPercent = (data['percent_used'] ?? 0).toDouble();
        final usedMB = (data['used_storage_mb'] ?? 0).toDouble();
        final maxMB = (data['max_storage_mb'] ?? 0).toDouble();

        if (!mounted) return;

        setState(() {
          percentUsed = usedPercent;
          isStorageNearLimit = percentUsed >= 85;
          storageMessage = percentUsed >= 98.5
              ? "Storage full! Please contact admin."
              : percentUsed >= 85
              ? "Warning: You are close to your storage limit!"
              : "";
        });

        debugPrint(
          "Used: $usedMB MB / $maxMB MB (${percentUsed.toStringAsFixed(2)}%)",
        );
      } else {
        debugPrint(
          "Storage check failed: ${response.statusCode} → ${response.body}",
        );
      }
    } catch (e) {
      debugPrint("❌ Error checking storage: $e");
    }
  }

  Future<void> _loadFolders() async {
    final result = await folderService.loadFolders();

    // Sort folders by creation (or last modified) time descending
    result.sort((a, b) {
      final aStat = a.statSync();
      final bStat = b.statSync();
      return bStat.changed.compareTo(aStat.changed); // latest first
    });

    if (!mounted) return;
    setState(() {
      folders = result;
      filteredFolders = result;
    });
  }

  void _filterFolders(String query) {
    final lowerQuery = query.toLowerCase();
    setState(() {
      searchQuery = query;
      filteredFolders = folders.where((folder) {
        final folderName = folder.path.split('/').last.toLowerCase();
        return folderName.contains(lowerQuery);
      }).toList();
    });
  }

  void _showCustomDrawer(BuildContext context) {
    final parentCtx = context; // store FolderScreen's context
    showDialog(
      context: context,
      barrierColor: Colors.black54,
      builder: (dialogContext) {
        return CustomDrawer(
          userName: userName,
          avatarImage: _avatarImage,
          parentContext: parentCtx, // ✅ now real FolderScreen context
          onDelete: () async {
            await _loadFolders();
            await _countFoldersAndImages();
          },
        );
      },
    );
  }

  Future<void> _showCreateFolderDialog(BuildContext context) async {
    String folderName = '';

    await showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Create Folder'),
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
                hintText: "Enter folder name",
                border: UnderlineInputBorder(),
              ),
              onChanged: (value) => folderName = value.trim(),
            ),
          ],
        ),

        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
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

              // ✅ BLOCK / \ : * ? " < > |
              final invalidChars = RegExp(r'[\\/:*?"<>|]');
              if (invalidChars.hasMatch(folderName)) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Folder name cannot contain: /  \\  :  *  ?  "  <  >  |',
                    ),
                  ),
                );
                return;
              }

              Navigator.of(dialogContext).pop(); // Close first dialog
              final created = await folderService.createFolder(folderName);

              if (!mounted) return;

              if (created) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Folder created successfully')),
                );
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Folder already exists')),
                );
              }

              _loadFolders();
              _countFoldersAndImages();
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showCameraDisabledMessage() {
    folderService.showCameraDisabledMessage(context);
  }

  void _showScanDisabledMessage() {
    folderService.showScanDisabledMessage(context);
  }

  Future<void> _renameFolder(Directory folder) async {
    final TextEditingController controller = TextEditingController(
      text: folder.path.split('/').last,
    );

    await showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Rename Folder'),

        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Do not use: /  \\  :  *  ?  "  <  >  |',
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: controller,
              decoration: const InputDecoration(hintText: 'New folder name'),
            ),
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
              Navigator.pop(dialogContext); // ✅ close dialog safely

              if (!mounted) return;

              if (newName.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Folder name cannot be empty')),
                );
                return;
              }

              final invalidChars = RegExp(r'[\\/:*?"<>|]');
              if (invalidChars.hasMatch(newName)) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Invalid characters in folder name'),
                  ),
                );
                return;
              }

              final newPath = '${folder.parent.path}/$newName';
              final newDir = Directory(newPath);

              if (await newDir.exists()) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Folder already exists')),
                );
                return;
              }

              final folderId = await FolderService.getFolderIdFromDisk(folder);

              print('🧪 FOLDER SCREEN RENAME DEBUG');
              print('➡️ Folder path = ${folder.path}');
              print('➡️ Folder name = ${folder.path.split('/').last}');
              print('➡️ Returned folderId = $folderId');

              if (folderId == null) {
                // ✅ LOCAL-ONLY FOLDER
                print('ℹ️ Local-only folder. Renaming locally.');

                await folder.rename(newPath);
                _loadFolders(); // or _loadItems()
                _countFoldersAndImages();
                return;
              }

              // server rename first
              final success = await folderService.renameFolderOnServer(
                folderId: folderId,
                newName: newName,
              );

              if (!success) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Failed to rename folder on server'),
                  ),
                );
                return;
              }

              // local rename
              await folder.rename(newPath);

              // ✅ update metadata name
              await FolderService.updateFolderMetaName(folderId, newName);

              _loadFolders();
              _countFoldersAndImages();
            },
            child: const Text('Rename'),
          ),
        ],
      ),
    );
  }

  Future<void> _shareFolder(Directory folder) async {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => Wrap(
        children: [
          ListTile(
            leading: Icon(
              Icons.email,
              color: Theme.of(context).colorScheme.secondary,
            ),
            title: const Text("Share via Email (App Share)"),
            onTap: () async {
              Navigator.pop(ctx); // close bottom sheet
              final TextEditingController controller = TextEditingController();

              await showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Share Folder'),
                  content: TextField(
                    controller: controller,
                    decoration: const InputDecoration(
                      hintText: 'Enter User Email to share with',
                    ),
                    keyboardType: TextInputType.emailAddress,
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
                            const SnackBar(content: Text('Invalid Email')),
                          );
                          return;
                        }

                        // Get folder ID from server
                        final folderId = await FolderShareService.getFolderId(
                          folderName: folder.path.split('/').last,
                          parentId: null, // main folder has no parent
                        );

                        if (folderId == null) {
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'This folder hasn’t been uploaded yet. Upload first to share.',
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
                                  ? 'Folder shared successfully!'
                                  : 'Failed to share',
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
          ListTile(
            leading: Icon(
              Icons.share,
              color: Theme.of(context).colorScheme.primary,
            ),
            title: const Text("Share via WhatsApp / Bluetooth"),
            onTap: () async {
              Navigator.pop(ctx); // close bottom sheet

              final files = folder
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
                  text: "📂 Sharing folder: ${folder.path.split('/').last}",
                );
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text("No images found in this folder"),
                  ),
                );
              }
            },
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
        _loadFolders(); // Refresh UI
      } catch (e) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error deleting folder: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: isSearching
            ? TextField(
                autofocus: true,
                decoration: InputDecoration(
                  hintText: 'Search folders...',
                  border: InputBorder.none,
                ),
                onChanged: _filterFolders,
              )
            : Text(appBarTitle),

        leading: IconButton(
          icon: const Icon(Icons.menu),
          onPressed: () => _showCustomDrawer(context),
        ),
        actions: [
          IconButton(
            icon: Icon(isSearching ? Icons.close : Icons.search),
            onPressed: () {
              setState(() {
                if (isSearching) {
                  // Reset search
                  searchQuery = '';
                  filteredFolders = folders;
                }
                isSearching = !isSearching;
              });
            },
          ),
        ],
        backgroundColor: Theme.of(context).appBarTheme.backgroundColor,
        foregroundColor: Theme.of(context).appBarTheme.foregroundColor,
        centerTitle: true,
      ),
      drawer: null,
      body: Column(
        children: [
          // 🔹 Always-visible storage banner
          if (isStorageNearLimit)
            AnimatedContainer(
              duration: const Duration(milliseconds: 400),
              width: double.infinity,
              color: percentUsed >= 99.5
                  ? Colors.red.shade400
                  : Theme.of(context).colorScheme.primary,
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
              child: Row(
                children: [
                  Icon(
                    percentUsed >= 99.5
                        ? Icons.error_outline
                        : Icons.warning_amber_rounded,
                    color: Colors.white,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      storageMessage,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // Main content below banner
          Expanded(
            child: TabBarView(
              controller: _tabController,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _buildFolderGrid(),
                folders.isNotEmpty
                    ? ScanScreen(
                        userId: widget.userId,
                        folderName: folders.first.path.split('/').last,
                      )
                    : const Center(child: Text("No folder selected")),
                const SizedBox(),
                const SizedBox(),
                const SizedBox(),
              ],
            ),
          ),
        ],
      ),

      bottomNavigationBar: SafeArea(
        child: BottomTabs(
          controller: _tabController,
          userId: widget.userId, // or actual userId from prefs/auth
          folderName: selectedFolder != null
              ? selectedFolder!.path.split('/').last
              : "",
          showCamera: true,
          cameraDisabled: true,
          scanDisabled: true,
          onCameraTap: _showCameraDisabledMessage,
          onScanTap: () {
            _showScanDisabledMessage(); // call the async function, but closure itself is not async
          },
          onCreateFolder: (index) {
            _tabController.index = 0;
            _showCreateFolderDialog(context);
          },
          onUploadComplete: () {
            setState(() {
              _loadFolders(); // ✅ re-scan folders and update counts
              _countFoldersAndImages();
            });
          },
        ),
      ),
    );
  }

  Widget _buildFolderGrid() {
    if (filteredFolders.isEmpty) {
      return Center(
        child: Text(
          "No folders found",
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: filteredFolders.length,
      itemBuilder: (context, index) {
        final folder = filteredFolders[index];
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
            leading: Icon(
              Icons.folder,
              size: 40,
              color: Theme.of(context).colorScheme.primary,
            ),
            title: Text(
              folderName,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            subtitle: FutureBuilder<Map<String, int>>(
              future: folderService.countSubfoldersImagesVideos(folder),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Text('Loading...');
                }
                final subfolderCount = snapshot.data?['subfolders'] ?? 0;
                final imageCount = snapshot.data?['images'] ?? 0;

                return Text(
                  'Subfolders: $subfolderCount\n'
                  'Images: $imageCount    Videos: ${snapshot.data?['videos'] ?? 0}    PDFs: ${snapshot.data?['pdfs'] ?? 0}',
                  style: Theme.of(context).textTheme.bodySmall,
                );
              },
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: Icon(
                    Icons.edit,
                    color: Theme.of(context).colorScheme.secondary,
                  ),
                  onPressed: () {
                    _renameFolder(folder);
                  },
                ),
                IconButton(
                  icon: Icon(
                    Icons.share,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  onPressed: () {
                    _shareFolder(folder);
                  },
                ),
                IconButton(
                  icon: Icon(
                    Icons.delete,
                    color: Theme.of(context).colorScheme.error,
                  ),
                  onPressed: () {
                    _deleteFolder(folder);
                  },
                ),
              ],
            ),
            onTap: () {
              setState(() {
                selectedFolder = folder; // ✅ store currently tapped folder
              });
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => PhotoListScreen(
                    folder: folder,
                    userId: widget.userId,
                    selectedFolder: folder,
                  ),
                ),
              ).then((_) {
                _countFoldersAndImages();
              });
            },
          ),
        );
      },
    );
  }
}

import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:photomanager_practice/services/bottom_tabs.dart';
import 'package:photomanager_practice/widgets/custom_drawer.dart';
import 'photo_list_screen.dart';
import 'package:photomanager_practice/services/folder_service.dart';

class FolderScreen extends StatefulWidget {
  const FolderScreen({super.key});

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
  // late final StreamSubscription _statusCheckSub;

  final FolderService folderService = FolderService();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    await _loadFolders();
    await _loadUserName();
    await _loadAvatar();
    await _countFoldersAndImages();
  }

  @override
  void dispose() {
    _tabController.dispose();
    //_statusCheckSub.cancel();
    super.dispose();
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
    final result = await folderService.countFoldersAndImages();
    if (!mounted) return;
    setState(() {
      folderCount = result['folders'] ?? 0;
      imageCount = result['images'] ?? 0;
    });
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
        content: TextField(
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Enter folder name'),
          onChanged: (value) => folderName = value.trim(),
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

              if (folderName.length > 20) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Folder name must be 20 characters or less'),
                  ),
                );
                return;
              }

              final created = await folderService.createFolder(folderName);
              if (created) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Folder created successfully')),
                );
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Folder already exists')),
                );
              }

              Navigator.of(dialogContext).pop();
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
                  _loadFolders(); // Refresh UI
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
                  hintStyle: TextStyle(
                    color: Theme.of(context).hintColor, // ✅ adapts to theme
                  ),
                  border: InputBorder.none,
                ),
                style: TextStyle(
                  color: Theme.of(
                    context,
                  ).textTheme.bodyLarge?.color, // ✅ adapts to theme
                  fontSize: 18,
                ),
                onChanged: _filterFolders,
              )
            : const Text("Folders"),
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
      body: TabBarView(
        controller: _tabController,
        physics: const NeverScrollableScrollPhysics(),
        children: [
          _buildFolderGrid(),
          const SizedBox(),
          const SizedBox(),
          const SizedBox(),
        ],
      ),
      bottomNavigationBar: BottomTabs(
        controller: _tabController,
        showCamera: true,
        cameraDisabled: true,
        onCameraTap: _showCameraDisabledMessage,
        onCreateFolder: (index) {
          _tabController.index = 0;
          _showCreateFolderDialog(context);
        },
        onUploadComplete: () {
          setState(() {
            _loadFolders(); // ✅ re-scan folders and update counts
          });
        },
      ),
    );
  }

  Widget _buildFolderGrid() {
    if (filteredFolders.isEmpty) {
      return const Center(
        child: Text(
          "No folders found",
          style: TextStyle(color: Colors.white70),
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
            leading: const Icon(Icons.folder, size: 40, color: Colors.orange),
            title: Text(
              folderName,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            subtitle: FutureBuilder<Map<String, int>>(
              future: folderService.countSubfoldersAndImages(folder),
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
                  onPressed: () {
                    _renameFolder(folder);
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.delete, color: Colors.redAccent),
                  onPressed: () {
                    _deleteFolder(folder);
                  },
                ),
              ],
            ),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => PhotoListScreen(folder: folder),
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

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
  late TabController _tabController;
  bool isAutoUploadEnabled = false;
  bool isUploading = false;
  String userName = '';
  File? _avatarImage;
  int folderCount = 0;
  int imageCount = 0;
  int totalImages = 0;

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
    if (!mounted) return;
    setState(() {
      folders = result;
    });
  }

  void _showCustomDrawer(BuildContext context) {
    showDialog(
      context: context,
      barrierColor: Colors.black54,
      builder: (context) {
        return CustomDrawer(
          userName: userName,
          avatarImage: _avatarImage,
          parentContext: context,
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
                Navigator.of(dialogContext).pop();
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

  void _showRenameDialog(BuildContext context, String folderPath) {
    final TextEditingController controller = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename Folder'),
        content: TextField(controller: controller),
        actions: [
          TextButton(
            onPressed: () async {
              String newName = controller.text.trim();
              Navigator.pop(context); // Close dialog first

              if (newName.isNotEmpty) {
                final renamed = await folderService.renameFolder(
                  folderPath,
                  newName,
                );

                if (renamed) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Folder renamed successfully'),
                    ),
                  );
                  _loadFolders();
                  _countFoldersAndImages();
                } else {
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Rename failed')),
                  );
                }
              }
            },
            child: const Text('Rename'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  void _confirmDeleteFolder(BuildContext context, String folderPath) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Folder'),
        content: const Text('Are you sure you want to delete this folder?'),
        actions: [
          TextButton(
            onPressed: () async {
              Navigator.pop(context); // Close dialog first

              final deleted = await folderService.deleteFolder(folderPath);
              if (deleted) {
                if (!mounted) return;
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('Folder deleted')));
                _loadFolders();
                _countFoldersAndImages();
              } else {
                if (!mounted) return;
                Navigator.pop(context); // Close dialog if delete failed
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Failed to delete folder')),
                );
              }
            },
            child: const Text('Delete'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Column(
          children: [
            Text(
              "Folders ($folderCount) | Images ($imageCount)",
              style: const TextStyle(fontSize: 16),
            ),
          ],
        ),
        leading: IconButton(
          icon: const Icon(Icons.menu),
          onPressed: () => _showCustomDrawer(context),
        ),
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
      ),
    );
  }

  Widget _buildFolderGrid() {
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
            leading: Icon(Icons.folder, size: 40, color: Colors.orange),
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
                    _showRenameDialog(context, folder.path);
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.delete, color: Colors.redAccent),
                  onPressed: () {
                    _confirmDeleteFolder(context, folder.path);
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

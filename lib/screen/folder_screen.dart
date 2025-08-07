import 'dart:io';
import 'package:flutter/material.dart';
import 'package:photomanager_practice/screen/login_screen.dart';
import 'package:photomanager_practice/screen/user_profile_screen.dart';
import 'package:photomanager_practice/services/bottom_tabs.dart';
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
        return Align(
          alignment: Alignment.topLeft,
          child: Padding(
            padding: const EdgeInsets.only(left: 12.0, top: 50.0),
            child: Material(
              elevation: 12,
              borderRadius: const BorderRadius.only(
                topRight: Radius.circular(24),
                bottomRight: Radius.circular(24),
                topLeft: Radius.circular(24),
                bottomLeft: Radius.circular(24),
              ),
              color: Theme.of(context).colorScheme.surface,
              child: Container(
                width: MediaQuery.of(context).size.width * 0.75,
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ListTile(
                      leading: CircleAvatar(
                        radius: 24,
                        backgroundColor: Colors.deepPurple,
                        backgroundImage: _avatarImage != null
                            ? FileImage(_avatarImage!)
                            : null,
                        child: _avatarImage == null
                            ? const Icon(Icons.person, color: Colors.white)
                            : null,
                      ),
                      title: Text(
                        userName,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                      ),
                    ),
                    const Divider(),
                    ListTile(
                      leading: const Icon(Icons.person),
                      title: const Text("User Profile"),
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const UserProfileScreen(),
                          ),
                        );
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.logout),
                      title: const Text("Logout"),
                      onTap: () {
                        Navigator.pop(context);
                        _showLogoutDialog();
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _showLogoutDialog() {
    folderService.showLogoutDialog(context, () {
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => LoginScreen()),
        );
      }
    });
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

    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: 1,
      ),
      itemCount: folders.length,
      itemBuilder: (context, index) {
        final folder = folders[index];
        final folderName = folder.path.split('/').last;

        return GestureDetector(
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
          child: Column(
            children: [
              Container(
                height: 80,
                width: 80,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(Icons.folder, size: 40, color: Colors.orange),
              ),
              const SizedBox(height: 8),
              Flexible(
                child: Text(
                  folderName,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

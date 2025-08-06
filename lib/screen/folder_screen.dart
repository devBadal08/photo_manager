import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as path;
import 'package:photomanager_practice/screen/login_screen.dart';
import 'package:photomanager_practice/screen/user_profile_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:photomanager_practice/services/bottom_tabs.dart';
import 'photo_list_screen.dart';

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

  Future<void> _countTotalImages() async {
    int count = 0;

    for (final folder in folders) {
      final files = folder.listSync();
      final imageFiles = files.where((file) {
        final ext = path.extension(file.path).toLowerCase();
        return file is File && ['.jpg', '.jpeg', '.png'].contains(ext);
      });
      count += imageFiles.length;
    }

    setState(() {
      totalImages = count;
    });
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _loadFolders();
    _loadUserName(); // Load the username
    _loadAvatar();
    countFoldersAndImages();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadUserName() async {
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString('user_name'); // Ensure you saved it before
    setState(() {
      userName = name ?? 'Guest';
    });
  }

  Future<void> _loadAvatar() async {
    final prefs = await SharedPreferences.getInstance();
    final avatarPath = prefs.getString('avatar_path');
    if (avatarPath != null && File(avatarPath).existsSync()) {
      setState(() {
        _avatarImage = File(avatarPath);
      });
    }
  }

  Future<void> _pickAndSaveAvatar() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('avatar_path', picked.path);

      setState(() {
        _avatarImage = File(picked.path);
      });
    }
  }

  Future<void> countFoldersAndImages() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getInt('user_id');

    if (userId == null) {
      print("❌ No user ID found");
      return;
    }

    final Directory rootDir = Directory(
      '/storage/emulated/0/Pictures/MyApp/$userId',
    );

    if (!rootDir.existsSync()) {
      print("📂 User folder does not exist");
      setState(() {
        folderCount = 0;
        imageCount = 0;
      });
      return;
    }

    int totalFolders = 0;
    int totalImages = 0;

    void traverse(Directory dir) {
      final List<FileSystemEntity> entities = dir.listSync();

      for (FileSystemEntity entity in entities) {
        if (entity is Directory) {
          totalFolders++;
          traverse(entity); // Recursively count subfolders
        } else if (entity is File) {
          if (entity.path.endsWith('.jpg') ||
              entity.path.endsWith('.jpeg') ||
              entity.path.endsWith('.png')) {
            totalImages++;
          }
        }
      }
    }

    traverse(rootDir);

    print("📁 Total folders for $userId: $totalFolders");
    print("🖼️ Total images for $userId: $totalImages");

    setState(() {
      folderCount = totalFolders;
      imageCount = totalImages;
    });
  }

  Future<void> _loadFolders() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getInt('user_id');

    if (userId == null) {
      print("❌ No user ID found");
      return;
    }

    final baseDir = Directory('/storage/emulated/0/Pictures/MyApp/$userId');
    if (!await baseDir.exists()) {
      await baseDir.create(recursive: true);
    }

    final all = baseDir
        .listSync()
        .whereType<Directory>()
        .where((dir) => !dir.path.contains('/flutter_assets'))
        .toList();

    setState(() {
      folders = all;
    });
  }

  Future<void> _showCreateFolderDialog(BuildContext context) async {
    String folderName = '';
    SharedPreferences prefs = await SharedPreferences.getInstance();
    String? userId = prefs.getInt('user_id')?.toString();

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
              if (folderName.isEmpty || userId == null) {
                Navigator.of(dialogContext).pop();
                return;
              }

              final dir = Directory(
                '/storage/emulated/0/Pictures/MyApp/$userId/$folderName',
              );

              try {
                if (await dir.exists()) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Folder already exists')),
                  );
                } else {
                  await dir.create(recursive: true);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Folder created successfully'),
                    ),
                  );
                }

                Navigator.of(dialogContext).pop(); // ✅ Closes the dialog
                _loadFolders(); // ✅ Reload folder list
              } catch (e) {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text('Error: $e')));
                Navigator.of(dialogContext).pop(); // Still close the dialog
              }
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _handleCameraCapture() async {
    if (folders.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Please create a folder first."),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final folder = await showDialog<Directory>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: const Text(
          "Choose Folder",
          style: TextStyle(color: Colors.white),
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: folders.length,
            itemBuilder: (ctx, index) {
              final folderName = folders[index].path.split('/').last;
              return ListTile(
                title: Text(
                  folderName,
                  style: const TextStyle(color: Colors.white),
                ),
                onTap: () => Navigator.pop(ctx, folders[index]),
              );
            },
          ),
        ),
      ),
    );

    if (folder == null) return;

    final pickedFile = await ImagePicker().pickImage(
      source: ImageSource.camera,
    );
    if (pickedFile == null) return;

    final fileName = path.basename(pickedFile.path);
    final savedImage = await File(
      pickedFile.path,
    ).copy('${folder.path}/$fileName');

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("Saved to: ${savedImage.path}"),
        backgroundColor: Colors.green,
      ),
    );
  }

  void _showCameraDisabledMessage() {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text("Camera is disabled")));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        title: Column(
          children: [
            Text(
              "Folders ($folderCount) | Images ($imageCount)",
              style: const TextStyle(fontSize: 16),
            ),
          ],
        ),
        backgroundColor: const Color(0xFF1F1F1F),
        foregroundColor: Colors.white,
        centerTitle: true,
      ),
      drawer: Drawer(
        backgroundColor: Colors.black,
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            UserAccountsDrawerHeader(
              decoration: const BoxDecoration(color: Colors.black87),
              accountName: Text(
                userName,
                style: const TextStyle(color: Colors.white),
              ),
              accountEmail: const Text(
                '',
                style: TextStyle(color: Colors.white70),
              ),
              currentAccountPicture: GestureDetector(
                onTap: _pickAndSaveAvatar, // 👈 Tap to change avatar
                child: CircleAvatar(
                  backgroundColor: Colors.orange,
                  backgroundImage: _avatarImage != null
                      ? FileImage(_avatarImage!)
                      : null,
                  child: _avatarImage == null
                      ? const Icon(Icons.person, color: Colors.white)
                      : null,
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.person, color: Colors.white),
              title: const Text(
                'User Profile',
                style: TextStyle(color: Colors.white),
              ),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const UserProfileScreen(),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.logout, color: Colors.white),
              title: const Text(
                'Logout',
                style: TextStyle(color: Colors.white),
              ),
              onTap: () {
                showDialog(
                  context: context,
                  builder: (BuildContext context) {
                    return AlertDialog(
                      title: const Text("Confirm Logout"),
                      content: const Text("Are you sure you want to logout?"),
                      actions: [
                        TextButton(
                          child: const Text("Cancel"),
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                        TextButton(
                          child: const Text("Logout"),
                          onPressed: () async {
                            final prefs = await SharedPreferences.getInstance();
                            await prefs.clear();
                            Navigator.of(context).pop(); // Close the dialog
                            Navigator.pushReplacement(
                              context,
                              MaterialPageRoute(
                                builder: (context) => LoginScreen(),
                              ),
                            );
                          },
                        ),
                      ],
                    );
                  },
                );
              },
            ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        physics: const NeverScrollableScrollPhysics(),
        children: [
          _buildFolderGrid(),
          //_buildAutoUploadTab(),
          const SizedBox(), // Placeholder for Upload tab
          const SizedBox(),
          const SizedBox(), // Placeholder for Create Folder tab
        ],
      ),

      bottomNavigationBar: BottomTabs(
        controller: _tabController,
        showCamera: true,
        cameraDisabled: true,
        onCameraTap: _showCameraDisabledMessage,
        onCreateFolder: (index) {
          _tabController.index = 0; // Always revert to Folders tab
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
              _countTotalImages(); // Refresh when user comes back
            });
          },

          child: Column(
            children: [
              Container(
                height: 80,
                width: 80,
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(Icons.folder, size: 40, color: Colors.orange),
              ),
              const SizedBox(height: 8),
              Flexible(
                child: Text(
                  folderName,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // Widget _buildAutoUploadTab() {
  //   return Center(
  //     child: Row(
  //       mainAxisAlignment: MainAxisAlignment.center,
  //       children: [
  //         Switch(
  //           value: isAutoUploadEnabled,
  //           onChanged: (val) {
  //             setState(() => isAutoUploadEnabled = val);
  //           },
  //         ),
  //         const Text("Auto Upload", style: TextStyle(color: Colors.white70)),
  //       ],
  //     ),
  //   );
  // }
}

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as path;
import 'package:permission_handler/permission_handler.dart';
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

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);

    _tabController.addListener(() {
      if (_tabController.indexIsChanging) {
        final newIndex = _tabController.index;

        if (newIndex == 3) {
          Future.delayed(Duration.zero, () {
            _tabController.index = 0;
            _showCreateFolderDialog(context);
          });
        }
      }
    });
    _loadFolders();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
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
      builder: (context) => AlertDialog(
        title: const Text('Create Folder'),
        content: TextField(
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Enter folder name'),
          onChanged: (value) => folderName = value.trim(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (folderName.isEmpty || userId == null) return;

              final dir = Directory(
                '/storage/emulated/0/Pictures/MyApp/$userId/$folderName',
              );

              if (await dir.exists()) {
                Navigator.pop(context); // Close dialog first
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Folder already exists')),
                );
              } else {
                try {
                  await dir.create(recursive: true);
                  Navigator.pop(context); // Close dialog
                  _loadFolders(); // Refresh UI
                } catch (e) {
                  //Navigator.pop(context); // Ensure dialog closes
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text('Error: $e')));
                }
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
        title: const Text("My Folders"),
        backgroundColor: const Color(0xFF1F1F1F),
        foregroundColor: Colors.white,
        centerTitle: true,
      ),

      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: const [
            DrawerHeader(
              decoration: BoxDecoration(color: Colors.black),
              child: Text('Menu', style: TextStyle(color: Colors.white)),
            ),
            ListTile(title: Text('Option 1')),
            ListTile(title: Text('Option 2')),
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
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => PhotoListScreen(folder: folder)),
          ),
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

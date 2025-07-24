import 'dart:io';
import 'package:flutter/material.dart';
import 'photo_list_screen.dart';

class FolderScreen extends StatefulWidget {
  const FolderScreen({super.key});

  @override
  State<FolderScreen> createState() => _FolderScreenState();
}

class _FolderScreenState extends State<FolderScreen> {
  List<Directory> folders = [];

  @override
  void initState() {
    super.initState();
    _loadFolders();
  }

  Future<void> _loadFolders() async {
    final baseDir = Directory('/storage/emulated/0/Pictures/MyApp');
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

  Future<void> _showCreateFolderDialog() async {
    String folderName = '';

    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Enter Folder Name'),
          content: TextField(
            autofocus: true,
            decoration: const InputDecoration(hintText: 'MyFolder'),
            onChanged: (value) {
              folderName = value;
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                _createFolder(folderName);
              },
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _createFolder(String name) async {
    if (name.isEmpty) return;

    final baseDir = Directory('/storage/emulated/0/Pictures/MyApp');
    if (!await baseDir.exists()) {
      await baseDir.create(recursive: true);
    }

    final newFolder = Directory('${baseDir.path}/$name');

    if (await newFolder.exists()) {
      // Show warning if folder exists
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Folder '$name' already exists."),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    await newFolder.create();
    print("📁 Folder created at: ${newFolder.path}");
    _loadFolders();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(70),
        child: AppBar(
          flexibleSpace: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFFFFD180), Color(0xFF81D4FA)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),
          title: const Padding(
            padding: EdgeInsets.only(top: 16.0),
            child: Text("My Folders"),
          ),
          centerTitle: true,
          backgroundColor: Colors.transparent,
          elevation: 0,
        ),
      ),
      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            DrawerHeader(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFFFFD180), Color(0xFF81D4FA)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: const Text(
                'Menu',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
            ),
            ListTile(
              leading: Icon(Icons.settings),
              title: Text('Settings'),
              onTap: () {
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: Icon(Icons.info_outline),
              title: Text('About'),
              onTap: () {
                Navigator.pop(context);
              },
            ),
          ],
        ),
      ),
      body: folders.isEmpty
          ? const Center(child: Text("No folders yet"))
          : GridView.builder(
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

                double scale = 1.0;
                return StatefulBuilder(
                  builder: (context, setInnerState) {
                    return GestureDetector(
                      onTapDown: (_) {
                        setInnerState(() => scale = 0.95);
                      },
                      onTapUp: (_) {
                        setInnerState(() => scale = 1.0);
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => PhotoListScreen(folder: folder),
                          ),
                        );
                      },
                      onTapCancel: () {
                        setInnerState(() => scale = 1.0);
                      },
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          AnimatedScale(
                            scale: scale,
                            duration: const Duration(milliseconds: 150),
                            curve: Curves.easeOut,
                            child: Container(
                              height: 80,
                              width: 80,
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(
                                  0.25,
                                ), // semi-transparent glass effect
                                borderRadius: BorderRadius.circular(16),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.1),
                                    blurRadius: 8,
                                    offset: const Offset(2, 4),
                                  ),
                                ],
                                border: Border.all(
                                  color: Colors.white.withOpacity(0.4),
                                ),
                              ),
                              child: const Icon(
                                Icons.folder,
                                size: 40,
                                color: Color(0xFFFFA726), // orange folder icon
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Flexible(
                            child: Text(
                              folderName,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: Colors.black,
                              ),
                              textAlign: TextAlign.center,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showCreateFolderDialog,
        backgroundColor: Color(0xFF0288D1),
        elevation: 6,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: const Icon(Icons.create_new_folder),
      ),
    );
  }
}

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
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
    final baseDir = await getApplicationDocumentsDirectory();
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

    final baseDir = await getApplicationDocumentsDirectory();
    final newFolder = Directory('${baseDir.path}/$name');

    if (!await newFolder.exists()) {
      await newFolder.create();
      print("📁 Folder created at: ${newFolder.path}");
    } else {
      print("⚠️ Folder already exists at: ${newFolder.path}");
    }

    _loadFolders();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("My Folders")),
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
                final Color folderColor = Colors.deepPurple.shade100;

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
                                color: folderColor,
                                borderRadius: BorderRadius.circular(12),
                                boxShadow: [
                                  BoxShadow(
                                    color: folderColor.withOpacity(0.5),
                                    blurRadius: 6,
                                    offset: const Offset(2, 4),
                                  ),
                                ],
                              ),
                              child: const Icon(
                                Icons.folder,
                                size: 40,
                                color: Colors.deepPurple,
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            folderName,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Colors.black,
                            ),
                            textAlign: TextAlign.center,
                            overflow: TextOverflow.ellipsis,
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
        child: const Icon(Icons.create_new_folder),
      ),
    );
  }
}

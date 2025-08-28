import 'package:flutter/material.dart';
import 'package:photomanager_practice/screen/shared_folder_photos_screen.dart';
import 'package:photomanager_practice/services/folder_share_service.dart';

class SharedWithMeScreen extends StatelessWidget {
  const SharedWithMeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Shared With Me"), centerTitle: true),
      body: FutureBuilder<List<dynamic>>(
        future: FolderShareService().getSharedWithMe(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(child: Text("No folders shared with you"));
          }

          final sharedFolders = snapshot.data!;

          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: sharedFolders.length,
            itemBuilder: (context, index) {
              final share = sharedFolders[index];
              final folder = share['folder'];
              final photos = folder['photos'] ?? []; // 👈 get photos list

              return Card(
                margin: const EdgeInsets.symmetric(vertical: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 4,
                child: ExpansionTile(
                  leading: const Icon(
                    Icons.folder_shared,
                    size: 40,
                    color: Colors.green,
                  ),
                  title: Text(folder['name'] ?? "Unnamed Folder"),
                  subtitle: Text("Shared by User ID: ${share['shared_by']}"),
                  children: [
                    if (folder['photos'] != null && folder['photos'].isNotEmpty)
                      SizedBox(
                        height: 120,
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          itemCount: folder['photos'].length,
                          itemBuilder: (context, i) {
                            final photo = folder['photos'][i];
                            return Padding(
                              padding: const EdgeInsets.all(4),
                              child: Image.network(
                                photo['url'], // 👈 backend provides full URL
                                width: 100,
                                height: 100,
                                fit: BoxFit.cover,
                                errorBuilder: (c, e, s) =>
                                    const Icon(Icons.broken_image),
                              ),
                            );
                          },
                        ),
                      )
                    else
                      const Padding(
                        padding: EdgeInsets.all(8.0),
                        child: Text("No photos in this folder"),
                      ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}

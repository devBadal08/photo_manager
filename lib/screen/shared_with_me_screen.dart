import 'package:flutter/material.dart';
import 'package:photomanager_practice/screen/photo_list_screen.dart';
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
              final folder = sharedFolders[index];
              final realFolder = folder['folder'];

              return Card(
                margin: const EdgeInsets.symmetric(vertical: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 4,
                child: ListTile(
                  leading: const Icon(
                    Icons.folder_shared,
                    size: 40,
                    color: Colors.green,
                  ),

                  title: Text(realFolder?['name'] ?? 'Unnamed Folder'),
                  subtitle: Text(
                    "Owner ID: ${realFolder?['user_id'] ?? 'Unknown'}",
                  ),

                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => PhotoListScreen(
                          isShared: true,
                          sharedFolderId: realFolder['id'],
                          sharedFolderName: realFolder['path'],
                          userId: realFolder['user_id'].toString(),
                        ),
                      ),
                    );
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:photomanager_practice/screen/photo_list_screen.dart';

class SharedFolderList extends StatelessWidget {
  final List<Map<String, dynamic>> folders;
  final String userId;
  final String? currentPath;
  final bool canWrite;

  const SharedFolderList({
    super.key,
    required this.folders,
    required this.userId,
    this.currentPath,
    this.canWrite = false,
  });

  @override
  Widget build(BuildContext context) {
    if (folders.isEmpty) {
      return Center(
        child: Text(
          "No shared subfolders found",
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: folders.length,
      itemBuilder: (context, index) {
        final folder = folders[index];

        final folderName = folder['name'] ?? 'Unnamed';

        final int? folderId = folder['id'] is int
            ? folder['id']
            : int.tryParse(folder['id']?.toString() ?? '');

        if (folderId == null) {
          return const SizedBox.shrink();
        }

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
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => PhotoListScreen(
                    isShared: true,

                    // ✅ IMPORTANT:
                    // Use THIS subfolder's backend ID.
                    sharedFolderId: folderId,

                    // ✅ Keep the path/name for UI/navigation.
                    sharedFolderName: folderName,

                    userId: userId,

                    // ✅ IMPORTANT:
                    // Subfolder inherits parent's write permission.
                    canWrite: canWrite,
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

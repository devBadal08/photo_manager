import 'dart:io';
import 'package:flutter/material.dart';
import 'package:photomanager_practice/screen/photo_list_screen.dart';

class FolderListCards extends StatelessWidget {
  final List<Directory> folders;
  final String userId;
  final Directory? selectedFolder;
  final int? folderBackendId;
  final Future<Map<String, int>> Function(Directory) countFolderStats;
  final void Function(Directory) onRename;
  final void Function(Directory) onDelete;
  final void Function(Directory) onShare;

  const FolderListCards({
    super.key,
    required this.folders,
    required this.userId,
    required this.selectedFolder,
    required this.folderBackendId,
    required this.countFolderStats,
    required this.onRename,
    required this.onDelete,
    required this.onShare,
  });

  @override
  Widget build(BuildContext context) {
    if (folders.isEmpty) {
      return Center(
        child: Text(
          "No folders yet",
          style: Theme.of(context).textTheme.bodyMedium,
        ),
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
            subtitle: FutureBuilder<Map<String, int>>(
              future: countFolderStats(folder),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Text('Loading...');
                }
                final stats = snapshot.data!;
                return Text(
                  'Subfolders: ${stats['subfolders']}   Images: ${stats['images']}   Videos: ${stats['videos']}   PDFs: ${stats['pdfs']}',
                  style: Theme.of(context).textTheme.bodySmall,
                );
              },
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: Icon(
                    Icons.edit,
                    color: Theme.of(context).colorScheme.secondary,
                  ),
                  onPressed: () => onRename(folder),
                ),
                IconButton(
                  icon: Icon(
                    Icons.share,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  onPressed: () => onShare(folder),
                ),
                IconButton(
                  icon: Icon(
                    Icons.delete,
                    color: Theme.of(context).colorScheme.error,
                  ),
                  onPressed: () => onDelete(folder),
                ),
              ],
            ),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => PhotoListScreen(
                    folder: folder,
                    userId: userId,
                    selectedFolder: selectedFolder,
                    folderBackendId: folderBackendId,
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

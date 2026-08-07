import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/material.dart';

class BackupService {
  static Future<void> backupAllPhotos(
    BuildContext context,
    Directory sourceDir,
  ) async {
    try {
      if (!await sourceDir.exists()) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("No photos found to backup")),
        );
        return;
      }

      // Ask user to pick destination folder
      String? selectedPath = await FilePicker.platform.getDirectoryPath();

      if (selectedPath == null) {
        // User cancelled
        return;
      }

      final targetDir = Directory(selectedPath);

      int totalFiles = 0;

      await for (final entity in sourceDir.list(recursive: true)) {
        if (entity is File) {
          totalFiles++;
        }
      }
      progressNotifier.value = 0;
      progressTextNotifier.value = "0 / $totalFiles files copied";
      _showProgressDialog(context);
      int copied = 0;

      await for (final entity in sourceDir.list(recursive: true)) {
        if (entity is File) {
          final relativePath = entity.path.replaceFirst(sourceDir.path, '');
          final newFile = File('${targetDir.path}/$relativePath');

          await newFile.parent.create(recursive: true);
          await entity.copy(newFile.path);

          copied++;

          if (copied % 10 == 0 || copied == totalFiles) {
            progressNotifier.value = copied / totalFiles;
            progressTextNotifier.value = "$copied / $totalFiles files copied";

            await Future(() {});
          }
        }
      }

      if (Navigator.of(context, rootNavigator: true).canPop()) {
        Navigator.of(context, rootNavigator: true).pop();
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Backup completed. $copied media items copied")),
      );
    } catch (e) {
      debugPrint("❌ Backup error: $e");
      if (Navigator.of(context, rootNavigator: true).canPop()) {
        Navigator.of(context, rootNavigator: true).pop();
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Backup failed")));
    }
  }

  static Future<void> backupSelectedPhotos(
    BuildContext context,
    List<String> selectedPaths,
  ) async {
    try {
      if (selectedPaths.isEmpty) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text("No photos selected")));
        return;
      }

      // Ask user to choose backup location
      String? selectedDir = await FilePicker.platform.getDirectoryPath();

      if (selectedDir == null) return;

      final targetDir = Directory(selectedDir);

      int totalFiles = selectedPaths.length;
      progressNotifier.value = 0;
      progressTextNotifier.value = "0 / $totalFiles files copied";
      _showProgressDialog(context);
      int copied = 0;

      for (final path in selectedPaths) {
        // Skip network images
        if (path.startsWith("http")) continue;

        final file = File(path);

        if (!await file.exists()) continue;

        final fileName = file.path.split('/').last;
        final newFile = File('${targetDir.path}/$fileName');

        await newFile.parent.create(recursive: true);
        await file.copy(newFile.path);

        copied++;
        if (copied % 10 == 0 || copied == totalFiles) {
          progressNotifier.value = copied / totalFiles;
          progressTextNotifier.value = "$copied / $totalFiles files copied";

          await Future(() {});
        }
      }
      if (Navigator.of(context, rootNavigator: true).canPop()) {
        Navigator.of(context, rootNavigator: true).pop();
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("$copied media items backed up")));
    } catch (e) {
      debugPrint("❌ Backup selected error: $e");
      if (Navigator.of(context, rootNavigator: true).canPop()) {
        Navigator.of(context, rootNavigator: true).pop();
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Backup failed")));
    }
  }

  static ValueNotifier<double> progressNotifier = ValueNotifier(0);
  static ValueNotifier<String> progressTextNotifier = ValueNotifier("");

  static void _showProgressDialog(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) {
        return AlertDialog(
          title: const Text("Backing up files..."),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ValueListenableBuilder<double>(
                valueListenable: progressNotifier,
                builder: (_, progress, __) {
                  return LinearProgressIndicator(value: progress);
                },
              ),
              const SizedBox(height: 16),
              ValueListenableBuilder<String>(
                valueListenable: progressTextNotifier,
                builder: (_, text, __) {
                  return Text(text);
                },
              ),
            ],
          ),
        );
      },
    );
  }
}

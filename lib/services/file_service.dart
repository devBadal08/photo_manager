// lib/services/file_service.dart
import 'dart:io';

class FileService {
  // Load folders & files
  static Future<Map<String, dynamic>> loadItems(
    Directory folder,
    String mainFolderName,
  ) async {
    if (!await folder.exists()) {
      return {"folders": <Directory>[], "files": <File>[]};
    }

    final dirs = <Directory>[];
    final files = <File>[];

    await for (final entity in folder.list()) {
      if (entity is Directory) {
        final sub = entity.path.split('/').last;
        if (sub.toLowerCase() != mainFolderName.toLowerCase()) {
          dirs.add(entity);
        }
      } else if (entity is File &&
          (isMedia(entity.path) || isPdf(entity.path))) {
        files.add(entity);
      }
    }

    dirs.sort((a, b) => b.statSync().changed.compareTo(a.statSync().changed));
    return {"folders": dirs, "files": files};
  }

  // Check if file is PDF
  static bool isPdf(String path) => path.toLowerCase().endsWith('.pdf');

  // Check if file is image/video
  static bool isMedia(String path) {
    final lower = path.toLowerCase();
    return lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.png') ||
        lower.endsWith('.mp4');
  }

  // Rename folder
  static Future<void> renameFolder(
    Directory folder,
    String newName,
    String mainFolderName,
  ) async {
    if (newName.toLowerCase() == mainFolderName.toLowerCase()) {
      throw Exception("Folder name cannot be same as parent folder");
    }
    final newPath = '${folder.parent.path}/$newName';
    final newDir = Directory(newPath);
    if (await newDir.exists()) {
      throw Exception("Folder already exists");
    }
    await folder.rename(newPath);
  }

  // Delete folder
  static Future<void> deleteFolder(Directory folder) async {
    await folder.delete(recursive: true);
  }

  // Rename file
  static Future<void> renameFile(File file, String newName) async {
    final newPath = '${file.parent.path}/$newName';
    final newFile = File(newPath);
    if (await newFile.exists()) {
      throw Exception("File already exists");
    }
    await file.rename(newPath);
  }

  // Delete file
  static Future<void> deleteFile(File file) async {
    await file.delete();
  }
}

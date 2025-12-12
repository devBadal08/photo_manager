import 'dart:io';

class FolderStatService {
  static Future<Map<String, int>> getFolderStats(Directory folder) async {
    int subfolders = 0;
    int images = 0;
    int videos = 0;
    int pdfs = 0;

    final entities = folder.listSync();

    for (var entity in entities) {
      if (entity is Directory) {
        subfolders++;

        final subFiles = entity.listSync();
        for (var file in subFiles) {
          if (file is File) {
            final path = file.path.toLowerCase();
            if (path.endsWith('.jpg') ||
                path.endsWith('.jpeg') ||
                path.endsWith('.png')) {
              images++;
            } else if (path.endsWith('.mp4')) {
              videos++;
            } else if (path.endsWith('.pdf')) {
              pdfs++;
            }
          }
        }
      } else if (entity is File) {
        final path = entity.path.toLowerCase();
        if (path.endsWith('.jpg') ||
            path.endsWith('.jpeg') ||
            path.endsWith('.png')) {
          images++;
        } else if (path.endsWith('.mp4')) {
          videos++;
        } else if (path.endsWith('.pdf')) {
          pdfs++;
        }
      }
    }

    return {
      'subfolders': subfolders,
      'images': images,
      'videos': videos,
      'pdfs': pdfs,
    };
  }
}

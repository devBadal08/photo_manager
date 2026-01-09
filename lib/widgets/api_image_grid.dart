import 'dart:io';
import 'package:flutter/material.dart';
import 'package:photomanager_practice/widgets/video_thumb_widget.dart';
import 'package:photomanager_practice/services/photo_service.dart';
import 'package:photomanager_practice/screen/gallery_screen.dart';
import 'package:photomanager_practice/screen/pdf_viewer_screen.dart';
import 'package:photomanager_practice/screen/video_network_player_screen.dart';
import 'package:photomanager_practice/screen/video_player_screen.dart';

class ApiImageGrid extends StatelessWidget {
  final List<Map<String, dynamic>> photos;
  final Set<String> uploadedSet;
  final bool selectionMode;
  final List<String> selectedImages;
  final Function(String) onToggleSelect;
  final int? sharedFolderId;

  const ApiImageGrid({
    super.key,
    required this.photos,
    required this.uploadedSet,
    required this.selectionMode,
    required this.selectedImages,
    required this.onToggleSelect,
    this.sharedFolderId,
  });

  @override
  Widget build(BuildContext context) {
    // Filter duplicates: prefer local version
    final unique = <String, Map<String, dynamic>>{};
    for (var p in photos) {
      final filename = p['path'].split('/').last.toLowerCase();
      if (!unique.containsKey(filename) || p['local'] == true) {
        unique[filename] = p;
      }
    }
    final finalList = unique.values.toList();

    return GridView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: finalList.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 4,
        mainAxisSpacing: 4,
      ),
      itemBuilder: (context, index) {
        final photo = finalList[index];
        final localPath = photo['path'];
        final filename = localPath.split('/').last;
        final extension = filename.split('.').last.toLowerCase();

        final isPdf = extension == 'pdf';
        final isVideo = PhotoService.isVideoFileType(localPath);
        final isLocal = photo['local'] == true;
        final serverUrl = "https://techstrota.cloud/storage/${photo['path']}";
        final existsLocally = File(localPath).existsSync();
        final isSelected = selectedImages.contains(localPath);
        final isUploaded = uploadedSet.any((p) => p.endsWith(filename));

        return GestureDetector(
          onLongPress: () => onToggleSelect(localPath),
          onTap: () {
            if (selectionMode) {
              onToggleSelect(localPath);
              return;
            }

            if (isPdf) {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => PdfViewerScreen(
                    pdfFile: isLocal ? File(localPath) : serverUrl,
                    sharedFolderId: sharedFolderId,
                  ),
                ),
              );
            } else if (isVideo) {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => isLocal
                      ? VideoPlayerScreen(videoFile: File(localPath))
                      : VideoNetworkPlayerScreen(videoUrl: serverUrl),
                ),
              );
            } else {
              final imgs = finalList.map((p) {
                return p['local'] == true
                    ? p['path']
                    : "https://techstrota.cloud/storage/${p['path']}";
              }).toList();

              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      GalleryScreen(images: imgs, startIndex: index),
                ),
              );
            }
          },
          child: Stack(
            children: [
              Positioned.fill(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: isPdf
                      ? Container(
                          color: Colors.grey[200],
                          child: Center(
                            child: Icon(
                              Icons.picture_as_pdf,
                              size: 40,
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        )
                      : isVideo
                      ? (isLocal && existsLocally
                            ? VideoThumbWidget(
                                videoPath: localPath,
                              ) // local => thumbnail OK
                            : Container(
                                color: Colors
                                    .black54, // server => placeholder only
                                child: const Center(
                                  child: Icon(
                                    Icons.play_circle_fill,
                                    size: 40,
                                    color: Colors.white,
                                  ),
                                ),
                              ))
                      : existsLocally
                      ? Image.file(File(localPath), fit: BoxFit.cover)
                      : Image.network(serverUrl, fit: BoxFit.cover),
                ),
              ),

              if (selectionMode)
                Positioned(
                  top: 6,
                  left: 6,
                  child: Checkbox(
                    value: isSelected,
                    onChanged: (_) => onToggleSelect(localPath),
                  ),
                ),

              if (isUploaded)
                const Positioned(
                  right: 6,
                  top: 6,
                  child: CircleAvatar(
                    radius: 10,
                    backgroundColor: Colors.green,
                    child: Icon(Icons.check, size: 16, color: Colors.white),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

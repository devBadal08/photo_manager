import 'dart:io';
import 'package:flutter/material.dart';
import 'package:photomanager_practice/widgets/video_thumb_widget.dart';
import 'package:photomanager_practice/services/photo_service.dart';
import 'package:photomanager_practice/screen/pdf_viewer_screen.dart';
import 'package:photomanager_practice/screen/gallery_screen.dart';

class ImageGrid extends StatelessWidget {
  final List<File> files;
  final bool selectionMode;
  final List<String> selectedImages;
  final ValueNotifier<Set<String>> uploadedSet;
  final Function(String) onToggleSelect;
  final Function(String) onEnterSelectionMode;

  const ImageGrid({
    super.key,
    required this.files,
    required this.selectionMode,
    required this.selectedImages,
    required this.uploadedSet,
    required this.onToggleSelect,
    required this.onEnterSelectionMode,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Set<String>>(
      valueListenable: uploadedSet,
      builder: (context, uploaded, _) {
        return GridView.builder(
          padding: const EdgeInsets.all(8),
          itemCount: files.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            crossAxisSpacing: 4,
            mainAxisSpacing: 4,
          ),
          itemBuilder: (context, index) {
            final file = files[index];
            final filePath = file.path;
            final isSelected = selectedImages.contains(filePath);
            final isUploaded = uploaded.contains(filePath);

            final extension = filePath.split('.').last.toLowerCase();
            final isPdf = extension == 'pdf';
            final isVideo = PhotoService.isVideoFileType(filePath);

            return GestureDetector(
              onLongPress: () {
                if (!selectionMode) {
                  onEnterSelectionMode(filePath);
                }
              },
              onTap: () {
                if (selectionMode) {
                  onToggleSelect(filePath);
                } else {
                  if (isPdf) {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => PdfViewerScreen(pdfFile: file),
                      ),
                    );
                  } else {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            GalleryScreen(images: files, startIndex: index),
                      ),
                    );
                  }
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
                          ? VideoThumbWidget(videoPath: filePath)
                          : Image.file(
                              file,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) =>
                                  const Icon(Icons.broken_image),
                            ),
                    ),
                  ),

                  if (selectionMode)
                    Positioned(
                      top: 6,
                      left: 6,
                      child: Checkbox(
                        value: isSelected,
                        onChanged: (_) => onToggleSelect(filePath),
                      ),
                    ),

                  if (isUploaded)
                    Positioned(
                      right: 6,
                      top: 6,
                      child: Container(
                        decoration: const BoxDecoration(
                          color: Colors.green,
                          shape: BoxShape.circle,
                        ),
                        padding: const EdgeInsets.all(4),
                        child: const Icon(
                          Icons.check,
                          color: Colors.white,
                          size: 18,
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

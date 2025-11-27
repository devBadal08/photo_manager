import 'dart:io';
import 'package:flutter/material.dart';
import 'package:photomanager_practice/screen/image_editor_screen.dart';
import 'package:photomanager_practice/screen/photo_list_screen.dart';
import 'package:video_player/video_player.dart'; // 👈 for video playback

class GalleryScreen extends StatefulWidget {
  final List<File> images;

  const GalleryScreen({
    super.key,
    required this.images,
    required int startIndex,
  });

  @override
  State<GalleryScreen> createState() => _GalleryScreenState();
}

class _GalleryScreenState extends State<GalleryScreen> {
  late List<File> images;

  bool isVideo(File file) {
    final ext = file.path.toLowerCase().split(".").last;
    return ["mp4"].contains(ext);
  }

  @override
  void initState() {
    super.initState();
    images = widget.images.where((file) {
      final ext = file.path.toLowerCase().split('.').last;
      return ["jpg", "jpeg", "png", "mp4"].contains(ext);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Gallery")),
      body: GridView.builder(
        padding: const EdgeInsets.all(8),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          crossAxisSpacing: 4,
          mainAxisSpacing: 4,
        ),
        itemCount: images.length,
        itemBuilder: (context, index) {
          final file = images[index];

          return GestureDetector(
            onTap: () async {
              if (isVideo(file)) {
                // 👉 Open video player instead of ImageEditor
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => VideoPlayerScreen(videoFile: file),
                  ),
                );
              } else {
                final imageFilesOnly = images
                    .where((f) => !isVideo(f))
                    .toList();
                // 👉 Open image editor for photos
                final editedResult =
                    await Navigator.push<Map<String, dynamic>?>(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ImageEditorScreen(
                          images: imageFilesOnly,
                          initialIndex: index,
                        ),
                      ),
                    );

                if (editedResult != null &&
                    editedResult["index"] != null &&
                    editedResult["file"] != null) {
                  setState(() {
                    images[editedResult["index"]] = editedResult["file"];
                  });
                }
              }
            },
            child: isVideo(file)
                ? VideoThumbWidget(videoPath: file.path)
                : Image.file(
                    file,
                    fit: BoxFit.cover,
                    cacheWidth: 300,
                    cacheHeight: 300,
                    errorBuilder: (_, __, ___) =>
                        const Icon(Icons.broken_image, size: 50),
                  ),
          );
        },
      ),
    );
  }
}

/// ==================== VideoPlayerScreen ====================
class VideoPlayerScreen extends StatefulWidget {
  final File videoFile;
  const VideoPlayerScreen({super.key, required this.videoFile});

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  late VideoPlayerController _controller;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.file(widget.videoFile)
      ..initialize().then((_) {
        setState(() {});
        _controller.play();
      });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Video")),
      body: Center(
        child: _controller.value.isInitialized
            ? AspectRatio(
                aspectRatio: _controller.value.aspectRatio,
                child: VideoPlayer(_controller),
              )
            : const CircularProgressIndicator(),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          setState(() {
            _controller.value.isPlaying
                ? _controller.pause()
                : _controller.play();
          });
        },
        child: Icon(
          _controller.value.isPlaying ? Icons.pause : Icons.play_arrow,
        ),
      ),
    );
  }
}

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:photomanager_practice/screen/image_editor_screen.dart';
import 'package:photomanager_practice/screen/photo_list_screen.dart';
import 'package:video_player/video_player.dart'; // 👈 for video playback

class GalleryScreen extends StatefulWidget {
  final List<dynamic> images;

  const GalleryScreen({
    super.key,
    required this.images,
    required int startIndex,
  });

  @override
  State<GalleryScreen> createState() => _GalleryScreenState();
}

class _GalleryScreenState extends State<GalleryScreen> {
  late List<dynamic> images;

  bool isVideo(dynamic item) {
    if (item is File) {
      return item.path.toLowerCase().endsWith('.mp4');
    }
    if (item is String) {
      return item.toLowerCase().endsWith('.mp4');
    }
    return false;
  }

  @override
  void initState() {
    super.initState();
    images = widget.images.where((item) {
      final path = item is File ? item.path : item.toString();
      final ext = path.toLowerCase().split('.').last;
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
          final item = images[index];
          final path = item is File ? item.path : item.toString();

          return GestureDetector(
            onTap: () async {
              if (isVideo(item)) {
                if (item is File) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => VideoPlayerScreen(videoFile: item),
                    ),
                  );
                } else {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => VideoNetworkPlayerScreen(videoUrl: path),
                    ),
                  );
                }
              } else {
                final imageFilesOnly = images
                    .where((f) => !isVideo(f))
                    .toList();

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

            child: isVideo(item)
                ? (item is File
                      // ✅ LOCAL VIDEO
                      ? VideoThumbWidget(videoPath: item.path)
                      // ✅ SERVER VIDEO (NO THUMB, just play icon)
                      : Container(
                          color: Colors.black54,
                          child: const Center(
                            child: Icon(
                              Icons.play_circle_fill,
                              size: 50,
                              color: Colors.white,
                            ),
                          ),
                        ))
                : (item is File
                      // ✅ LOCAL IMAGE
                      ? Image.file(
                          item,
                          fit: BoxFit.cover,
                          cacheWidth: 300,
                          cacheHeight: 300,
                        )
                      // ✅ SERVER IMAGE
                      : Image.network(path, fit: BoxFit.cover)),
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

class VideoNetworkPlayerScreen extends StatefulWidget {
  final String videoUrl;
  const VideoNetworkPlayerScreen({super.key, required this.videoUrl});

  @override
  State<VideoNetworkPlayerScreen> createState() =>
      _VideoNetworkPlayerScreenState();
}

class _VideoNetworkPlayerScreenState extends State<VideoNetworkPlayerScreen> {
  late VideoPlayerController _controller;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.videoUrl))
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
    );
  }
}

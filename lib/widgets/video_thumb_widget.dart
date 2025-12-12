import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:video_thumbnail/video_thumbnail.dart' as vt;
import 'package:video_player/video_player.dart';

class VideoThumbWidget extends StatelessWidget {
  final String videoPath;

  const VideoThumbWidget({super.key, required this.videoPath});

  Future<Uint8List?> _getThumb() async {
    return await vt.VideoThumbnail.thumbnailData(
      video: videoPath,
      imageFormat: vt.ImageFormat.JPEG,
      maxWidth: 300,
      quality: 65,
    );
  }

  Future<String> _getDuration() async {
    late VideoPlayerController controller;

    if (videoPath.startsWith('http')) {
      controller = VideoPlayerController.network(videoPath);
    } else {
      controller = VideoPlayerController.file(File(videoPath));
    }

    await controller.initialize();
    final duration = controller.value.duration;
    controller.dispose();

    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');

    if (duration.inHours > 0) {
      return "${duration.inHours.toString().padLeft(2, '0')}:$minutes:$seconds";
    }

    return "$minutes:$seconds";
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: Future.wait([_getThumb(), _getDuration()]),
      builder: (context, AsyncSnapshot<List<dynamic>> snap) {
        if (!snap.hasData) {
          return Container(color: Colors.black26);
        }

        final Uint8List imageData = snap.data![0];
        final String duration = snap.data![1];

        return Stack(
          fit: StackFit.expand,
          children: [
            Image.memory(imageData, fit: BoxFit.cover),
            const Center(
              child: Icon(
                Icons.play_circle_fill,
                color: Colors.white,
                size: 40,
              ),
            ),
            Positioned(
              bottom: 6,
              right: 6,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.75),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  duration,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

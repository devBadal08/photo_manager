import 'dart:io';
import 'package:flutter/material.dart';
import 'package:photomanager_practice/screen/image_editor_screen.dart';

class GalleryScreen extends StatefulWidget {
  final List<File> images;

  const GalleryScreen({super.key, required this.images});

  @override
  State<GalleryScreen> createState() => _GalleryScreenState();
}

class _GalleryScreenState extends State<GalleryScreen> {
  late List<File> images;

  @override
  void initState() {
    super.initState();
    images = List<File>.from(widget.images); // mutable copy
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
          final rawPath = images[index].path;
          final cleanPath = rawPath.split('?')[0];
          final file = File(cleanPath);

          return GestureDetector(
            onTap: () async {
              final updatedImages = await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ImageEditorScreen(images: [file]),
                ),
              );

              if (updatedImages != null && updatedImages is List<File>) {
                setState(() {
                  images[index] =
                      updatedImages[0]; // update only the edited image
                });
              }
            },
            child: file.existsSync()
                ? Image.file(file, fit: BoxFit.cover)
                : const Icon(Icons.broken_image),
          );
        },
      ),
    );
  }
}

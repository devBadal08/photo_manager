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
          final file = images[index];

          return GestureDetector(
            onTap: () async {
              final editedResult = await Navigator.push<Map<String, dynamic>?>(
                context,
                MaterialPageRoute(
                  builder: (_) => ImageEditorScreen(
                    images: images, // pass ALL images
                    initialIndex: index, // start from tapped image
                  ),
                ),
              );

              // Expect result like: { "index": i, "file": editedFile }
              if (editedResult != null &&
                  editedResult["index"] != null &&
                  editedResult["file"] != null) {
                setState(() {
                  images[editedResult["index"]] = editedResult["file"];
                });
              }
            },
            child: Image.file(
              file,
              fit: BoxFit.cover,
              cacheWidth: 300,
              cacheHeight: 300,
              errorBuilder: (_, __, ___) => const Icon(Icons.broken_image),
            ),
          );
        },
      ),
    );
  }
}

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_cropper/image_cropper.dart';

class ImageEditorScreen extends StatefulWidget {
  final List<File> images; // Multiple images to edit

  const ImageEditorScreen({super.key, required this.images});

  @override
  State<ImageEditorScreen> createState() => _ImageEditorScreenState();
}

class _ImageEditorScreenState extends State<ImageEditorScreen> {
  late List<File> images;
  late PageController _pageController;
  List<File?> previewFiles = [];
  int currentIndex = 0; // track current page

  @override
  void initState() {
    super.initState();
    images = List<File>.from(widget.images);
    previewFiles = List<File?>.filled(images.length, null);
    _pageController = PageController();
  }

  Future<void> _cropImage(int index) async {
    final cropped = await ImageCropper().cropImage(
      sourcePath: previewFiles[index]?.path ?? images[index].path,
      compressFormat: ImageCompressFormat.jpg,
      compressQuality: 100,
      uiSettings: [
        AndroidUiSettings(
          toolbarTitle: 'Crop Image',
          toolbarColor: Theme.of(context).colorScheme.primary,
          toolbarWidgetColor: Colors.white,
          initAspectRatio: CropAspectRatioPreset.original,
          lockAspectRatio: false,
          aspectRatioPresets: [
            CropAspectRatioPreset.square,
            CropAspectRatioPreset.original,
            CropAspectRatioPreset.ratio16x9,
          ],
        ),
        IOSUiSettings(
          title: 'Crop Image',
          aspectRatioPresets: [
            CropAspectRatioPreset.square,
            CropAspectRatioPreset.original,
            CropAspectRatioPreset.ratio16x9,
          ],
        ),
      ],
    );

    if (cropped != null) {
      setState(() {
        previewFiles[index] = File(cropped.path);
      });
    }
  }

  Future<void> _saveImage(int index) async {
    final fileToSave = previewFiles[index];
    if (fileToSave != null) {
      await images[index].writeAsBytes(await fileToSave.readAsBytes());

      // Clear Flutter's image cache
      imageCache.clear();
      imageCache.clearLiveImages();

      previewFiles[index] = null;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Image saved successfully")));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Edit Images")),
      body: Stack(
        children: [
          PageView.builder(
            controller: _pageController,
            itemCount: images.length,
            physics: const BouncingScrollPhysics(),
            onPageChanged: (index) {
              setState(() {
                currentIndex = index; // update current page
              });
            },
            itemBuilder: (context, index) {
              final displayedImage = previewFiles[index] ?? images[index];
              return Center(
                child: Image.file(
                  displayedImage,
                  fit: BoxFit.contain,
                  width: double.infinity,
                  height: double.infinity,
                ),
              );
            },
          ),
          Positioned(
            bottom: 30,
            left: 0,
            right: 0,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ElevatedButton.icon(
                      icon: const Icon(Icons.crop),
                      label: const Text("Crop"),
                      onPressed: () => _cropImage(currentIndex),
                    ),
                    const SizedBox(width: 20),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.save),
                      label: const Text("Save"),
                      onPressed: () => _saveImage(currentIndex),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  "${currentIndex + 1} / ${images.length}",
                  style: const TextStyle(color: Colors.white),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

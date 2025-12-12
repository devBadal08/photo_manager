import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_cropper/image_cropper.dart';

class ImageEditorScreen extends StatefulWidget {
  final List<dynamic> images;
  final int initialIndex;

  const ImageEditorScreen({
    super.key,
    required this.images,
    this.initialIndex = 0,
  });

  @override
  State<ImageEditorScreen> createState() => _ImageEditorScreenState();
}

class _ImageEditorScreenState extends State<ImageEditorScreen>
    with TickerProviderStateMixin {
  late List<dynamic> images;
  late PageController _pageController;
  List<File?> previewFiles = [];
  int currentIndex = 0;

  @override
  void initState() {
    super.initState();
    images = widget.images.map((item) {
      if (item is File) return item;
      if (item is String && item.startsWith('http')) return item; // keep URL
      return File(item);
    }).toList();

    previewFiles = List<File?>.filled(images.length, null);
    _pageController = PageController(initialPage: widget.initialIndex);
    currentIndex = widget.initialIndex;
  }

  void _animateTransformation(
    TransformationController controller,
    Matrix4 target,
  ) {
    final AnimationController animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );

    final animation = Matrix4Tween(begin: controller.value, end: target)
        .animate(
          CurvedAnimation(parent: animationController, curve: Curves.easeInOut),
        );

    animation.addListener(() {
      controller.value = animation.value;
    });

    animationController.forward();
  }

  Future<void> _cropImage(int index) async {
    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;

    final cropped = await ImageCropper().cropImage(
      sourcePath: previewFiles[index]?.path ?? images[index].path,
      compressFormat: ImageCompressFormat.jpg,
      compressQuality: 100,
      uiSettings: [
        AndroidUiSettings(
          toolbarTitle: 'Crop Image',
          toolbarColor: isDarkMode ? Colors.black : Colors.white,
          toolbarWidgetColor: isDarkMode ? Colors.white : Colors.black,
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
      imageCache.clear();
      imageCache.clearLiveImages();
      previewFiles[index] = null;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text("Image saved successfully"),
          backgroundColor: Theme.of(context).colorScheme.primary,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text("Edit Images"),
        backgroundColor:
            theme.appBarTheme.backgroundColor ?? theme.colorScheme.surface,
        foregroundColor:
            theme.appBarTheme.foregroundColor ?? theme.colorScheme.onSurface,
      ),
      body: Stack(
        children: [
          PageView.builder(
            controller: _pageController,
            itemCount: images.length,
            physics: const PageScrollPhysics(),
            onPageChanged: (index) {
              setState(() {
                currentIndex = index;
              });
            },
            itemBuilder: (context, index) {
              final displayedImage = previewFiles[index] ?? images[index];
              final TransformationController controller =
                  TransformationController();

              return GestureDetector(
                onDoubleTapDown: (details) {
                  final tapPosition = details.localPosition;

                  setState(() {
                    if (controller.value != Matrix4.identity()) {
                      _animateTransformation(controller, Matrix4.identity());
                    } else {
                      final zoom = 2.5;
                      final x = -tapPosition.dx * (zoom - 1);
                      final y = -tapPosition.dy * (zoom - 1);

                      final zoomed = Matrix4.identity()
                        ..translate(x, y)
                        ..scale(zoom);

                      _animateTransformation(controller, zoomed);
                    }
                  });
                },
                child: InteractiveViewer(
                  transformationController: controller,
                  panEnabled: true,
                  minScale: 1.0,
                  maxScale: 4.0,
                  child: _buildImage(displayedImage),
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
                      style: ElevatedButton.styleFrom(
                        backgroundColor: theme.colorScheme.primary,
                        foregroundColor: theme.colorScheme.onPrimary,
                      ),
                      onPressed: () => _cropImage(currentIndex),
                    ),
                    const SizedBox(width: 20),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.save),
                      label: const Text("Save"),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: theme.colorScheme.secondary,
                        foregroundColor: theme.colorScheme.onSecondary,
                      ),
                      onPressed: () => _saveImage(currentIndex),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  "${currentIndex + 1} / ${images.length}",
                  style: TextStyle(color: theme.colorScheme.onBackground),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImage(dynamic img) {
    if (img is File) {
      return Image.file(img, fit: BoxFit.contain);
    } else if (img is String && img.startsWith('http')) {
      return Image.network(img, fit: BoxFit.contain);
    } else if (img is String) {
      return Image.file(File(img), fit: BoxFit.contain);
    } else {
      return const Text("Invalid image");
    }
  }
}

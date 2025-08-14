import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

class DefaultCameraScreen extends StatefulWidget {
  final Directory saveFolder; // where to save images
  final List<CameraDescription> cameras;
  const DefaultCameraScreen({
    super.key,
    required this.saveFolder,
    required this.cameras,
  });

  @override
  State<DefaultCameraScreen> createState() => _DefaultCameraScreenState();
}

class _DefaultCameraScreenState extends State<DefaultCameraScreen> {
  late CameraController _controller;
  bool _isCameraInitialized = false;
  int _currentCameraIndex = 0;
  List<File> capturedImages = [];
  bool _isCapturing = false;
  List<CameraDescription> cameras = [];

  @override
  void initState() {
    super.initState();
    initCamera();
  }

  Future<void> initCamera() async {
    cameras = await availableCameras();
    if (cameras.isNotEmpty) {
      _controller = CameraController(
        cameras.first,
        ResolutionPreset.max,
        enableAudio: false,
      );
      await _controller.initialize();
      if (!mounted) return;
      setState(() {
        _isCameraInitialized = true;
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _capturePhoto() async {
    if (!_controller.value.isInitialized || _isCapturing) return;

    setState(() => _isCapturing = true);

    try {
      final image = await _controller.takePicture();

      final String newPath =
          '${widget.saveFolder.path}/${DateTime.now().millisecondsSinceEpoch}.jpg';
      await File(image.path).copy(newPath);

      setState(() {
        capturedImages.add(File(newPath));
      });
    } catch (e) {
      debugPrint("Error capturing photo: $e");
    } finally {
      setState(() => _isCapturing = false);
    }
  }

  void _switchCamera() {
    _currentCameraIndex = (_currentCameraIndex + 1) % widget.cameras.length;
    initCamera();
  }

  void _openFullScreenImage(File imageFile) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FullScreenImageView(imageFile: imageFile),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: _isCameraInitialized
          ? Stack(
              children: [
                // Camera preview with correct aspect ratio & fullscreen crop
                Positioned.fill(
                  child: _controller.value.isInitialized
                      ? FittedBox(
                          fit: BoxFit.cover, // fills screen without stretching
                          child: SizedBox(
                            width: _controller.value.previewSize!.height,
                            height: _controller.value.previewSize!.width,
                            child: CameraPreview(_controller),
                          ),
                        )
                      : const Center(child: CircularProgressIndicator()),
                ),
                Align(
                  alignment: Alignment.bottomCenter,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      vertical: 12,
                      horizontal: 24,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surface.withOpacity(0.3),
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(20),
                        topRight: Radius.circular(20),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        // Thumbnail preview clickable
                        if (capturedImages.isNotEmpty)
                          GestureDetector(
                            onTap: () =>
                                _openFullScreenImage(capturedImages.last),
                            child: ClipOval(
                              child: Image.file(
                                capturedImages.last,
                                width: 50,
                                height: 50,
                                fit: BoxFit.cover,
                              ),
                            ),
                          )
                        else
                          const SizedBox(width: 50),

                        // Capture button
                        GestureDetector(
                          onTap: _isCapturing ? null : _capturePhoto,
                          child: Container(
                            width: 65,
                            height: 65,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: theme.colorScheme.onSurface,
                                width: 4,
                              ),
                              color: _isCapturing
                                  ? Colors.grey.withOpacity(
                                      0.5,
                                    ) // show disabled state
                                  : theme.colorScheme.onSurface.withOpacity(
                                      0.2,
                                    ),
                            ),
                          ),
                        ),
                        // Switch camera button
                        IconButton(
                          icon: Icon(
                            Icons.cameraswitch,
                            color: theme.iconTheme.color,
                            size: 32,
                          ),
                          onPressed: _switchCamera,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            )
          : const Center(child: CircularProgressIndicator()),
    );
  }
}

class FullScreenImageView extends StatelessWidget {
  final File imageFile;
  const FullScreenImageView({super.key, required this.imageFile});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: theme.appBarTheme.backgroundColor,
        iconTheme: theme.appBarTheme.iconTheme,
      ),
      body: Center(child: Image.file(imageFile, fit: BoxFit.contain)),
    );
  }
}

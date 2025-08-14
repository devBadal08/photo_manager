import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

class CustomCameraScreen extends StatefulWidget {
  final Directory saveFolder; // where to save images
  final List<CameraDescription> cameras;
  const CustomCameraScreen({
    super.key,
    required this.saveFolder,
    required this.cameras,
  });

  @override
  State<CustomCameraScreen> createState() => _CustomCameraScreenState();
}

class _CustomCameraScreenState extends State<CustomCameraScreen> {
  late CameraController _controller;
  bool _isCameraInitialized = false;
  int _currentCameraIndex = 0;
  List<File> capturedImages = [];
  bool _isCapturing = false;

  @override
  void initState() {
    super.initState();
    _initCamera(widget.cameras[_currentCameraIndex]);
  }

  void _initCamera(CameraDescription cameraDescription) async {
    // Use highest available resolution
    _controller = CameraController(
      cameraDescription,
      ResolutionPreset.max, // instead of medium
      imageFormatGroup: ImageFormatGroup.jpeg, // better compatibility & quality
    );

    await _controller.initialize();

    // Optional: lock focus & exposure for better sharpness
    try {
      await _controller.setFocusMode(FocusMode.auto);
      await _controller.setExposureMode(ExposureMode.auto);
    } catch (e) {
      debugPrint("Focus/Exposure control not supported: $e");
    }

    setState(() => _isCameraInitialized = true);
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
    _initCamera(widget.cameras[_currentCameraIndex]);
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
                Positioned.fill(child: CameraPreview(_controller)),

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

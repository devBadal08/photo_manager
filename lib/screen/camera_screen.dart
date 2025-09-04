import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:photomanager_practice/services/folder_share_service.dart';

class CameraScreen extends StatefulWidget {
  final Directory? saveFolder; // where to save images
  final int? sharedFolderId; // shared folder ID
  final List<CameraDescription> cameras;
  const CameraScreen({
    super.key,
    this.saveFolder,
    this.sharedFolderId,
    required this.cameras,
  });

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  late CameraController _controller;
  bool _isCameraInitialized = false;
  int _currentCameraIndex = 0;
  List<File> capturedImages = [];
  bool _isCapturing = false;
  List<CameraDescription> cameras = [];
  double _thumbnailScale = 1.0;

  @override
  void initState() {
    super.initState();
    initCamera();
  }

  Future<void> initCamera() async {
    cameras = await availableCameras();
    if (cameras.isNotEmpty) {
      _controller = CameraController(
        cameras[_currentCameraIndex],
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

  FlashMode _flashMode = FlashMode.off;

  Future<void> _toggleFlash() async {
    if (_flashMode == FlashMode.off) {
      _flashMode = FlashMode.torch;
    } else {
      _flashMode = FlashMode.off;
    }
    await _controller.setFlashMode(_flashMode);
    setState(() {});
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

      if (widget.saveFolder != null) {
        // 📂 Local folder mode
        final newPath =
            '${widget.saveFolder!.path}/${DateTime.now().millisecondsSinceEpoch}.jpg';
        await File(image.path).copy(newPath);

        setState(() {
          capturedImages.add(File(newPath));
        });
      } else if (widget.sharedFolderId != null) {
        // 📂 Shared folder mode (store locally just like normal folders)
        final dir = Directory(
          '/storage/emulated/0/Pictures/MyApp/Shared/${widget.sharedFolderId}',
        );
        if (!await dir.exists()) {
          await dir.create(recursive: true);
        }

        final newPath =
            '${dir.path}/${DateTime.now().millisecondsSinceEpoch}.jpg';
        await File(image.path).copy(newPath);

        setState(() {
          capturedImages.add(File(newPath));
        });
      }
    } catch (e) {
      debugPrint("Error capturing photo: $e");
    } finally {
      setState(() => _isCapturing = false);
    }
  }

  void _switchCamera() async {
    if (cameras.length < 2) return; // no second camera available
    _currentCameraIndex = (_currentCameraIndex + 1) % cameras.length;

    await _controller.dispose(); // ✅ dispose old controller
    await initCamera(); // ✅ reinitialize with new camera
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

    return WillPopScope(
      onWillPop: () async {
        Navigator.pop(context, capturedImages.map((f) => f.path).toList());
        return false; // prevent default pop (we already did it)
      },
      child: Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        body: _isCameraInitialized
            ? Stack(
                children: [
                  // Camera preview with correct aspect ratio & fullscreen crop
                  Positioned.fill(
                    child: _controller.value.isInitialized
                        ? FittedBox(
                            fit:
                                BoxFit.cover, // fills screen without stretching
                            child: SizedBox(
                              width: _controller.value.previewSize!.height,
                              height: _controller.value.previewSize!.width,
                              child: CameraPreview(_controller),
                            ),
                          )
                        : const Center(child: CircularProgressIndicator()),
                  ),
                  // Flash mode toggle button
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: Container(
                      height: 100, // same height as bottom bar
                      color: Colors.black.withOpacity(0.5),
                      padding: EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 20,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          IconButton(
                            icon: Icon(
                              _flashMode == FlashMode.off
                                  ? Icons.flash_off
                                  : Icons.flash_on,
                              color: Colors.white,
                              size: 32,
                            ),
                            onPressed: _toggleFlash,
                          ),
                        ],
                      ),
                    ),
                  ),
                  // Bottom control bar
                  Align(
                    alignment: Alignment.bottomCenter,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        vertical: 25,
                        horizontal: 25,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.5),
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
                              onTapDown: (_) {
                                setState(() => _thumbnailScale = 0.9); // shrink
                              },
                              onTapUp: (_) async {
                                // Shrink already done in onTapDown
                                await Future.delayed(
                                  const Duration(milliseconds: 200),
                                ); // wait before zoom back
                                setState(() => _thumbnailScale = 1.0);
                                await Future.delayed(
                                  const Duration(milliseconds: 200),
                                ); // wait for zoom back
                                _openFullScreenImage(
                                  capturedImages.last,
                                ); // navigate AFTER animation
                              },
                              onTapCancel: () {
                                setState(() => _thumbnailScale = 1.0);
                              },
                              child: AnimatedScale(
                                scale: _thumbnailScale,
                                duration: const Duration(milliseconds: 200),
                                curve: Curves.easeInOut,
                                child: ClipOval(
                                  child: Image.file(
                                    capturedImages.last,
                                    width: 50,
                                    height: 50,
                                    fit: BoxFit.cover,
                                  ),
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
                                    : Colors.white,
                              ),
                            ),
                          ),
                          // Switch camera button
                          IconButton(
                            icon: Icon(
                              Icons.cameraswitch,
                              color: Colors.white,
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
      ),
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

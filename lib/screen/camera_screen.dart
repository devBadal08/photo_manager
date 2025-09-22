import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:photomanager_practice/services/folder_share_service.dart';
import 'package:photomanager_practice/services/photo_service.dart';

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
  bool _isVideoMode = false;
  bool _isRecording = false;

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
      final XFile image = await _controller.takePicture();
      File originalFile = File(image.path);

      // ✅ Compress before saving
      File compressedFile = await PhotoService.compressImage(originalFile);

      if (widget.saveFolder != null) {
        // 📂 Local folder mode
        final newPath =
            '${widget.saveFolder!.path}/${DateTime.now().millisecondsSinceEpoch}.jpg';
        await compressedFile.copy(newPath);

        setState(() {
          capturedImages.add(File(newPath));
        });
      } else if (widget.sharedFolderId != null) {
        // 📂 Shared folder mode
        final dir = Directory(
          '/storage/emulated/0/Pictures/MyApp/Shared/${widget.sharedFolderId}',
        );
        if (!await dir.exists()) {
          await dir.create(recursive: true);
        }

        final newPath =
            '${dir.path}/${DateTime.now().millisecondsSinceEpoch}.jpg';
        await compressedFile.copy(newPath);

        setState(() {
          capturedImages.add(File(newPath));
        });
      }

      // (optional) cleanup: delete the original uncompressed file
      //await originalFile.delete();
    } catch (e) {
      debugPrint("Error capturing photo: $e");
    } finally {
      setState(() => _isCapturing = false);
    }
  }

  Future<void> _startVideoRecording() async {
    if (!_controller.value.isInitialized || _isRecording) return;

    try {
      await _controller.startVideoRecording();
      setState(() => _isRecording = true);
    } catch (e) {
      debugPrint("Error starting video recording: $e");
    }
  }

  Future<void> _stopVideoRecording() async {
    if (!_controller.value.isInitialized || !_isRecording) return;

    try {
      final XFile videoFile = await _controller.stopVideoRecording();
      File savedVideo = File(videoFile.path);

      if (widget.saveFolder != null) {
        final newPath =
            '${widget.saveFolder!.path}/${DateTime.now().millisecondsSinceEpoch}.mp4';
        await savedVideo.copy(newPath);
      } else if (widget.sharedFolderId != null) {
        final dir = Directory(
          '/storage/emulated/0/Pictures/MyApp/Shared/${widget.sharedFolderId}',
        );
        if (!await dir.exists()) {
          await dir.create(recursive: true);
        }
        final newPath =
            '${dir.path}/${DateTime.now().millisecondsSinceEpoch}.mp4';
        await savedVideo.copy(newPath);
      }

      setState(() => _isRecording = false);
    } catch (e) {
      debugPrint("Error stopping video recording: $e");
    }
  }

  void _switchCamera() async {
    if (cameras.length < 2) return; // no second camera available
    _currentCameraIndex = (_currentCameraIndex + 1) % cameras.length;

    await _controller.dispose(); // ✅ dispose old controller
    await initCamera(); // ✅ reinitialize with new camera
  }

  void _openFullScreenImage(int initialIndex) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FullScreenGalleryView(
          images: capturedImages,
          initialIndex: initialIndex,
        ),
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
                                  capturedImages.length - 1,
                                ); // last image index
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

class FullScreenGalleryView extends StatefulWidget {
  final List<File> images;
  final int initialIndex;

  const FullScreenGalleryView({
    super.key,
    required this.images,
    this.initialIndex = 0,
  });

  @override
  State<FullScreenGalleryView> createState() => _FullScreenGalleryViewState();
}

class _FullScreenGalleryViewState extends State<FullScreenGalleryView> {
  late PageController _pageController;
  late int _currentIndex;
  TransformationController _transformationController =
      TransformationController();
  TapDownDetails? _doubleTapDetails;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: _currentIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    _transformationController.dispose();
    super.dispose();
  }

  void _handleDoubleTap(TapDownDetails details) {
    final position = details.localPosition;

    if (_transformationController.value != Matrix4.identity()) {
      _transformationController.value = Matrix4.identity();
    } else {
      _transformationController.value = Matrix4.identity()
        ..translate(-position.dx * 2, -position.dy * 2)
        ..scale(3.0); // adjust zoom level
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: theme.appBarTheme.backgroundColor,
        iconTheme: theme.appBarTheme.iconTheme,
        title: Text('${_currentIndex + 1}/${widget.images.length}'),
      ),
      body: PageView.builder(
        controller: _pageController,
        itemCount: widget.images.length,
        onPageChanged: (index) {
          setState(() => _currentIndex = index);
          _transformationController.value =
              Matrix4.identity(); // reset zoom on page change
        },
        itemBuilder: (_, index) {
          return Center(
            child: GestureDetector(
              onDoubleTapDown: (details) {
                _doubleTapDetails = details; // store tap position
              },
              onDoubleTap: () {
                if (_doubleTapDetails != null) {
                  _handleDoubleTap(_doubleTapDetails!);
                }
              },
              child: InteractiveViewer(
                transformationController: _transformationController,
                panEnabled: true,
                scaleEnabled: true,
                minScale: 1.0,
                maxScale: 5.0,
                child: Image.file(widget.images[index], fit: BoxFit.contain),
              ),
            ),
          );
        },
      ),
    );
  }
}

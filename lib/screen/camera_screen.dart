import 'dart:io';
import 'package:camera/camera.dart' hide ImageFormat;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:photomanager_practice/services/photo_service.dart';
import 'package:video_compress/video_compress.dart';
import 'package:video_player/video_player.dart';
import 'dart:math';
import 'package:sensors_plus/sensors_plus.dart';

enum MediaType { image, video }

class MediaFile {
  final File file;
  final MediaType type;
  MediaFile({required this.file, required this.type});
}

class CameraScreen extends StatefulWidget {
  final Directory? saveFolder;
  final int? sharedFolderId;
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
  List<MediaFile> capturedMedia = [];
  bool _isCapturing = false;
  bool _isVideoMode = false;
  bool _isRecording = false;
  FlashMode _flashMode = FlashMode.off;
  double _currentZoom = 1.0;
  double _baseZoom = 1.0;
  double _deviceRotation = 0;

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    initCamera();

    accelerometerEvents.listen((event) {
      double angle = atan2(event.y, event.x) * (180 / pi);

      // Normalize to 0, 90, 180, 270
      if (angle >= -45 && angle < 45) {
        _deviceRotation = 0; // Portrait Up
      } else if (angle >= 45 && angle < 135) {
        _deviceRotation = 270; // Landscape Left
      } else if (angle >= -135 && angle < -45) {
        _deviceRotation = 90; // Landscape Right
      } else {
        _deviceRotation = 180; // Portrait Down
      }
    });
  }

  Future<void> initCamera() async {
    final cameras = widget.cameras;
    if (cameras.isEmpty) return;

    _controller = CameraController(
      cameras[_currentCameraIndex],
      ResolutionPreset.max,
      enableAudio: true,
    );

    await _controller.initialize();
    await _controller.lockCaptureOrientation(DeviceOrientation.portraitUp);

    if (!mounted) return;
    setState(() => _isCameraInitialized = true);
  }

  Future<void> _toggleFlash() async {
    _flashMode = _flashMode == FlashMode.off ? FlashMode.torch : FlashMode.off;
    await _controller.setFlashMode(_flashMode);
    setState(() {});
  }

  Future<void> _capturePhoto() async {
    if (!_controller.value.isInitialized || _isCapturing) return;

    setState(() => _isCapturing = true);
    try {
      final XFile image = await _controller.takePicture();
      File compressedFile = await PhotoService.compressImage(File(image.path));

      final String newPath = widget.saveFolder != null
          ? '${widget.saveFolder!.path}/${DateTime.now().millisecondsSinceEpoch}.jpg'
          : '/storage/emulated/0/Pictures/MyApp/Shared/${widget.sharedFolderId}/${DateTime.now().millisecondsSinceEpoch}.jpg';

      final dir = File(newPath).parent;
      if (!await dir.exists()) await dir.create(recursive: true);
      await compressedFile.copy(newPath);

      // Delay briefly to ensure file is ready
      await Future.delayed(const Duration(milliseconds: 50));

      setState(() {
        capturedMedia.add(
          MediaFile(file: File(newPath), type: MediaType.image),
        );
      });
    } catch (e) {
      debugPrint("Error capturing photo: $e");
    } finally {
      setState(() => _isCapturing = false);
    }
  }

  Future<void> _startVideoRecording() async {
    if (!_controller.value.isInitialized || _isRecording) return;

    try {
      // Lock Flutter UI to portrait
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
      ]);

      // Lock camera orientation to portrait
      await _controller.lockCaptureOrientation(DeviceOrientation.portraitUp);

      // Prepare & start recording
      await _controller.prepareForVideoRecording();
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
      setState(() => _isRecording = false);

      // Compress and rotate video according to device orientation
      await _compressAndSaveVideo(videoFile);
    } catch (e) {
      debugPrint("Error stopping video recording: $e");
    }
  }

  Future<void> _compressAndSaveVideo(XFile videoFile) async {
    try {
      final MediaInfo? compressedVideo = await VideoCompress.compressVideo(
        videoFile.path,
        quality: VideoQuality.LowQuality,
        deleteOrigin: false,
        includeAudio: true,
        frameRate: 24,
        //rotate: _deviceRotation.toInt(), // <- automatic rotation
      );

      if (compressedVideo == null) return;

      final String newVideoPath = widget.saveFolder != null
          ? '${widget.saveFolder!.path}/${DateTime.now().millisecondsSinceEpoch}.mp4'
          : '/storage/emulated/0/Pictures/MyApp/Shared/${widget.sharedFolderId}/${DateTime.now().millisecondsSinceEpoch}.mp4';

      final dir = File(newVideoPath).parent;
      if (!await dir.exists()) await dir.create(recursive: true);

      await File(compressedVideo.path!).copy(newVideoPath);
      await Future.delayed(const Duration(milliseconds: 50));

      setState(() {
        capturedMedia.add(
          MediaFile(file: File(newVideoPath), type: MediaType.video),
        );
      });
    } catch (e) {
      debugPrint("Error compressing/saving video: $e");
    }
  }

  void _switchCamera() async {
    _currentCameraIndex = (_currentCameraIndex + 1) % widget.cameras.length;
    await _controller.dispose();
    await initCamera();
  }

  @override
  void dispose() {
    _controller.dispose();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    super.dispose();
  }

  void _returnCapturedMedia() {
    final paths = capturedMedia.map((m) => m.file.path).toList();
    Navigator.pop(context, paths); // returns captured paths to folder grid
  }

  @override
  Widget build(BuildContext context) {
    if (!_isCameraInitialized) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return WillPopScope(
      onWillPop: () async {
        // This is called when user presses the back button
        _returnCapturedMedia();
        return true; // allow pop
      },
      child: Scaffold(
        body: Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                onScaleStart: (details) {
                  _baseZoom = _currentZoom;
                },
                onScaleUpdate: (details) async {
                  if (_controller.value.isInitialized) {
                    final maxZoom = await _controller.getMaxZoomLevel();
                    final minZoom = await _controller.getMinZoomLevel();

                    double newZoom = (_baseZoom * details.scale).clamp(
                      minZoom,
                      maxZoom,
                    );

                    await _controller.setZoomLevel(newZoom);
                    setState(() => _currentZoom = newZoom);
                  }
                },
                child: FittedBox(
                  fit: BoxFit.cover,
                  child: SizedBox(
                    width: _controller.value.previewSize!.height,
                    height: _controller.value.previewSize!.width,
                    child: CameraPreview(_controller),
                  ),
                ),
              ),
            ),

            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.only(
                  top: 40,
                  right: 20,
                  left: 20,
                  bottom: 10,
                ),
                color: Colors.black.withOpacity(0.5),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    IconButton(
                      icon: Icon(
                        _flashMode == FlashMode.off
                            ? Icons.flash_off
                            : Icons.flash_on,
                        color: Colors.white,
                        size: 30,
                      ),
                      onPressed: _toggleFlash,
                    ),
                  ],
                ),
              ),
            ),
            Align(
              alignment: Alignment.bottomCenter,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  vertical: 15,
                  horizontal: 20,
                ),
                color: Colors.black.withOpacity(0.7),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Mode selector
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        GestureDetector(
                          onTap: () => setState(() => _isVideoMode = false),
                          child: Text(
                            "PHOTO",
                            style: TextStyle(
                              color: !_isVideoMode
                                  ? Colors.yellow
                                  : Colors.white70,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(width: 25),
                        GestureDetector(
                          onTap: () => setState(() => _isVideoMode = true),
                          child: Text(
                            "VIDEO",
                            style: TextStyle(
                              color: _isVideoMode
                                  ? Colors.yellow
                                  : Colors.white70,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // Thumbnail
                        if (capturedMedia.isNotEmpty)
                          GestureDetector(
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => FullScreenMediaView(
                                    media: capturedMedia,
                                    initialIndex: capturedMedia.length - 1,
                                  ),
                                ),
                              );
                            },
                            child: ClipOval(
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  Container(
                                    width: 45,
                                    height: 45,
                                    child:
                                        capturedMedia.last.type ==
                                            MediaType.image
                                        ? Image(
                                            key: ValueKey(
                                              capturedMedia.last.file.path,
                                            ),
                                            image: FileImage(
                                              capturedMedia.last.file,
                                            ),
                                            fit: BoxFit.cover,
                                          )
                                        : Container(
                                            color: Colors.black26,
                                            child: const Icon(
                                              Icons.videocam,
                                              color: Colors.white70,
                                            ),
                                          ),
                                  ),
                                  if (capturedMedia.last.type ==
                                      MediaType.video)
                                    const Icon(
                                      Icons.play_arrow,
                                      color: Colors.white,
                                    ),
                                ],
                              ),
                            ),
                          )
                        else
                          const SizedBox(width: 45, height: 45),

                        // Capture button
                        GestureDetector(
                          onTap: () async {
                            if (_isVideoMode) {
                              _isRecording
                                  ? await _stopVideoRecording()
                                  : await _startVideoRecording();
                            } else {
                              await _capturePhoto();
                            }
                          },
                          child: Container(
                            width: 70,
                            height: 70,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 4),
                              color: _isVideoMode
                                  ? (_isRecording ? Colors.red : Colors.white)
                                  : Colors.white,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(
                            Icons.cameraswitch,
                            color: Colors.white,
                          ),
                          iconSize: 35,
                          onPressed: _switchCamera,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// FullScreenMediaView remains the same as your previous code

// ==================== FullScreenMediaView ====================
class FullScreenMediaView extends StatefulWidget {
  final List<MediaFile> media;
  final int initialIndex;

  const FullScreenMediaView({
    super.key,
    required this.media,
    this.initialIndex = 0,
  });

  @override
  State<FullScreenMediaView> createState() => _FullScreenMediaViewState();
}

class _FullScreenMediaViewState extends State<FullScreenMediaView> {
  late PageController _pageController;
  late int _currentIndex;
  VideoPlayerController? _videoController;

  // Zoom related
  double _currentScale = 1.0;
  double _baseScale = 1.0;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: _currentIndex);
    _loadVideoController();
  }

  void _loadVideoController() {
    _videoController?.dispose();
    if (widget.media[_currentIndex].type == MediaType.video) {
      _videoController =
          VideoPlayerController.file(widget.media[_currentIndex].file)
            ..initialize().then((_) {
              setState(() {});
              _videoController!.play();
            });
    } else {
      _videoController = null;
    }
  }

  @override
  void dispose() {
    _videoController?.dispose();
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text('${_currentIndex + 1}/${widget.media.length}'),
      ),
      body: PageView.builder(
        controller: _pageController,
        itemCount: widget.media.length,
        onPageChanged: (index) {
          setState(() {
            _currentIndex = index;
            _currentScale = 1.0; // Reset scale when changing media
            _loadVideoController();
          });
        },
        itemBuilder: (_, index) {
          final media = widget.media[index];
          if (media.type == MediaType.image) {
            // Use InteractiveViewer for pinch-zoom
            return Center(
              child: InteractiveViewer(
                maxScale: 5.0,
                minScale: 1.0,
                child: Image.file(media.file, fit: BoxFit.contain),
              ),
            );
          } else {
            // Video pinch-zoom
            return GestureDetector(
              onScaleStart: (details) {
                _baseScale = _currentScale;
              },
              onScaleUpdate: (details) {
                setState(() {
                  _currentScale = (_baseScale * details.scale).clamp(1.0, 3.0);
                });
              },
              child: Center(
                child:
                    _videoController != null &&
                        _videoController!.value.isInitialized
                    ? Transform.scale(
                        scale: _currentScale,
                        child: AspectRatio(
                          aspectRatio: _videoController!.value.aspectRatio,
                          child: VideoPlayer(_videoController!),
                        ),
                      )
                    : const CircularProgressIndicator(),
              ),
            );
          }
        },
      ),
      floatingActionButton: _videoController != null
          ? FloatingActionButton(
              onPressed: () {
                setState(() {
                  _videoController!.value.isPlaying
                      ? _videoController!.pause()
                      : _videoController!.play();
                });
              },
              child: Icon(
                _videoController!.value.isPlaying
                    ? Icons.pause
                    : Icons.play_arrow,
              ),
            )
          : null,
    );
  }
}

// auto_upload_service.dart
import 'dart:async';
import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/src/widgets/framework.dart';
import 'package:path/path.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'photo_service.dart';
import 'bottom_tabs.dart';

class AutoUploadService {
  static final AutoUploadService _instance = AutoUploadService._internal();
  static AutoUploadService get instance => _instance;
  AutoUploadService._internal();

  bool _autoUploadEnabled = false;
  bool _isUploading = false; // prevent overlapping runs
  StreamSubscription<List<ConnectivityResult>>? _subscription;

  Future<void> init() async {
    _autoUploadEnabled = false; // always start as OFF

    // Listen to connectivity changes
    _subscription = Connectivity().onConnectivityChanged.listen((results) {
      if (!_autoUploadEnabled) return;
      final hasNet =
          results.contains(ConnectivityResult.wifi) ||
          results.contains(ConnectivityResult.mobile);
      if (hasNet) {
        _uploadPendingImages(); // private
      }
    });

    // Kick off once on startup if already connected
    final current = await Connectivity().checkConnectivity();
    if (_autoUploadEnabled &&
        (current == ConnectivityResult.wifi ||
            current == ConnectivityResult.mobile)) {
      _uploadPendingImages(); // private
    }
  }

  Future<void> setAutoUpload(bool enabled) async {
    _autoUploadEnabled = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool("auto_upload", enabled);

    if (enabled) {
      final current = await Connectivity().checkConnectivity();
      if (current == ConnectivityResult.wifi ||
          current == ConnectivityResult.mobile) {
        _uploadPendingImages(); // private
      }
    }
  }

  bool get isEnabled => _autoUploadEnabled;

  /// Public method you can call from anywhere (screens, after capture, etc.)
  Future<void> uploadNow() async {
    if (!_autoUploadEnabled) return;
    await _uploadPendingImages(); // private
  }

  // ----------------- PRIVATE -----------------
  Future<void> _uploadPendingImages() async {
    if (_isUploading) return; // debounce
    _isUploading = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getInt('user_id')?.toString();
      if (userId == null) return;

      final root = Directory('/storage/emulated/0/Pictures/MyApp/$userId');
      if (!await root.exists()) return;

      final files = root
          .listSync(recursive: true)
          .whereType<File>()
          .where(
            (f) =>
                f.path.endsWith(".jpg") ||
                f.path.endsWith(".jpeg") ||
                f.path.endsWith(".png"),
          )
          .toList();

      for (final file in files) {
        if (!PhotoService.uploadedFiles.value.contains(file.path)) {
          await PhotoService.uploadImagesToServer(null, silent: true);
          PhotoService.uploadedFiles.value = {
            ...PhotoService.uploadedFiles.value,
            file.path,
          };
        }
      }

      debugPrint("✅ Auto-upload completed");
    } catch (e) {
      debugPrint("❌ Auto-upload failed: $e");
    } finally {
      _isUploading = false;
    }
  }

  void dispose() {
    _subscription?.cancel();
  }
}

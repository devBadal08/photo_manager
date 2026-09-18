import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:photomanager_practice/screen/folder_screen.dart';
import 'package:photomanager_practice/screen/shared_with_me_screen.dart';
import 'package:photomanager_practice/services/auto_upload_service.dart';
import 'package:photomanager_practice/services/backup_service.dart';
import 'package:photomanager_practice/widgets/diceBearAvatar.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../screen/login_screen.dart';
import '../screen/user_profile_screen.dart';
import '../services/folder_service.dart';
import '../provider/theme_provider.dart';
import '../services/photo_service.dart';
import 'package:provider/provider.dart';
import 'package:path_provider/path_provider.dart';

class CustomDrawer extends StatefulWidget {
  final String userName;
  final File? avatarImage;
  final BuildContext parentContext; // FolderScreen context
  final VoidCallback? onDelete;

  const CustomDrawer({
    super.key,
    required this.userName,
    required this.avatarImage,
    required this.parentContext,
    this.onDelete,
  });

  @override
  State<CustomDrawer> createState() => _CustomDrawerState();
}

class _CustomDrawerState extends State<CustomDrawer> {
  bool _deleteEnabled = false;
  bool _autoUploadEnabled = false;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;

  String? _companyLogo;
  String? _avatarSeed;
  String? _userEmail;
  List<dynamic> _companies = [];
  int? _selectedCompanyId;
  String? _profilePhotoUrl;
  bool _hasSelfie = false;

  @override
  void initState() {
    super.initState();
    // restore saved toggle state
    _loadSettings();
    _loadCompanyLogo();
    _loadAvatarSeed();
    _loadUserEmail();
    _loadCompanies();
    _loadProfilePhoto();
  }

  Future<void> _loadUserEmail() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() => _userEmail = prefs.getString("email"));
  }

  Future<void> _loadCompanies() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = prefs.getString("companies");

    if (jsonList != null) {
      setState(() {
        _companies = List<dynamic>.from(jsonDecode(jsonList));
        _selectedCompanyId = prefs.getInt("selected_company_id");
      });
    }
  }

  Future<void> _loadProfilePhoto() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getString("user_id");

    if (userId == null) return;

    setState(() {
      _profilePhotoUrl = prefs.getString("profile_photo_$userId");
      _hasSelfie = prefs.getBool("has_selfie_$userId") ?? false;
    });
  }

  Future<void> _loadAvatarSeed() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getString("user_id");
    setState(() {
      if (userId != null) {
        _avatarSeed =
            prefs.getString("user_avatar_seed_$userId") ?? "defaultSeed";
      } else {
        _avatarSeed = "defaultSeed"; // fallback
      }
    });
  }

  Future<void> _saveAvatarSeed(String seed) async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getString("user_id");
    if (userId != null) {
      await prefs.setString("user_avatar_seed_$userId", seed);
      setState(() {
        _avatarSeed = seed;
      });
    }
  }

  Widget _buildDrawerHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
      child: Row(
        children: [
          GestureDetector(
            onTap: _openAvatarPicker,
            child: CircleAvatar(
              radius: 26,
              backgroundColor: Colors.grey.shade200,
              backgroundImage: (_hasSelfie && _profilePhotoUrl != null)
                  ? NetworkImage(_profilePhotoUrl!)
                  : null,
              child: (!_hasSelfie)
                  ? DiceBearAvatar(
                      seed: _avatarSeed ?? widget.userName,
                      size: 52,
                    )
                  : null,
            ),
          ),
          const SizedBox(width: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _userEmail ?? "",
                style: const TextStyle(fontSize: 14, color: Colors.grey),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCompanySelector() {
    if (_companies.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: DropdownButtonFormField<int>(
        value: _selectedCompanyId,
        decoration: InputDecoration(
          labelText: "Select Company",
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        ),
        items: _companies.map((company) {
          return DropdownMenuItem(
            value: company["id"] as int,
            child: Text(company["company_name"].toString()),
          );
        }).toList(),
        onChanged: (val) async {
          if (val == null) return;
          _selectedCompanyId = val;

          final prefs = await SharedPreferences.getInstance();
          prefs.setInt("selected_company_id", val);

          Navigator.pop(context);
          Navigator.pushReplacement(
            widget.parentContext,
            MaterialPageRoute(
              builder: (_) {
                return FolderScreen(userId: prefs.getString("user_id")!);
              },
            ),
          );
        },
      ),
    );
  }

  Widget drawerItem({
    required IconData icon,
    required String text,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Icon(icon, color: Colors.deepPurple),
      title: Text(text, style: const TextStyle(fontSize: 16)),
      onTap: onTap,
    );
  }

  Future<void> _loadCompanyLogo() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      final logo = prefs.getString('company_logo');
      if (logo != null && logo.isNotEmpty) {
        _companyLogo = logo; // always full URL saved from login
      }
    });
  }

  void _openAvatarPicker() async {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text("Take Selfie"),
              onTap: () async {
                Navigator.pop(context);
                await _takeAndUploadSelfie();
              },
            ),
            ListTile(
              leading: const Icon(Icons.face),
              title: const Text("Choose Avatar"),
              onTap: () {
                Navigator.pop(context);
                _openDiceBearPicker();
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<XFile> _compressImage(XFile file) async {
    final dir = await getTemporaryDirectory();
    final targetPath =
        '${dir.path}/selfie_${DateTime.now().millisecondsSinceEpoch}.jpg';

    final XFile? compressed = await FlutterImageCompress.compressAndGetFile(
      file.path,
      targetPath,
      quality: 70,
      minWidth: 600,
      minHeight: 600,
      format: CompressFormat.jpeg,
    );

    return compressed ?? file;
  }

  Future<void> _takeAndUploadSelfie() async {
    final picker = ImagePicker();
    final image = await picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 100,
      preferredCameraDevice: CameraDevice.front,
    );

    if (image == null) return;

    final XFile compressedImage = await _compressImage(image);
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString("auth_token");
    final userId = prefs.getString("user_id");

    final uri = Uri.parse("https://techstrota.cloud/api/upload-selfie");

    final request = http.MultipartRequest("POST", uri);
    request.headers["Authorization"] = "Bearer $token";
    request.headers["Accept"] = "application/json";

    request.files.add(
      await http.MultipartFile.fromPath("selfie", compressedImage.path),
    );

    final response = await request.send();

    if (response.statusCode == 200) {
      final resBody = jsonDecode(await response.stream.bytesToString());
      final photoUrl = resBody["photo"];

      if (userId == null) return;

      await prefs.setString("profile_photo_$userId", photoUrl);
      await prefs.setBool("has_selfie_$userId", true);

      setState(() {
        _profilePhotoUrl = photoUrl;
        _hasSelfie = true;
      });
    } else {
      final body = await response.stream.bytesToString();
      debugPrint("❌ Upload failed: ${response.statusCode}");
      debugPrint(body);
    }
  }

  Future<void> _removeSelfieFromServer() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString("auth_token");

    if (token == null) return;

    final uri = Uri.parse("https://techstrota.cloud/api/remove-profile-photo");

    await http.post(
      uri,
      headers: {"Authorization": "Bearer $token", "Accept": "application/json"},
    );
  }

  void _openDiceBearPicker() async {
    List<String> seeds = List.generate(40, (i) => "avatar_$i");

    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Choose Your Avatar"),
        content: SizedBox(
          width: double.maxFinite,
          height: 300,
          child: GridView.builder(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
            ),
            itemCount: seeds.length,
            itemBuilder: (context, index) {
              return GestureDetector(
                onTap: () async {
                  final prefs = await SharedPreferences.getInstance();
                  final userId = prefs.getString("user_id");
                  await _saveAvatarSeed(seeds[index]);

                  if (userId == null) return;

                  await _removeSelfieFromServer();

                  await prefs.setBool("has_selfie_$userId", false);
                  await prefs.remove("profile_photo_$userId");

                  setState(() {
                    _profilePhotoUrl = null;
                    _hasSelfie = false;
                  });
                  Navigator.pop(context);
                },
                child: DiceBearAvatar(seed: seeds[index], size: 60),
              );
            },
          ),
        ),
      ),
    );
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _autoUploadEnabled = prefs.getBool("auto_upload") ?? false;
    });

    if (_autoUploadEnabled) {
      _startAutoUploadListener();

      final current = await Connectivity().checkConnectivity();
      if (current.contains(ConnectivityResult.wifi) ||
          current.contains(ConnectivityResult.mobile)) {
        await AutoUploadService.instance.enableBackgroundUpload();
      }
    }
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool("auto_upload", _autoUploadEnabled);
  }

  void _startAutoUploadListener() {
    _connectivitySubscription?.cancel();
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((
      results,
    ) async {
      if (results.isNotEmpty) {
        final result = results.first;
        if (_autoUploadEnabled &&
            (result == ConnectivityResult.wifi ||
                result == ConnectivityResult.mobile)) {
          await AutoUploadService.instance.enableBackgroundUpload();
        }
      }
    });
  }

  void _stopAutoUploadListener() {
    _connectivitySubscription?.cancel();
    _connectivitySubscription = null;
  }

  @override
  void dispose() {
    _stopAutoUploadListener();
    super.dispose();
  }

  Future<Set<String>> _getUploadedFiles() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList("uploaded_files") ?? [];
    return list.toSet();
  }

  Future<void> _deleteAllImages() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getString('user_id');
      final companyId = prefs.getInt('selected_company_id');

      if (userId == null || companyId == null) return;

      Directory rootDir;

      if (Platform.isAndroid) {
        final base = await getExternalStorageDirectory();
        if (base == null) return;
        rootDir = Directory('${base.path}/ScanVaultApp/$companyId/$userId');
      } else {
        final docDir = await getApplicationDocumentsDirectory();
        rootDir = Directory('${docDir.path}/ScanVaultApp/$companyId/$userId');
      }

      final uploaded = await _getUploadedFiles();

      if (!await rootDir.exists()) {
        ScaffoldMessenger.of(widget.parentContext).showSnackBar(
          const SnackBar(content: Text("No files found to delete")),
        );
        return;
      }

      int deleted = 0;
      int skipped = 0;

      await for (final entity in rootDir.list(recursive: true)) {
        if (entity is File) {
          final path = entity.path.toLowerCase();

          if (path.endsWith('.jpg') ||
              path.endsWith('.jpeg') ||
              path.endsWith('.png')) {
            if (uploaded.contains(entity.path)) {
              await entity.delete();
              deleted++;
            } else {
              skipped++;
            }
          }
        }
      }

      widget.onDelete?.call();

      if (mounted) {
        ScaffoldMessenger.of(widget.parentContext).showSnackBar(
          SnackBar(
            content: Text(
              "Deleted $deleted photos. Skipped $skipped not uploaded.",
            ),
          ),
        );
      }
    } catch (e) {
      debugPrint("❌ Error deleting images: $e");
      if (mounted) {
        ScaffoldMessenger.of(widget.parentContext).showSnackBar(
          const SnackBar(content: Text("Failed to delete images")),
        );
      }
    }
  }

  void _confirmDelete() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Delete All Images?"),
        content: const Text(
          "Are you sure you want to delete all images from the app? This action cannot be undo.",
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              setState(() {
                _deleteEnabled = false;
              });
            },
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await _deleteAllImages();
              if (mounted) {
                Navigator.of(widget.parentContext).pop();
              }
            },
            child: const Text("Delete"),
          ),
        ],
      ),
    );
  }

  void _showLogoutDialog(BuildContext context) {
    FolderService().showLogoutDialog(context, () async {
      if (mounted) {
        await FolderService().logoutUser();
        Navigator.of(context).pop();
        Navigator.of(widget.parentContext).pop();
        Navigator.pushReplacement(
          widget.parentContext,
          MaterialPageRoute(builder: (_) => LoginScreen()),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topLeft,
      child: Padding(
        padding: const EdgeInsets.only(left: 12.0, top: 50.0),
        child: Material(
          elevation: 12,
          borderRadius: BorderRadius.circular(24),
          color: Theme.of(context).colorScheme.surface,
          child: Container(
            width: MediaQuery.of(context).size.width * 0.75,
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Consumer<ThemeProvider>(
              builder: (context, themeProvider, _) {
                return ListView(
                  padding: EdgeInsets.zero,
                  children: [
                    _buildDrawerHeader(),

                    if (_companyLogo != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Image.network(
                          _companyLogo!,
                          height: 60,
                          fit: BoxFit.contain,
                        ),
                      ),

                    _buildCompanySelector(),

                    const Divider(),

                    drawerItem(
                      icon: Icons.person,
                      text: "User Profile",
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(
                          widget.parentContext,
                          MaterialPageRoute(
                            builder: (_) => const UserProfileScreen(),
                          ),
                        );
                      },
                    ),

                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: SwitchListTile(
                        secondary: const Icon(
                          Icons.cloud_upload,
                          color: Colors.deepPurple,
                        ),
                        title: const Text("Auto Upload"),
                        value: _autoUploadEnabled,
                        onChanged: (value) async {
                          setState(() {
                            _autoUploadEnabled = value;
                          });

                          await _saveSettings();

                          if (value) {
                            _startAutoUploadListener();
                            await AutoUploadService.instance.setAutoUpload(
                              true,
                            );
                          } else {
                            _stopAutoUploadListener();
                            await AutoUploadService.instance.setAutoUpload(
                              false,
                            );
                          }
                        },
                      ),
                    ),

                    drawerItem(
                      icon: Icons.cloud_upload_outlined,
                      text: "Upload Pending Photos",
                      onTap: () async {
                        Navigator.pop(context);

                        await PhotoService.uploadPendingPhotos(
                          context: widget.parentContext,
                        );
                      },
                    ),

                    drawerItem(
                      icon: Icons.delete_forever,
                      text: "Delete All Images",
                      onTap: () => _confirmDelete(),
                    ),

                    drawerItem(
                      icon: Icons.folder_shared,
                      text: "Shared With Me",
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(
                          widget.parentContext,
                          MaterialPageRoute(
                            builder: (_) => const SharedWithMeScreen(),
                          ),
                        );
                      },
                    ),

                    drawerItem(
                      icon: Icons.backup,
                      text: "Backup Photos",
                      onTap: () async {
                        Navigator.pop(context);

                        final prefs = await SharedPreferences.getInstance();
                        final userId = prefs.getString('user_id');
                        final companyId = prefs.getInt('selected_company_id');

                        if (userId == null || companyId == null) return;

                        Directory rootDir;

                        if (Platform.isAndroid) {
                          final base = await getExternalStorageDirectory();
                          if (base == null) return;
                          rootDir = Directory(
                            '${base.path}/ScanVaultApp/$companyId/$userId',
                          );
                        } else {
                          final docDir =
                              await getApplicationDocumentsDirectory();
                          rootDir = Directory(
                            '${docDir.path}/ScanVaultApp/$companyId/$userId',
                          );
                        }

                        await BackupService.backupAllPhotos(
                          widget.parentContext,
                          rootDir,
                        );
                      },
                    ),

                    drawerItem(
                      icon: Icons.brightness_6,
                      text: themeProvider.isDarkMode
                          ? "Dark Mode"
                          : "Light Mode",
                      onTap: () =>
                          themeProvider.toggleTheme(!themeProvider.isDarkMode),
                    ),

                    const Divider(),

                    drawerItem(
                      icon: Icons.logout,
                      text: "Log Out",
                      onTap: () => _showLogoutDialog(context),
                    ),

                    const SizedBox(height: 16),

                    // Updated Bottom Container Matching Reference Image Layout
                    // Replace the bottom Container block in your ListView with this:
                    Container(
                      margin: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Theme.of(
                              context,
                            ).colorScheme.primary.withOpacity(0.08),
                            Theme.of(
                              context,
                            ).colorScheme.primary.withOpacity(0.02),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: Theme.of(
                            context,
                          ).colorScheme.primary.withOpacity(0.15),
                          width: 1.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Theme.of(
                              context,
                            ).colorScheme.primary.withOpacity(0.03),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          // App Icon with subtle glow effect
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  Theme.of(context).colorScheme.primary,
                                  Theme.of(
                                    context,
                                  ).colorScheme.primary.withOpacity(0.8),
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: [
                                BoxShadow(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.primary.withOpacity(0.3),
                                  blurRadius: 6,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.camera_alt_rounded,
                              color: Colors.white,
                              size: 22,
                            ),
                          ),
                          const SizedBox(width: 12),

                          // App Title and Tagline
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: const [
                                Text(
                                  "ScanVault",
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.2,
                                  ),
                                ),
                                SizedBox(height: 2),
                                Text(
                                  "Your Photos. Always Safe.",
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey,
                                    fontWeight: FontWeight.w400,
                                  ),
                                ),
                              ],
                            ),
                          ),

                          // Modern Pill Version Badge
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.surface,
                              borderRadius: BorderRadius.circular(30),
                              border: Border.all(
                                color: Theme.of(
                                  context,
                                ).colorScheme.primary.withOpacity(0.2),
                              ),
                            ),
                            child: Text(
                              "v 1.0.1",
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

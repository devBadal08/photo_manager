import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cunning_document_scanner/cunning_document_scanner.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:open_file/open_file.dart';
import 'package:cunning_document_scanner/ios_options.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ScanScreen extends StatefulWidget {
  final Directory? saveFolder;
  final String userId;
  final String folderName;
  final int? sharedFolderId;
  final String? currentFolderPath; // ✅ new parameter for exact folder path
  final void Function(File pdfFile)? onPdfCreated;

  const ScanScreen({
    Key? key,
    this.saveFolder,
    required this.userId,
    required this.folderName,
    this.sharedFolderId,
    this.onPdfCreated,
    this.currentFolderPath, // ✅ added
  }) : super(key: key);

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  List<File> scannedImages = [];
  File? pdfFile;
  bool isScanning = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _startScan());
  }

  Future<void> _startScan() async {
    try {
      final imagePaths = await CunningDocumentScanner.getPictures(
        noOfPages: 50,
        isGalleryImportAllowed: false,
        iosScannerOptions: const IosScannerOptions(
          imageFormat: IosImageFormat.jpg,
          jpgCompressionQuality: 0.7,
        ),
      );

      if (imagePaths == null || imagePaths.isEmpty) {
        Navigator.of(context).pop(pdfFile);
        return;
      }

      final images = imagePaths.map((path) => File(path)).toList();
      if (!mounted) return;
      setState(() {
        scannedImages = images;
        isScanning = false;
      });

      final pdf = await _convertImagesToPdf(images);

      if (pdf != null) {
        widget.onPdfCreated?.call(pdf);
        print("📤 Returning PDF to PhotoListScreen");
      }
    } catch (e) {
      debugPrint("Scan error: $e");
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Failed to scan document")));
      Navigator.of(context).pop();
    }
  }

  Future<File?> _convertImagesToPdf(List<File> images) async {
    try {
      // Request permissions
      if (Platform.isAndroid) {
        final storageStatus = await Permission.storage.request();
        if (!storageStatus.isGranted) {
          final manageStatus = await Permission.manageExternalStorage.request();
          if (!manageStatus.isGranted) return null;
        }
      }

      // ✅ Determine the correct folder path
      final Directory baseDir;

      if (widget.currentFolderPath != null &&
          widget.currentFolderPath!.isNotEmpty) {
        // Use the *exact* subfolder the user is currently inside
        baseDir = Directory(widget.currentFolderPath!);
      } else if (widget.saveFolder != null) {
        // If saveFolder is passed, use that
        baseDir = widget.saveFolder!;
      } else {
        // Fallback to user folder
        baseDir = Directory(
          '/storage/emulated/0/Pictures/MyApp/${widget.userId}/${widget.folderName}',
        );
      }

      // ✅ Ensure directory exists
      if (!await baseDir.exists()) {
        await baseDir.create(recursive: true);
      }

      // Create PDF
      final pdf = pw.Document();
      for (final imgFile in images) {
        final image = pw.MemoryImage(await imgFile.readAsBytes());
        pdf.addPage(
          pw.Page(
            pageFormat: PdfPageFormat.a4,
            margin: pw.EdgeInsets.zero,
            build: (_) => pw.Image(image, fit: pw.BoxFit.contain),
          ),
        );
      }

      // Save PDF
      final pdfPath =
          '${baseDir.path}/scanned_${DateTime.now().millisecondsSinceEpoch}.pdf';
      final file = File(pdfPath);
      await file.writeAsBytes(await pdf.save());

      setState(() => pdfFile = file);

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("PDF saved at: $pdfPath")));

      // Optionally upload PDF
      // await _uploadPdfToServer(file, widget.sharedFolderId ?? 0);

      return file;
    } catch (e, st) {
      debugPrint("PDF conversion error: $e\n$st");
      if (!mounted) return null;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Failed to save as PDF")));
      return null;
    }
  }

  void _openPdf() {
    if (pdfFile != null) OpenFile.open(pdfFile!.path);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return WillPopScope(
      onWillPop: () async {
        if (pdfFile != null) {
          widget.onPdfCreated?.call(pdfFile!);
          Navigator.of(context).pop(pdfFile);
          return false;
        }
        return true;
      },
      child: Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        appBar: AppBar(
          title: const Text("Scan Document"),
          backgroundColor: theme.appBarTheme.backgroundColor,
          foregroundColor: theme.appBarTheme.foregroundColor,
          actions: [
            if (pdfFile != null)
              IconButton(
                icon: const Icon(Icons.picture_as_pdf),
                onPressed: _openPdf,
                tooltip: 'Open PDF',
              ),
          ],
        ),
        body: isScanning
            ? const Center(child: CircularProgressIndicator())
            : scannedImages.isNotEmpty
            ? ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: scannedImages.length,
                itemBuilder: (context, index) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 16.0),
                    child: Image.file(
                      scannedImages[index],
                      fit: BoxFit.contain,
                    ),
                  );
                },
              )
            : const Center(child: Text("No document scanned")),
      ),
    );
  }
}

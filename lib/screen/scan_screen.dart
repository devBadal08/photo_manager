import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cunning_document_scanner/cunning_document_scanner.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:open_file/open_file.dart';
import 'package:cunning_document_scanner/ios_options.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photomanager_practice/services/photo_service.dart'; // Only if saving images/PDF previews to gallery
import 'package:photomanager_practice/utils/invoice_helper.dart';

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
        isGalleryImportAllowed: true,
        iosScannerOptions: const IosScannerOptions(
          imageFormat: IosImageFormat.jpg,
          jpgCompressionQuality: 0.4,
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
      Directory baseDir;

      // ✅ SHARED FOLDER PDF
      if (widget.sharedFolderId != null) {
        final root = await getExternalStorageDirectory();
        if (root == null) {
          throw Exception("External storage not available");
        }

        baseDir = Directory(
          '${root.path}/ScanVaultApp/shared/${widget.sharedFolderId}',
        );
      }
      // ✅ PERSONAL FOLDER PDF
      else if (widget.saveFolder != null) {
        baseDir = widget.saveFolder!;
      }
      // fallback safety
      else {
        final root = await PhotoService.getUserRootDir();
        if (root == null) {
          throw Exception("User root directory not available");
        }
        baseDir = root;
      }

      if (!await baseDir.exists()) {
        await baseDir.create(recursive: true);
      }

      if (!await baseDir.exists()) {
        await baseDir.create(recursive: true);
      }

      if (!await baseDir.exists()) {
        await baseDir.create(recursive: true);
      }

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

      String fileName = "document_${DateTime.now().millisecondsSinceEpoch}";

      try {
        if (images.isNotEmpty) {
          String typeName = "Document";

          try {
            if (images.isNotEmpty) {
              String text = await extractTextFromImage(images.first);

              print("📄 OCR TEXT:\n$text");

              typeName = detectDocumentType(text);

              print("📂 Detected Type: $typeName");
            }
          } catch (e) {
            print("⚠️ Detection failed: $e");
          }

          // ✅ Generate unique name like InvoiceBill1, InvoiceBill2
          fileName = await generateUniqueFileName(baseDir, typeName);

          print("📁 Final File Name: $fileName");
        }
      } catch (e) {
        print("⚠️ Smart naming failed: $e");
      }

      final pdfPath = "${baseDir.path}/$fileName.pdf";

      final file = File(pdfPath);
      await file.writeAsBytes(await pdf.save());

      setState(() => pdfFile = file);

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("PDF saved successfully")));
      print("📦 PDF size: ${await file.length() / (1024 * 1024)} MB");
      return file;
    } catch (e) {
      debugPrint("PDF conversion error: $e");
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Failed to save PDF")));
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

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cunning_document_scanner/cunning_document_scanner.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:open_file/open_file.dart';
import 'package:cunning_document_scanner/ios_options.dart';
import 'package:permission_handler/permission_handler.dart';

class ScanScreen extends StatefulWidget {
  final String userId; // required
  final String folderName; // required
  final int? sharedFolderId; // optional for shared folders
  final void Function(File pdfFile)?
  onPdfCreated; // Add this to ScanScreen constructor

  const ScanScreen({
    Key? key,
    required this.userId,
    required this.folderName,
    this.sharedFolderId,
    this.onPdfCreated,
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
        noOfPages: 10,
        isGalleryImportAllowed: false,
        iosScannerOptions: IosScannerOptions(
          imageFormat: IosImageFormat.jpg,
          jpgCompressionQuality: 0.7,
        ),
      );

      if (imagePaths == null || imagePaths.isEmpty) {
        Navigator.of(context).pop(); // user cancelled
        return;
      }

      final images = imagePaths.map((path) => File(path)).toList();
      setState(() {
        scannedImages = images;
        isScanning = false;
      });

      await _convertImagesToPdf(images);
    } catch (e) {
      debugPrint("Scan error: $e");
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Failed to scan document")));
      Navigator.of(context).pop();
    }
  }

  Future<void> _convertImagesToPdf(List<File> images) async {
    try {
      // 1️⃣ Handle permissions
      if (Platform.isAndroid) {
        // request storage first (works on API <= 29)
        final storageStatus = await Permission.storage.request();
        if (!storageStatus.isGranted) {
          // on Android 11+ user may need MANAGE_EXTERNAL_STORAGE
          final manageStatus = await Permission.manageExternalStorage.request();
          if (!manageStatus.isGranted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text("Storage permission denied")),
            );
            return;
          }
        }
      }

      // 2️⃣ Build folder path: /Pictures/MyApp/<userId>/<folderName>
      final Directory baseDir = widget.sharedFolderId != null
          ? Directory(
              '/storage/emulated/0/Pictures/MyApp/Shared/${widget.sharedFolderId}',
            )
          : Directory(
              '/storage/emulated/0/Pictures/MyApp/${widget.userId}/${widget.folderName}',
            );

      // 3️⃣ Ensure folder exists
      if (!await baseDir.exists()) {
        await baseDir.create(recursive: true);
      }

      // 4️⃣ Create PDF
      final pdf = pw.Document();
      for (final imgFile in images) {
        final image = pw.MemoryImage(await imgFile.readAsBytes());
        pdf.addPage(
          pw.Page(
            pageFormat: PdfPageFormat.a4,
            build: (_) =>
                pw.Center(child: pw.Image(image, fit: pw.BoxFit.contain)),
          ),
        );
      }

      // 5️⃣ Save with timestamp inside selected folder
      final pdfPath =
          '${baseDir.path}/scanned_${DateTime.now().millisecondsSinceEpoch}.pdf';
      final file = File(pdfPath);
      await file.writeAsBytes(await pdf.save());

      setState(() => pdfFile = file);

      if (widget.onPdfCreated != null) {
        widget.onPdfCreated!(file);
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("PDF saved at: $pdfPath")));
    } catch (e, st) {
      debugPrint("PDF conversion error: $e\n$st");
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Failed to save as PDF")));
    }
  }

  void _openPdf() {
    if (pdfFile != null) OpenFile.open(pdfFile!.path);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
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
                  child: Image.file(scannedImages[index], fit: BoxFit.contain),
                );
              },
            )
          : const Center(child: Text("No document scanned")),
    );
  }
}

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cunning_document_scanner/cunning_document_scanner.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:open_file/open_file.dart'; // for opening PDF

class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  File? scannedDocument;
  File? pdfFile;

  Future<void> _startScan() async {
    try {
      final imagePaths = await CunningDocumentScanner.getPictures(
        noOfPages: 1,
        isGalleryImportAllowed: false,
        iosScannerOptions: IosScannerOptions(
          imageFormat: IosImageFormat.jpg,
          jpgCompressionQuality: 0.7,
        ),
      );

      if (imagePaths != null && imagePaths.isNotEmpty) {
        final scannedImage = File(imagePaths[0]);
        setState(() {
          scannedDocument = scannedImage;
        });

        await _convertImageToPdf(scannedImage);
      }
    } catch (e) {
      debugPrint("Scan error: $e");
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Failed to scan document")));
    }
  }

  Future<void> _convertImageToPdf(File imageFile) async {
    try {
      final pdf = pw.Document();

      final image = pw.MemoryImage(imageFile.readAsBytesSync());

      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          build: (pw.Context context) {
            return pw.Center(child: pw.Image(image, fit: pw.BoxFit.contain));
          },
        ),
      );

      final dir = await getApplicationDocumentsDirectory();
      final pdfPath = '${dir.path}/scanned_document.pdf';
      final file = File(pdfPath);
      await file.writeAsBytes(await pdf.save());

      setState(() {
        pdfFile = file;
      });

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("PDF saved at: $pdfPath")));
    } catch (e) {
      debugPrint("PDF conversion error: $e");
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Failed to save as PDF")));
    }
  }

  void _openPdf() {
    if (pdfFile != null) {
      OpenFile.open(pdfFile!.path);
    }
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
      body: Column(
        children: [
          Expanded(
            child: scannedDocument != null
                ? Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Image.file(scannedDocument!, fit: BoxFit.contain),
                  )
                : Center(
                    child: Text(
                      "No document scanned yet",
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24.0),
            child: ElevatedButton.icon(
              icon: const Icon(Icons.document_scanner),
              label: const Text("Start Scan"),
              style: ElevatedButton.styleFrom(
                backgroundColor: theme.colorScheme.primary,
                foregroundColor: theme.colorScheme.onPrimary,
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 16,
                ),
              ),
              onPressed: _startScan,
            ),
          ),
        ],
      ),
    );
  }
}

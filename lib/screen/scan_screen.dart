import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cunning_document_scanner/cunning_document_scanner.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:open_file/open_file.dart';
import 'package:cunning_document_scanner/ios_options.dart';
import 'package:permission_handler/permission_handler.dart';

class ScanScreen extends StatefulWidget {
  final Directory? saveFolder;
  final String userId; // required
  final String folderName; // required
  final int? sharedFolderId; // optional for shared folders
  final void Function(File pdfFile)?
  onPdfCreated; // Add this to ScanScreen constructor

  const ScanScreen({
    Key? key,
    this.saveFolder,
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
      if (!mounted) return;
      setState(() {
        scannedImages = images;
        isScanning = false;
      });

      // Convert images to PDF and return the file path immediately
      final pdf = await _convertImagesToPdf(images);

      if (pdf != null) {
        widget.onPdfCreated?.call(pdf); // send PDF back
        //Navigator.of(context).pop([pdf.path]); // return list of paths
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
      // 1️⃣ Handle permissions
      if (Platform.isAndroid) {
        final storageStatus = await Permission.storage.request();
        if (!storageStatus.isGranted) {
          final manageStatus = await Permission.manageExternalStorage.request();
          if (!manageStatus.isGranted) return null;
        }
      }

      // 2️⃣ Build folder path
      final Directory baseDir = widget.sharedFolderId != null
          ? Directory(
              '/storage/emulated/0/Pictures/MyApp/Shared/${widget.sharedFolderId}',
            )
          : Directory(
              '/storage/emulated/0/Pictures/MyApp/${widget.userId}/${widget.folderName}',
            );

      if (!await baseDir.exists()) await baseDir.create(recursive: true);

      // 3️⃣ Create PDF
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

      // 4️⃣ Save PDF
      final pdfPath =
          '${baseDir.path}/scanned_${DateTime.now().millisecondsSinceEpoch}.pdf';
      final file = File(pdfPath);
      await file.writeAsBytes(await pdf.save());
      if (!mounted) ;

      setState(() => pdfFile = file);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("PDF saved at: $pdfPath")));

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

  Future<void> _renamePdf() async {
    if (pdfFile == null) return;

    final currentPdf = pdfFile!;
    String currentName = currentPdf.path.split('/').last.replaceAll('.pdf', '');

    final result = await showDialog<String>(
      context: context,
      builder: (context) {
        final controller = TextEditingController(text: currentName);
        return AlertDialog(
          title: const Text('Rename PDF'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(hintText: 'Enter new PDF name'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, null),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                final input = controller.text.trim();
                if (input.isNotEmpty) Navigator.pop(context, input);
              },
              child: const Text('Rename'),
            ),
          ],
        );
      },
    );

    if (result == null) return; // user cancelled

    final newPath = '${currentPdf.parent.path}/$result.pdf';
    final newFile = await currentPdf.rename(newPath);

    setState(() => pdfFile = newFile);

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('PDF renamed to $result.pdf')));

    // Call the callback with the updated file
    widget.onPdfCreated?.call(newFile);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return WillPopScope(
      onWillPop: () async {
        // If a PDF was created, send it back before popping
        if (pdfFile != null) {
          widget.onPdfCreated?.call(pdfFile!);
          Navigator.of(context).pop(pdfFile); // return file to caller
          return false; // prevent double pop
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
            if (pdfFile != null) ...[
              IconButton(
                icon: const Icon(Icons.picture_as_pdf),
                onPressed: _openPdf,
                tooltip: 'Open PDF',
              ),
              IconButton(
                icon: const Icon(Icons.edit_note),
                onPressed: _renamePdf,
                tooltip: 'Rename PDF',
              ),
            ],
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

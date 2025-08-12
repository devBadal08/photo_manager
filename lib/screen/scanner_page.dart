import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cunning_document_scanner/cunning_document_scanner.dart';

class ScannerPage extends StatefulWidget {
  final Directory saveFolder; // folder where we save scanned images
  final VoidCallback onScanned; // callback to refresh UI after save

  const ScannerPage({
    super.key,
    required this.saveFolder,
    required this.onScanned,
  });

  @override
  State<ScannerPage> createState() => _ScannerPageState();
}

class _ScannerPageState extends State<ScannerPage> {
  Future<void> _scanDocument() async {
    try {
      // Launch the Cunning Document Scanner
      final List<String>? images = await CunningDocumentScanner.getPictures(
        noOfPages: 1, // limit to 1 page scan; remove if you want multiple
      );

      if (images != null && images.isNotEmpty) {
        // Ensure save folder exists
        if (!await widget.saveFolder.exists()) {
          await widget.saveFolder.create(recursive: true);
        }

        for (final path in images) {
          final fileName = 'IMG_${DateTime.now().millisecondsSinceEpoch}.jpg';
          final newPath = '${widget.saveFolder.path}/$fileName';
          await File(path).copy(newPath);
        }

        // Show confirmation
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('📥 Saved to ${widget.saveFolder.path}')),
        );

        // Trigger UI refresh in parent
        widget.onScanned();

        // Close scanner page
        Navigator.pop(context);
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error scanning: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Document Scanner')),
      body: Center(
        child: ElevatedButton.icon(
          icon: const Icon(Icons.document_scanner),
          label: const Text('Scan Document'),
          onPressed: _scanDocument,
        ),
      ),
    );
  }
}

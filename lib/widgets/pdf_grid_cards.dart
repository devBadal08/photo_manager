// this file code is for display of pdf files in shared users list cards
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:photomanager_practice/screen/pdf_viewer_screen.dart';

class PDFGridCards extends StatelessWidget {
  final List<dynamic> pdfFiles; // can be File or server Map
  final bool selectionMode;
  final List<String> selectedImages;
  final void Function(String) onSelectToggle;

  const PDFGridCards({
    super.key,
    required this.pdfFiles,
    required this.selectionMode,
    required this.selectedImages,
    required this.onSelectToggle,
  });

  @override
  Widget build(BuildContext context) {
    if (pdfFiles.isEmpty) {
      return Center(
        child: Text(
          "No PDFs found",
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: pdfFiles.length,
      itemBuilder: (context, index) {
        final pdf = pdfFiles[index];

        final pdfName = pdf is File
            ? pdf.path.split('/').last
            : pdf['name'] ?? pdf['path'].split('/').last;

        final pdfPath = pdf is File ? pdf.path : pdf['url'] ?? pdf['path'];
        final isSelected = selectedImages.contains(pdfPath);

        final bool isShared =
            pdf is Map &&
            ((pdf['url'] != null &&
                    (pdf['url'] as String).startsWith('http')) ||
                !(pdfPath.toString().startsWith('/storage')));

        final String? pdfUrl = isShared
            ? (pdf['url'] ?? "http://192.168.1.10:8000/storage/${pdf['path']}")
            : null;

        return Card(
          margin: const EdgeInsets.symmetric(vertical: 8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: 4,
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(
              vertical: 12,
              horizontal: 16,
            ),
            leading: selectionMode
                ? Checkbox(
                    value: isSelected,
                    onChanged: (_) => onSelectToggle(pdfPath),
                  )
                : Icon(
                    Icons.picture_as_pdf,
                    size: 40,
                    color: Theme.of(context).colorScheme.error,
                  ),
            title: Text(
              pdfName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            trailing: isShared
                ? null
                : IconButton(
                    icon: const Icon(Icons.edit_note, color: Colors.blueAccent),
                    onPressed: () =>
                        onSelectToggle(pdfPath), // rename handled outside
                  ),
            onLongPress: () => onSelectToggle(pdfPath),
            onTap: () {
              if (selectionMode) {
                onSelectToggle(pdfPath);
              } else {
                if (isShared) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => PdfViewerScreen(pdfFile: pdfUrl!),
                    ),
                  );
                } else {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => PdfViewerScreen(pdfFile: File(pdfPath)),
                    ),
                  );
                }
              }
            },
          ),
        );
      },
    );
  }
}

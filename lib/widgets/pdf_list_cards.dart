// this file code is for display of pdf files in normal users list cards
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:photomanager_practice/screen/pdf_viewer_screen.dart';

class PDFListCards extends StatelessWidget {
  final List<File> pdfFiles;
  final bool selectionMode;
  final List<String> selectedImages;
  final void Function(String) onSelectToggle;
  final void Function(File) onRename;

  const PDFListCards({
    super.key,
    required this.pdfFiles,
    required this.selectionMode,
    required this.selectedImages,
    required this.onSelectToggle,
    required this.onRename,
  });

  @override
  Widget build(BuildContext context) {
    if (pdfFiles.isEmpty) {
      return Center(
        child: Text(
          "No PDFs yet",
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: pdfFiles.length,
      itemBuilder: (context, index) {
        final pdfFile = pdfFiles[index];
        final pdfPath = pdfFile.path;
        final pdfName = pdfPath.split('/').last;
        final isSelected = selectedImages.contains(pdfPath);

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
            trailing: selectionMode
                ? null
                : IconButton(
                    icon: const Icon(Icons.edit_note, color: Colors.blueAccent),
                    onPressed: () => onRename(pdfFile),
                  ),
            onLongPress: () => onSelectToggle(pdfPath),
            onTap: () {
              if (selectionMode) {
                onSelectToggle(pdfPath);
              } else {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => PdfViewerScreen(pdfFile: pdfFile),
                  ),
                );
              }
            },
          ),
        );
      },
    );
  }
}

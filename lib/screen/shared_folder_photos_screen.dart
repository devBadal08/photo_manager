import 'package:flutter/material.dart';

class SharedFolderPhotosScreen extends StatelessWidget {
  final String folderName;
  final List<dynamic> photos;

  const SharedFolderPhotosScreen({
    super.key,
    required this.folderName,
    required this.photos,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(folderName), centerTitle: true),
      body: photos.isEmpty
          ? const Center(child: Text("No photos in this folder"))
          : GridView.builder(
              padding: const EdgeInsets.all(10),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3, // 👈 grid with 3 columns
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
              ),
              itemCount: photos.length,
              itemBuilder: (context, index) {
                final photo = photos[index];
                final imageUrl =
                    "http://192.168.1.4:8000/storage/${photo['path']}"; // 👈 adjust path if needed

                return ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(imageUrl, fit: BoxFit.cover),
                );
              },
            ),
    );
  }
}

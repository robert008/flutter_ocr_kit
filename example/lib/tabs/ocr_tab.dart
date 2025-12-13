import 'package:flutter/material.dart';

import '../pages/image_ocr_page.dart';
import '../camera_ocr_page.dart';

/// OCR Tab - Real-time text recognition
class OcrTab extends StatelessWidget {
  final TextEditingController searchController;

  const OcrTab({super.key, required this.searchController});

  static const List<Map<String, String>> _testImages = [
    {'name': 'Test 1', 'asset': 'assets/test_1.jpg'},
    {'name': 'Test 2', 'asset': 'assets/test_2.jpg'},
    {'name': 'Test 3', 'asset': 'assets/test_3.png'},
  ];

  void _navigateToCameraOcr(BuildContext context) {
    final searchText = searchController.text.trim();
    if (searchText.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter text to search')),
      );
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CameraOcrPage(searchText: searchText),
      ),
    );
  }

  void _navigateToImageOcr(BuildContext context, String assetPath) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ImageOcrPage(
          assetPath: assetPath,
          searchText: searchController.text.trim(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Search input (OCR tab only)
        Container(
          padding: const EdgeInsets.all(12),
          color: Colors.grey.shade100,
          child: TextField(
            controller: searchController,
            decoration: InputDecoration(
              hintText: 'Enter text to search (optional)...',
              prefixIcon: const Icon(Icons.search),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              filled: true,
              fillColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 8,
              ),
            ),
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Camera OCR Card
                Card(
                  color: Colors.blue.shade50,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.camera_alt, color: Colors.blue),
                            SizedBox(width: 8),
                            Text(
                              'Camera Real-time OCR',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Search for text in real-time using camera',
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: () => _navigateToCameraOcr(context),
                            icon: const Icon(Icons.play_arrow),
                            label: const Text('Start Camera OCR'),
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              backgroundColor: Colors.blue,
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                // Image OCR Card
                Card(
                  color: Colors.green.shade50,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.image, color: Colors.green),
                            SizedBox(width: 8),
                            Text(
                              'Image OCR',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Run OCR on test images (opens new page)',
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: _testImages.map((img) {
                            return Expanded(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                ),
                                child: ElevatedButton(
                                  onPressed: () => _navigateToImageOcr(
                                    context,
                                    img['asset']!,
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 12,
                                    ),
                                    backgroundColor: Colors.green,
                                    foregroundColor: Colors.white,
                                  ),
                                  child: Text(
                                    'OCR ${img['name']!.split(' ').last}',
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

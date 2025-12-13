import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'package:flutter_ocr_kit/flutter_ocr_kit.dart';

import '../painters/kie_overlay_painter.dart';

/// Image KIE Page - Static image KIE extraction
class ImageKiePage extends StatefulWidget {
  final List<EntityType> enabledTypes;

  const ImageKiePage({super.key, required this.enabledTypes});

  @override
  State<ImageKiePage> createState() => _ImageKiePageState();
}

class _ImageKiePageState extends State<ImageKiePage> {
  String? _imagePath;
  String _status = 'Select an image';
  bool _isProcessing = false;
  OcrResult? _ocrResult;
  KieResult? _kieResult;

  final SimpleKieExtractor _kieExtractor = SimpleKieExtractor();

  static const List<Map<String, String>> _testImages = [
    {'name': 'Test 1', 'asset': 'assets/test_1.jpg'},
    {'name': 'Test 2', 'asset': 'assets/test_2.jpg'},
    {'name': 'Test 3', 'asset': 'assets/test_3.png'},
  ];

  Future<void> _runKie(String assetPath) async {
    if (_isProcessing) return;

    setState(() {
      _status = 'Loading image...';
      _isProcessing = true;
      _ocrResult = null;
      _kieResult = null;
    });

    try {
      final data = await rootBundle.load(assetPath);
      final imageBytes = data.buffer.asUint8List();

      final appDir = await getApplicationDocumentsDirectory();
      final fileName = 'kie_${assetPath.split('/').last}';
      final imagePath = '${appDir.path}/$fileName';
      await File(imagePath).writeAsBytes(imageBytes);
      _imagePath = imagePath;

      setState(() => _status = 'Running OCR...');
      final ocrResult = await OcrKit.recognizeNative(imagePath);

      setState(() => _status = 'Extracting entities...');
      final kieResult = _kieExtractor.extract(
        ocrResult,
        enabledTypes: widget.enabledTypes,
      );

      setState(() {
        _ocrResult = ocrResult;
        _kieResult = kieResult;
        _status =
            'Done: OCR ${ocrResult.inferenceTimeMs}ms, Found ${kieResult.count} entities';
        _isProcessing = false;
      });
    } catch (e) {
      setState(() {
        _status = 'Error: $e';
        _isProcessing = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'KIE: ${widget.enabledTypes.map((t) => t.label).join(", ")}',
        ),
        backgroundColor: _kieResult?.isNotEmpty == true ? Colors.green : null,
      ),
      body: Column(
        children: [
          // Status bar
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            color: _kieResult?.isNotEmpty == true
                ? Colors.green.shade100
                : (_isProcessing
                    ? Colors.blue.shade100
                    : Colors.grey.shade200),
            child: Row(
              children: [
                if (_isProcessing)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                if (_isProcessing) const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _status,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: _kieResult?.isNotEmpty == true
                          ? Colors.green.shade800
                          : Colors.black,
                    ),
                  ),
                ),
                if (_kieResult?.isNotEmpty == true)
                  Chip(
                    label: Text('${_kieResult!.count} FOUND'),
                    backgroundColor: Colors.green,
                    labelStyle: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                    ),
                  ),
              ],
            ),
          ),

          // Test image buttons
          Container(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: _testImages.map((img) {
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: ElevatedButton(
                      onPressed:
                          !_isProcessing ? () => _runKie(img['asset']!) : null,
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                      ),
                      child: Text(
                        img['name']!,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),

          // Image preview with overlay
          if (_imagePath != null && _ocrResult != null)
            Expanded(
              flex: 2,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    return FittedBox(
                      fit: BoxFit.contain,
                      child: SizedBox(
                        width: _ocrResult!.imageWidth.toDouble(),
                        height: _ocrResult!.imageHeight.toDouble(),
                        child: Stack(
                          children: [
                            Image.file(File(_imagePath!), fit: BoxFit.fill),
                            if (_kieResult != null)
                              CustomPaint(
                                size: Size(
                                  _ocrResult!.imageWidth.toDouble(),
                                  _ocrResult!.imageHeight.toDouble(),
                                ),
                                painter: KieOverlayPainter(
                                  entities: _kieResult!.entities,
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            )
          else
            const Expanded(
              flex: 2,
              child: Center(child: Text('Select a test image above')),
            ),

          // Extracted entities
          if (_kieResult?.isNotEmpty == true)
            Expanded(
              flex: 1,
              child: Card(
                margin: const EdgeInsets.all(8),
                color: Colors.orange.shade50,
                child: ListView(
                  padding: const EdgeInsets.all(12),
                  children: _kieResult!.byType.entries.map((entry) {
                    final type = entry.key;
                    final entities = entry.value;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 12,
                                height: 12,
                                decoration: BoxDecoration(
                                  color: type.color,
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '${type.label} (${entities.length})',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                  color: type.color,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            children: entities
                                .map(
                                  (e) => Chip(
                                    label: Text(
                                      e.value,
                                      style: const TextStyle(fontSize: 11),
                                    ),
                                    backgroundColor: type.color.withOpacity(0.2),
                                    side: BorderSide(
                                      color: type.color,
                                      width: 1,
                                    ),
                                    visualDensity: VisualDensity.compact,
                                    materialTapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                  ),
                                )
                                .toList(),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

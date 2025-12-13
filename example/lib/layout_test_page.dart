import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import 'package:flutter_ocr_kit/flutter_ocr_kit.dart';

/// Top-level function for compute() - initializes layout model and runs warmup
int _initLayoutModelInBackground(Map<String, String> paths) {
  final modelPath = paths['modelPath']!;
  final warmupPath = paths['warmupPath']!;

  OcrKit.init(modelPath);

  final warmupStart = DateTime.now();
  OcrKit.detectLayout(warmupPath);
  return DateTime.now().difference(warmupStart).inMilliseconds;
}

/// Top-level function for compute() - runs layout detection in background isolate
Map<String, dynamic> _detectLayoutInBackground(Map<String, String> params) {
  final modelPath = params['modelPath']!;
  final imagePath = params['imagePath']!;

  OcrKit.init(modelPath);

  final result = OcrKit.detectLayout(imagePath);
  return result.toJson();
}

/// Layout Test Page - Test Layout Detection on invoice photos
///
/// This page helps us understand how Layout Detection handles invoices
/// before implementing the full invoice scanner.
class LayoutTestPage extends StatefulWidget {
  const LayoutTestPage({super.key});

  @override
  State<LayoutTestPage> createState() => _LayoutTestPageState();
}

class _LayoutTestPageState extends State<LayoutTestPage> {
  String? _imagePath;
  String? _layoutModelPath;
  String _status = 'Initializing...';
  bool _isProcessing = false;
  bool _isLayoutInitialized = false;
  bool _isInitializing = false;

  LayoutResult? _layoutResult;
  OcrResult? _ocrResult;

  final ImagePicker _picker = ImagePicker();

  // Model selection
  String _selectedModel = 'pp_doclayout_m.onnx'; // Default to Medium
  final List<String> _availableModels = [
    'pp_doclayout_m.onnx',
    'pp_doclayout_l.onnx',
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 300), () {
        if (mounted) _initLayoutModel();
      });
    });
  }

  Future<void> _initLayoutModel() async {
    if (_isLayoutInitialized || _isInitializing) return;

    setState(() {
      _isInitializing = true;
      _status = 'Copying Layout model...';
    });

    try {
      final data = await rootBundle.load('assets/$_selectedModel');
      final modelBytes = data.buffer.asUint8List();

      final appDir = await getApplicationDocumentsDirectory();
      final modelPath = '${appDir.path}/$_selectedModel';

      final modelFile = File(modelPath);
      if (!await modelFile.exists()) {
        await modelFile.writeAsBytes(modelBytes);
      }

      // Prepare warmup image
      final warmupData = await rootBundle.load('assets/test_1.jpg');
      final warmupBytes = warmupData.buffer.asUint8List();
      final warmupPath = '${appDir.path}/warmup_layout.jpg';
      await File(warmupPath).writeAsBytes(warmupBytes);

      setState(() => _status = 'Initializing Layout model...');

      final warmupTime = await compute(
        _initLayoutModelInBackground,
        {'modelPath': modelPath, 'warmupPath': warmupPath},
      );

      OcrKit.init(modelPath);
      _layoutModelPath = modelPath;

      try {
        await File(warmupPath).delete();
      } catch (_) {}

      setState(() {
        _isLayoutInitialized = true;
        _isInitializing = false;
        _status = '$_selectedModel ready (warmup: ${warmupTime}ms). Pick a photo.';
      });
    } catch (e) {
      setState(() {
        _isInitializing = false;
        _status = 'Failed to init: $e';
      });
    }
  }

  Future<void> _pickAndProcess() async {
    if (_isProcessing || !_isLayoutInitialized) return;

    final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
    if (image == null) return;

    setState(() {
      _isProcessing = true;
      _status = 'Processing...';
      _layoutResult = null;
      _ocrResult = null;
      _imagePath = image.path;
    });

    try {
      // Step 1: Layout Detection
      setState(() => _status = 'Running Layout Detection...');
      final layoutJson = await compute(_detectLayoutInBackground, {
        'modelPath': _layoutModelPath!,
        'imagePath': image.path,
      });
      final layoutResult = LayoutResult.fromJson(layoutJson);

      // Log Layout Detection results
      debugPrint('========== LAYOUT DETECTION RESULTS ==========');
      debugPrint('Image: ${image.path}');
      debugPrint('Total regions: ${layoutResult.count}');
      debugPrint('Inference time: ${layoutResult.inferenceTimeMs}ms');
      for (int i = 0; i < layoutResult.detections.length; i++) {
        final det = layoutResult.detections[i];
        debugPrint('  [${i + 1}] ${det.className} (score: ${(det.score * 100).toStringAsFixed(1)}%)');
        debugPrint('      Box: (${det.x1.toInt()}, ${det.y1.toInt()}) - (${det.x2.toInt()}, ${det.y2.toInt()})');
        debugPrint('      Size: ${det.width.toInt()} x ${det.height.toInt()}');
      }
      debugPrint('===============================================');

      // Step 2: OCR
      setState(() => _status = 'Running OCR...');
      final ocrResult = await OcrKit.recognizeNative(image.path);

      // Log OCR results summary
      debugPrint('========== OCR RESULTS ==========');
      debugPrint('Total texts: ${ocrResult.count}');
      debugPrint('Inference time: ${ocrResult.inferenceTimeMs}ms');
      debugPrint('First 10 texts:');
      for (int i = 0; i < ocrResult.results.length && i < 10; i++) {
        final text = ocrResult.results[i];
        debugPrint('  [${i + 1}] "${text.text}" (score: ${(text.score * 100).toStringAsFixed(1)}%)');
      }
      if (ocrResult.results.length > 10) {
        debugPrint('  ... and ${ocrResult.results.length - 10} more texts');
      }
      debugPrint('=================================');

      setState(() {
        _layoutResult = layoutResult;
        _ocrResult = ocrResult;
        _status = 'Layout: ${layoutResult.inferenceTimeMs}ms (${layoutResult.count} regions), '
            'OCR: ${ocrResult.inferenceTimeMs}ms (${ocrResult.count} texts)';
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
        title: const Text('Layout Test (Invoice)'),
        backgroundColor: Colors.deepOrange,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          // Status bar
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            color: _isProcessing || _isInitializing
                ? Colors.blue.shade100
                : (_layoutResult != null ? Colors.green.shade100 : Colors.grey.shade200),
            child: Row(
              children: [
                if (_isProcessing || _isInitializing)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                if (_isProcessing || _isInitializing) const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _status,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),

          // Model selector + Pick image button
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                // Model selector
                Row(
                  children: [
                    const Text('Model: ', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: SegmentedButton<String>(
                        segments: _availableModels.map((m) {
                          final name = m.contains('_m') ? 'Medium' : 'Large';
                          return ButtonSegment(value: m, label: Text(name));
                        }).toList(),
                        selected: {_selectedModel},
                        onSelectionChanged: _isLayoutInitialized && !_isProcessing
                            ? (selected) {
                                setState(() {
                                  _selectedModel = selected.first;
                                  _isLayoutInitialized = false;
                                  _layoutResult = null;
                                  _ocrResult = null;
                                  _imagePath = null;
                                });
                                _initLayoutModel();
                              }
                            : null,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // Pick image button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: (!_isProcessing && _isLayoutInitialized) ? _pickAndProcess : null,
                    icon: const Icon(Icons.photo_library),
                    label: const Text('Pick Invoice Photo'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      backgroundColor: Colors.deepOrange,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Image preview with Layout overlay
          if (_imagePath != null && _layoutResult != null && _ocrResult != null)
            Expanded(
              flex: 3,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    return InteractiveViewer(
                      minScale: 0.5,
                      maxScale: 4.0,
                      child: FittedBox(
                        fit: BoxFit.contain,
                        child: SizedBox(
                          width: _ocrResult!.imageWidth.toDouble(),
                          height: _ocrResult!.imageHeight.toDouble(),
                          child: Stack(
                            children: [
                              Image.file(File(_imagePath!), fit: BoxFit.fill),
                              CustomPaint(
                                size: Size(
                                  _ocrResult!.imageWidth.toDouble(),
                                  _ocrResult!.imageHeight.toDouble(),
                                ),
                                painter: _LayoutOverlayPainter(
                                  layoutResult: _layoutResult!,
                                  ocrResult: _ocrResult!,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            )
          else if (_isInitializing)
            const Expanded(
              flex: 3,
              child: Center(child: CircularProgressIndicator()),
            )
          else
            const Expanded(
              flex: 3,
              child: Center(
                child: Text(
                  'Pick an invoice photo to test\nLayout Detection output',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey),
                ),
              ),
            ),

          // Results panel
          if (_layoutResult != null)
            Expanded(
              flex: 2,
              child: Card(
                margin: const EdgeInsets.all(8),
                child: DefaultTabController(
                  length: 2,
                  child: Column(
                    children: [
                      const TabBar(
                        tabs: [
                          Tab(text: 'Layout Regions'),
                          Tab(text: 'OCR Texts'),
                        ],
                      ),
                      Expanded(
                        child: TabBarView(
                          children: [
                            // Layout Regions tab
                            _buildLayoutRegionsTab(),
                            // OCR Texts tab
                            _buildOcrTextsTab(),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildLayoutRegionsTab() {
    if (_layoutResult == null) return const SizedBox();

    final regions = _layoutResult!.detections;
    if (regions.isEmpty) {
      return const Center(child: Text('No regions detected'));
    }

    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: regions.length,
      itemBuilder: (context, index) {
        final region = regions[index];
        final color = _getRegionColor(region.className);
        return Card(
          child: ListTile(
            leading: Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Center(
                child: Text(
                  '${index + 1}',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                ),
              ),
            ),
            title: Text(
              region.className,
              style: TextStyle(fontWeight: FontWeight.bold, color: color),
            ),
            subtitle: Text(
              'Score: ${(region.score * 100).toStringAsFixed(1)}%\n'
              'Box: (${region.x1.toInt()}, ${region.y1.toInt()}) - (${region.x2.toInt()}, ${region.y2.toInt()})\n'
              'Size: ${region.width.toInt()} x ${region.height.toInt()}',
              style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
            ),
            isThreeLine: true,
          ),
        );
      },
    );
  }

  Widget _buildOcrTextsTab() {
    if (_ocrResult == null) return const SizedBox();

    final texts = _ocrResult!.results;
    if (texts.isEmpty) {
      return const Center(child: Text('No text recognized'));
    }

    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: texts.length,
      itemBuilder: (context, index) {
        final text = texts[index];
        return Card(
          child: ListTile(
            leading: CircleAvatar(
              radius: 12,
              backgroundColor: Colors.blue,
              child: Text(
                '${index + 1}',
                style: const TextStyle(color: Colors.white, fontSize: 10),
              ),
            ),
            title: Text(
              text.text,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Text(
              'Score: ${(text.score * 100).toStringAsFixed(1)}% | '
              '(${text.x1.toInt()}, ${text.y1.toInt()})',
              style: const TextStyle(fontSize: 11),
            ),
          ),
        );
      },
    );
  }

  Color _getRegionColor(String className) {
    switch (className) {
      case 'Table':
        return const Color(0xFF4CAF50);
      case 'Text':
        return const Color(0xFF2196F3);
      case 'Title':
        return const Color(0xFFFF9800);
      case 'Figure':
        return const Color(0xFF9C27B0);
      case 'Figure caption':
      case 'Table caption':
        return const Color(0xFF795548);
      case 'Header':
      case 'Footer':
        return const Color(0xFF607D8B);
      case 'Reference':
        return const Color(0xFF00BCD4);
      case 'Equation':
        return const Color(0xFFE91E63);
      default:
        return const Color(0xFF9E9E9E);
    }
  }
}

class _LayoutOverlayPainter extends CustomPainter {
  final LayoutResult layoutResult;
  final OcrResult ocrResult;

  _LayoutOverlayPainter({required this.layoutResult, required this.ocrResult});

  @override
  void paint(Canvas canvas, Size size) {
    // Draw Layout regions with thick borders and labels
    for (int i = 0; i < layoutResult.detections.length; i++) {
      final region = layoutResult.detections[i];
      final color = _getRegionColor(region.className);

      // Fill
      final fillPaint = Paint()
        ..color = color.withOpacity(0.15)
        ..style = PaintingStyle.fill;

      // Border
      final borderPaint = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4;

      final rect = Rect.fromLTRB(region.x1, region.y1, region.x2, region.y2);
      canvas.drawRect(rect, fillPaint);
      canvas.drawRect(rect, borderPaint);

      // Label with index
      final labelSpan = TextSpan(
        text: ' ${i + 1}. ${region.className} (${(region.score * 100).toInt()}%) ',
        style: TextStyle(
          color: Colors.white,
          fontSize: 20,
          fontWeight: FontWeight.bold,
          backgroundColor: color,
        ),
      );
      final labelPainter = TextPainter(
        text: labelSpan,
        textDirection: TextDirection.ltr,
      );
      labelPainter.layout();

      final labelY = region.y1 - labelPainter.height - 4;
      labelPainter.paint(
        canvas,
        Offset(region.x1, labelY > 0 ? labelY : region.y1),
      );
    }

    // Draw OCR text boxes (thin blue lines)
    final textPaint = Paint()
      ..color = Colors.blue.withOpacity(0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    for (final text in ocrResult.results) {
      final rect = Rect.fromLTRB(text.x1, text.y1, text.x2, text.y2);
      canvas.drawRect(rect, textPaint);
    }
  }

  Color _getRegionColor(String className) {
    switch (className) {
      case 'Table':
        return const Color(0xFF4CAF50);
      case 'Text':
        return const Color(0xFF2196F3);
      case 'Title':
        return const Color(0xFFFF9800);
      case 'Figure':
        return const Color(0xFF9C27B0);
      default:
        return const Color(0xFF9E9E9E);
    }
  }

  @override
  bool shouldRepaint(covariant _LayoutOverlayPainter oldDelegate) {
    return layoutResult != oldDelegate.layoutResult || ocrResult != oldDelegate.ocrResult;
  }
}

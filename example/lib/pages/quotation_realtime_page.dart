import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'package:flutter_ocr_kit/flutter_ocr_kit.dart';

import 'quotation_list_page.dart';

/// Top-level function for compute() - initializes layout model
int _initLayoutModelInBackground(Map<String, String> paths) {
  final modelPath = paths['modelPath']!;
  final warmupPath = paths['warmupPath']!;

  OcrKit.init(modelPath);

  final warmupStart = DateTime.now();
  OcrKit.detectLayout(warmupPath);
  return DateTime.now().difference(warmupStart).inMilliseconds;
}

/// Top-level function for compute() - runs layout detection
Map<String, dynamic> _detectLayoutInBackground(Map<String, String> params) {
  final modelPath = params['modelPath']!;
  final imagePath = params['imagePath']!;

  OcrKit.init(modelPath);

  final result = OcrKit.detectLayout(imagePath);
  return result.toJson();
}

/// Quotation Real-time Scanner Page
///
/// Real-time scanning with:
/// - Layout Detection (find Table regions)
/// - OCR text recognition
/// - Quotation info extraction
/// - Overlay showing Table and quotation number
class QuotationRealtimePage extends StatefulWidget {
  final Map<String, ScannedQuotation> sharedStorage;

  const QuotationRealtimePage({
    super.key,
    required this.sharedStorage,
  });

  @override
  State<QuotationRealtimePage> createState() => _QuotationRealtimePageState();
}

class _QuotationRealtimePageState extends State<QuotationRealtimePage> {
  CameraController? _cameraController;
  List<CameraDescription>? _cameras;
  bool _isCameraInitialized = false;
  bool _isProcessing = false;
  bool _isScanning = false;
  String _status = 'Initializing...';

  // Layout model
  String? _layoutModelPath;
  bool _isLayoutInitialized = false;
  bool _isInitializing = false;

  // OCR & Quotation extraction
  final QuotationExtractor _extractor = QuotationExtractor();
  QuotationInfo? _lastQuotation;
  LayoutResult? _lastLayoutResult;
  OcrResult? _lastOcrResult;
  Size? _imageSize;

  /// Generate unique key for deduplication
  /// Uses only the numeric portion of quotation number
  String _getDedupeKey(String quotationNumber) {
    return quotationNumber.replaceAll(RegExp(r'[^0-9]'), '');
  }

  // FPS tracking
  int _frameCount = 0;
  double _currentFps = 0;
  DateTime? _fpsStartTime;

  // Last added quotation (for UI feedback)
  String? _lastAddedQuotation;
  DateTime? _lastAddedTime;

  @override
  void initState() {
    super.initState();
    _initAll();
  }

  Future<void> _initAll() async {
    await _initLayoutModel();
    await _initCamera();
  }

  Future<void> _initLayoutModel() async {
    if (_isLayoutInitialized || _isInitializing) return;

    setState(() {
      _isInitializing = true;
      _status = 'Copying Layout model...';
    });

    try {
      final data = await rootBundle.load('assets/pp_doclayout_l.onnx');
      final modelBytes = data.buffer.asUint8List();

      final appDir = await getApplicationDocumentsDirectory();
      final modelPath = '${appDir.path}/pp_doclayout_l.onnx';

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
        _status = 'Layout ready (warmup: ${warmupTime}ms)';
      });
    } catch (e) {
      setState(() {
        _isInitializing = false;
        _status = 'Layout init failed: $e';
      });
    }
  }

  Future<void> _initCamera() async {
    try {
      setState(() => _status = 'Initializing camera...');

      _cameras = await availableCameras();
      if (_cameras == null || _cameras!.isEmpty) {
        setState(() => _status = 'No camera available');
        return;
      }

      _cameraController = CameraController(
        _cameras!.first,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );

      await _cameraController!.initialize();

      setState(() {
        _isCameraInitialized = true;
        _status = 'Ready. Tap Play to start scanning.';
      });
    } catch (e) {
      setState(() => _status = 'Camera init failed: $e');
    }
  }

  void _startScanning() {
    if (!_isLayoutInitialized || !_isCameraInitialized) return;

    setState(() {
      _isScanning = true;
      _frameCount = 0;
      _fpsStartTime = DateTime.now();
      _status = 'Scanning...';
    });

    _processNextFrame();
  }

  Future<void> _processNextFrame() async {
    if (!_isScanning) return;
    if (!_isCameraInitialized || _cameraController == null) return;
    if (!_cameraController!.value.isInitialized) return;
    if (_isProcessing) {
      Future.microtask(() => _processNextFrame());
      return;
    }

    _isProcessing = true;
    String? tempFilePath;

    try {
      final XFile file = await _cameraController!.takePicture();
      tempFilePath = file.path;

      // Step 1: Layout Detection
      final layoutJson = await compute(_detectLayoutInBackground, {
        'modelPath': _layoutModelPath!,
        'imagePath': file.path,
      });
      final layoutResult = LayoutResult.fromJson(layoutJson);

      // Step 2: OCR
      final ocrResult = await OcrKit.recognizeNative(file.path);

      // Step 3: Extract quotation info
      final quotationInfo = _extractor.extract(ocrResult, layoutResult: layoutResult);

      // Update FPS
      _frameCount++;
      final elapsed = DateTime.now().difference(_fpsStartTime!).inMilliseconds;
      if (elapsed > 0) {
        _currentFps = (_frameCount / elapsed) * 1000;
      }

      // Check if valid and meets confidence threshold
      const double addThreshold = 0.60;

      debugPrint('[QuotationRealtime] OCR confidence: ${(quotationInfo.confidence * 100).toStringAsFixed(1)}%, isValid: ${quotationInfo.isValid}, number: ${quotationInfo.quotationNumber}');

      if (quotationInfo.isValid) {
        final dedupeKey = _getDedupeKey(quotationInfo.quotationNumber!);
        if (!widget.sharedStorage.containsKey(dedupeKey)) {
          // Only add new entry if confidence >= 90%
          if (quotationInfo.confidence >= addThreshold) {
            final scanned = ScannedQuotation.fromInfo(quotationInfo);
            widget.sharedStorage[dedupeKey] = scanned;
            _lastAddedQuotation = quotationInfo.quotationNumber;
            _lastAddedTime = DateTime.now();
          }
        } else {
          // Update existing (threshold check is inside updateFrom)
          widget.sharedStorage[dedupeKey]!.updateFrom(quotationInfo);
        }
      }

      // Clear "just added" feedback after 2 seconds
      if (_lastAddedTime != null &&
          DateTime.now().difference(_lastAddedTime!).inSeconds >= 2) {
        _lastAddedQuotation = null;
      }

      if (mounted) {
        setState(() {
          _lastLayoutResult = layoutResult;
          _lastOcrResult = ocrResult;
          _lastQuotation = quotationInfo;
          _imageSize = Size(
            ocrResult.imageWidth.toDouble(),
            ocrResult.imageHeight.toDouble(),
          );

          if (quotationInfo.isValid) {
            _status = '${quotationInfo.quotationNumber} | ${quotationInfo.displayTotal}';
          } else {
            final tableCount = layoutResult.detections
                .where((d) => d.className.toLowerCase() == 'table')
                .length;
            _status = 'Table: $tableCount | ${_currentFps.toStringAsFixed(1)} FPS';
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _status = 'Error: $e');
      }
    } finally {
      _isProcessing = false;
      if (tempFilePath != null) {
        try {
          await File(tempFilePath).delete();
        } catch (_) {}
      }
      if (_isScanning && mounted) {
        Future.microtask(() => _processNextFrame());
      }
    }
  }

  void _toggleScanning() {
    if (_isScanning) {
      setState(() {
        _isScanning = false;
        _status = 'Paused';
      });
    } else {
      _startScanning();
    }
  }

  void _viewResults() {
    setState(() {
      _isScanning = false;
    });

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => QuotationListPage(
          quotations: widget.sharedStorage.values.toList(),
        ),
      ),
    );
  }

  void _clearAll() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear All'),
        content: Text('Delete all ${widget.sharedStorage.length} scanned quotations?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              setState(() {
                widget.sharedStorage.clear();
                _lastAddedQuotation = null;
              });
              Navigator.pop(context);
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _isScanning = false;
    _cameraController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final quotationCount = widget.sharedStorage.length;
    final totalAmount = widget.sharedStorage.values
        .where((q) => q.total != null)
        .fold<int>(0, (sum, q) => sum + q.total!);

    final isReady = _isLayoutInitialized && _isCameraInitialized;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Real-time Scan'),
        backgroundColor: _lastQuotation?.isValid == true ? Colors.green : Colors.deepPurple,
        foregroundColor: Colors.white,
        actions: [
          if (quotationCount > 0)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: _clearAll,
              tooltip: 'Clear all',
            ),
        ],
      ),
      body: Column(
        children: [
          // Status bar
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            color: _lastQuotation?.isValid == true
                ? Colors.green.shade100
                : (_isScanning ? Colors.blue.shade100 : Colors.grey.shade200),
            child: Row(
              children: [
                if (_isScanning)
                  Container(
                    width: 12,
                    height: 12,
                    margin: const EdgeInsets.only(right: 8),
                    decoration: const BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                    ),
                  ),
                Expanded(
                  child: Text(
                    _status,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontFamily: 'monospace',
                      fontSize: 13,
                      color: _lastQuotation?.isValid == true
                          ? Colors.green.shade800
                          : Colors.black,
                    ),
                  ),
                ),
                if (_isScanning)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.red,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text(
                      'LIVE',
                      style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                    ),
                  ),
              ],
            ),
          ),

          // Camera preview
          Expanded(
            child: _isCameraInitialized && _cameraController != null
                ? Stack(
                    fit: StackFit.expand,
                    children: [
                      // Camera preview
                      _buildCameraPreview(),

                      // Layout + Quotation overlay
                      if (_imageSize != null)
                        CustomPaint(
                          painter: _QuotationRealtimeOverlayPainter(
                            layoutResult: _lastLayoutResult,
                            quotationInfo: _lastQuotation,
                            imageSize: _imageSize!,
                          ),
                        ),

                      // "Just added" feedback
                      if (_lastAddedQuotation != null)
                        Positioned(
                          top: 20,
                          left: 20,
                          right: 20,
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.green,
                              borderRadius: BorderRadius.circular(8),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.3),
                                  blurRadius: 8,
                                ),
                              ],
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.check_circle, color: Colors.white),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Added: $_lastAddedQuotation',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  )
                : Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const CircularProgressIndicator(),
                        const SizedBox(height: 16),
                        Text(_status),
                      ],
                    ),
                  ),
          ),

          // Bottom panel
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 8,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: SafeArea(
              top: false,
              child: Column(
                children: [
                  // Stats row
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildStatItem(
                        icon: Icons.description,
                        label: 'Quotations',
                        value: '$quotationCount',
                      ),
                      _buildStatItem(
                        icon: Icons.attach_money,
                        label: 'Total',
                        value: '\$$totalAmount',
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Buttons row
                  Row(
                    children: [
                      // Pause/Resume button
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: isReady ? _toggleScanning : null,
                          icon: Icon(_isScanning ? Icons.pause : Icons.play_arrow),
                          label: Text(_isScanning ? 'Pause' : 'Start'),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),

                      // View results button
                      Expanded(
                        flex: 2,
                        child: ElevatedButton.icon(
                          onPressed: quotationCount > 0 ? _viewResults : null,
                          icon: const Icon(Icons.list),
                          label: Text('View Results ($quotationCount)'),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            backgroundColor: Colors.deepPurple,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCameraPreview() {
    return ClipRect(
      child: OverflowBox(
        alignment: Alignment.center,
        child: FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            width: _cameraController!.value.previewSize!.height,
            height: _cameraController!.value.previewSize!.width,
            child: CameraPreview(_cameraController!),
          ),
        ),
      ),
    );
  }

  Widget _buildStatItem({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Column(
      children: [
        Icon(icon, size: 28, color: Colors.deepPurple),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey.shade600,
          ),
        ),
      ],
    );
  }
}

/// Overlay painter for real-time quotation scanning
class _QuotationRealtimeOverlayPainter extends CustomPainter {
  final LayoutResult? layoutResult;
  final QuotationInfo? quotationInfo;
  final Size imageSize;

  _QuotationRealtimeOverlayPainter({
    this.layoutResult,
    this.quotationInfo,
    required this.imageSize,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (imageSize.width == 0 || imageSize.height == 0) return;

    final scaleX = size.width / imageSize.width;
    final scaleY = size.height / imageSize.height;

    // Draw Table regions from Layout Detection
    if (layoutResult != null) {
      for (final region in layoutResult!.detections) {
        if (region.className.toLowerCase() != 'table') continue;

        final rect = Rect.fromLTRB(
          region.x1 * scaleX,
          region.y1 * scaleY,
          region.x2 * scaleX,
          region.y2 * scaleY,
        );

        final fillPaint = Paint()
          ..color = Colors.green.withOpacity(0.15)
          ..style = PaintingStyle.fill;

        final strokePaint = Paint()
          ..color = Colors.green
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3;

        canvas.drawRect(rect, fillPaint);
        canvas.drawRect(rect, strokePaint);

        // Label
        _drawLabel(canvas, rect, 'Table', Colors.green);
      }
    }

    // Draw quotation number highlight
    if (quotationInfo?.quotationNumberRect != null) {
      final rect = quotationInfo!.quotationNumberRect!;
      final scaledRect = Rect.fromLTRB(
        rect.left * scaleX,
        rect.top * scaleY,
        rect.right * scaleX,
        rect.bottom * scaleY,
      );

      final fillPaint = Paint()
        ..color = Colors.orange.withOpacity(0.3)
        ..style = PaintingStyle.fill;

      final strokePaint = Paint()
        ..color = Colors.orange
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3;

      canvas.drawRect(scaledRect, fillPaint);
      canvas.drawRect(scaledRect, strokePaint);

      // Label with quotation number
      final label = quotationInfo!.quotationNumber ?? 'Quotation #';
      _drawLabel(canvas, scaledRect, label, Colors.orange);
    }
  }

  void _drawLabel(Canvas canvas, Rect rect, String text, Color color) {
    final textSpan = TextSpan(
      text: ' $text ',
      style: TextStyle(
        color: Colors.white,
        fontSize: 14,
        fontWeight: FontWeight.bold,
        backgroundColor: color,
      ),
    );
    final textPainter = TextPainter(
      text: textSpan,
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();

    final labelY = rect.top - textPainter.height - 4;
    textPainter.paint(
      canvas,
      Offset(rect.left, labelY > 0 ? labelY : rect.top),
    );
  }

  @override
  bool shouldRepaint(covariant _QuotationRealtimeOverlayPainter oldDelegate) {
    return layoutResult != oldDelegate.layoutResult ||
        quotationInfo != oldDelegate.quotationInfo ||
        imageSize != oldDelegate.imageSize;
  }
}

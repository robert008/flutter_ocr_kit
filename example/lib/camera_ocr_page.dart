import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import 'package:flutter_ocr_kit/flutter_ocr_kit.dart';

class CameraOcrPage extends StatefulWidget {
  final String searchText;

  const CameraOcrPage({super.key, required this.searchText});

  @override
  State<CameraOcrPage> createState() => _CameraOcrPageState();
}

class _CameraOcrPageState extends State<CameraOcrPage> {
  CameraController? _cameraController;
  List<CameraDescription>? _cameras;
  bool _isCameraInitialized = false;
  bool _isProcessing = false;
  bool _isRealTimeRunning = false;
  String _status = 'Initializing camera...';

  OcrResult? _lastOcrResult;
  List<TextLine> _matchedLines = [];
  Size? _imageSize;
  int _lastInferenceMs = 0;

  // FPS tracking
  int _frameCount = 0;
  double _currentFps = 0;
  DateTime? _fpsStartTime;

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras == null || _cameras!.isEmpty) {
        setState(() {
          _status = 'No camera available';
        });
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
        _isRealTimeRunning = true;
        _status = 'Starting OCR...';
        _frameCount = 0;
        _fpsStartTime = DateTime.now();
      });

      // Auto-start full speed OCR
      _processNextFrame();
    } catch (e) {
      setState(() {
        _status = 'Camera init failed: $e';
      });
    }
  }

  Future<void> _processNextFrame() async {
    if (!_isRealTimeRunning) return;
    if (!_isCameraInitialized || _cameraController == null) return;
    if (!_cameraController!.value.isInitialized) return;

    // Skip if still processing previous frame
    if (_isProcessing) {
      // Schedule next attempt
      Future.microtask(() => _processNextFrame());
      return;
    }

    _isProcessing = true;
    String? tempFilePath;

    try {
      // Capture image
      final XFile file = await _cameraController!.takePicture();
      tempFilePath = file.path;

      // Run Native OCR (Vision on iOS, ML Kit on Android)
      final result = await OcrKit.recognizeNative(file.path);

      // Update FPS
      _frameCount++;
      final elapsed = DateTime.now().difference(_fpsStartTime!).inMilliseconds;
      if (elapsed > 0) {
        _currentFps = (_frameCount / elapsed) * 1000;
      }

      // Find matches (use precise word-level boxes)
      final matches = result.findTextPrecise(widget.searchText);

      if (mounted) {
        setState(() {
          _lastOcrResult = result;
          _matchedLines = matches;
          _lastInferenceMs = result.inferenceTimeMs;
          _imageSize = Size(
            result.imageWidth.toDouble(),
            result.imageHeight.toDouble(),
          );

          if (matches.isNotEmpty) {
            _status = 'FOUND ${matches.length} | ${result.inferenceTimeMs}ms | ${_currentFps.toStringAsFixed(1)} FPS';
          } else {
            _status = '${result.count} texts | ${result.inferenceTimeMs}ms | ${_currentFps.toStringAsFixed(1)} FPS';
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _status = 'OCR error: $e';
        });
      }
    } finally {
      _isProcessing = false;

      // Clean up temp file
      if (tempFilePath != null) {
        try {
          await File(tempFilePath).delete();
        } catch (_) {}
      }

      // Immediately process next frame (full speed)
      if (_isRealTimeRunning && mounted) {
        // Use microtask to avoid stack overflow
        Future.microtask(() => _processNextFrame());
      }
    }
  }

  @override
  void dispose() {
    _isRealTimeRunning = false;
    _cameraController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Search: ${widget.searchText}'),
        backgroundColor: _matchedLines.isNotEmpty ? Colors.green : null,
      ),
      body: Column(
        children: [
          // Status bar
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            color: _matchedLines.isNotEmpty
                ? Colors.green.shade100
                : (_isRealTimeRunning ? Colors.blue.shade100 : Colors.grey.shade200),
            child: Row(
              children: [
                if (_isRealTimeRunning)
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
                      color: _matchedLines.isNotEmpty
                          ? Colors.green.shade800
                          : (_isRealTimeRunning ? Colors.blue.shade800 : Colors.black),
                    ),
                  ),
                ),
                if (_isRealTimeRunning)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.red,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text(
                      'LIVE',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // Camera preview with overlay
          Expanded(
            child: _isCameraInitialized && _cameraController != null
                ? Stack(
                    fit: StackFit.expand,
                    children: [
                      CameraPreview(controller: _cameraController!),
                      if (_imageSize != null && _lastOcrResult != null)
                        CustomPaint(
                          painter: OcrOverlayPainter(
                            matchedLines: _matchedLines,
                            allLines: _lastOcrResult!.results,
                            imageSize: _imageSize!,
                            searchText: widget.searchText,
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

          // Matched results
          if (_matchedLines.isNotEmpty)
            Container(
              constraints: const BoxConstraints(maxHeight: 120),
              color: Colors.green.shade50,
              child: ListView.builder(
                itemCount: _matchedLines.length,
                itemBuilder: (context, index) {
                  final line = _matchedLines[index];
                  return ListTile(
                    dense: true,
                    leading: const Icon(Icons.check_circle, color: Colors.green, size: 20),
                    title: Text(
                      line.text,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    subtitle: Text(
                      'Confidence: ${(line.score * 100).toStringAsFixed(1)}%',
                      style: const TextStyle(fontSize: 12),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

class CameraPreview extends StatelessWidget {
  final CameraController controller;

  const CameraPreview({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: controller.value.previewSize?.height ?? 0,
          height: controller.value.previewSize?.width ?? 0,
          child: controller.buildPreview(),
        ),
      ),
    );
  }
}

class OcrOverlayPainter extends CustomPainter {
  final List<TextLine> matchedLines;
  final List<TextLine> allLines;
  final Size imageSize;
  final String searchText;

  OcrOverlayPainter({
    required this.matchedLines,
    required this.allLines,
    required this.imageSize,
    required this.searchText,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (imageSize.width == 0 || imageSize.height == 0) return;

    final scaleX = size.width / imageSize.width;
    final scaleY = size.height / imageSize.height;

    // Draw all detected text boxes (faint)
    final allPaint = Paint()
      ..color = Colors.blue.withOpacity(0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    for (final line in allLines) {
      final rect = Rect.fromLTRB(
        line.x1 * scaleX,
        line.y1 * scaleY,
        line.x2 * scaleX,
        line.y2 * scaleY,
      );
      canvas.drawRect(rect, allPaint);
    }

    // Draw matched text boxes (highlighted) - using precise word-level boxes
    final matchPaint = Paint()
      ..color = Colors.green
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;

    final matchFillPaint = Paint()
      ..color = Colors.green.withOpacity(0.2)
      ..style = PaintingStyle.fill;

    for (final line in matchedLines) {
      // Use precise word-level bounding box directly
      final rect = Rect.fromLTRB(
        line.x1 * scaleX,
        line.y1 * scaleY,
        line.x2 * scaleX,
        line.y2 * scaleY,
      );

      canvas.drawRect(rect, matchFillPaint);
      canvas.drawRect(rect, matchPaint);

      // Draw label
      final textSpan = TextSpan(
        text: ' FOUND ',
        style: TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.bold,
          backgroundColor: Colors.green,
        ),
      );
      final textPainter = TextPainter(
        text: textSpan,
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset(rect.left, rect.top - textPainter.height - 2),
      );
    }
  }

  @override
  bool shouldRepaint(covariant OcrOverlayPainter oldDelegate) {
    return matchedLines != oldDelegate.matchedLines ||
        allLines != oldDelegate.allLines ||
        searchText != oldDelegate.searchText;
  }
}

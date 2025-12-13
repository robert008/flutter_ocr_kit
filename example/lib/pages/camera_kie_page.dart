import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import 'package:flutter_ocr_kit/flutter_ocr_kit.dart';

import '../painters/kie_camera_overlay_painter.dart';

/// Camera KIE Page - Real-time KIE extraction
class CameraKiePage extends StatefulWidget {
  final List<EntityType> enabledTypes;

  const CameraKiePage({super.key, required this.enabledTypes});

  @override
  State<CameraKiePage> createState() => _CameraKiePageState();
}

class _CameraKiePageState extends State<CameraKiePage> {
  CameraController? _cameraController;
  List<CameraDescription>? _cameras;
  bool _isCameraInitialized = false;
  bool _isProcessing = false;
  bool _isRealTimeRunning = false;
  String _status = 'Initializing camera...';

  OcrResult? _lastOcrResult;
  KieResult? _lastKieResult;
  Size? _imageSize;

  final SimpleKieExtractor _kieExtractor = SimpleKieExtractor();

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
        _isRealTimeRunning = true;
        _status = 'Starting KIE...';
        _frameCount = 0;
        _fpsStartTime = DateTime.now();
      });

      _processNextFrame();
    } catch (e) {
      setState(() => _status = 'Camera init failed: $e');
    }
  }

  Future<void> _processNextFrame() async {
    if (!_isRealTimeRunning) return;
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

      // Run OCR
      final ocrResult = await OcrKit.recognizeNative(file.path);

      // Run KIE extraction
      final kieResult = _kieExtractor.extract(
        ocrResult,
        enabledTypes: widget.enabledTypes,
      );

      // Update FPS
      _frameCount++;
      final elapsed = DateTime.now().difference(_fpsStartTime!).inMilliseconds;
      if (elapsed > 0) {
        _currentFps = (_frameCount / elapsed) * 1000;
      }

      if (mounted) {
        setState(() {
          _lastOcrResult = ocrResult;
          _lastKieResult = kieResult;
          _imageSize = Size(
            ocrResult.imageWidth.toDouble(),
            ocrResult.imageHeight.toDouble(),
          );

          if (kieResult.isNotEmpty) {
            _status =
                'Found ${kieResult.count} entities | ${ocrResult.inferenceTimeMs}ms | ${_currentFps.toStringAsFixed(1)} FPS';
          } else {
            _status =
                '${ocrResult.count} texts | ${ocrResult.inferenceTimeMs}ms | ${_currentFps.toStringAsFixed(1)} FPS';
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
      if (_isRealTimeRunning && mounted) {
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
        title: Text(
          'KIE: ${widget.enabledTypes.map((t) => t.label).join(", ")}',
        ),
        backgroundColor:
            _lastKieResult?.isNotEmpty == true ? Colors.green : null,
      ),
      body: Column(
        children: [
          // Status bar
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            color: _lastKieResult?.isNotEmpty == true
                ? Colors.green.shade100
                : (_isRealTimeRunning
                    ? Colors.blue.shade100
                    : Colors.grey.shade200),
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
                      fontSize: 12,
                      color: _lastKieResult?.isNotEmpty == true
                          ? Colors.green.shade800
                          : Colors.black,
                    ),
                  ),
                ),
                if (_isRealTimeRunning)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
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
                      _CameraPreview(controller: _cameraController!),
                      if (_imageSize != null && _lastKieResult != null)
                        CustomPaint(
                          painter: KieCameraOverlayPainter(
                            entities: _lastKieResult!.entities,
                            imageSize: _imageSize!,
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

          // Extracted entities
          if (_lastKieResult?.isNotEmpty == true)
            Container(
              constraints: const BoxConstraints(maxHeight: 150),
              color: Colors.grey.shade100,
              child: ListView(
                padding: const EdgeInsets.all(8),
                children: _lastKieResult!.byType.entries.map((entry) {
                  final type = entry.key;
                  final entities = entry.value;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: type.color,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            type.label,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Wrap(
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
                                    visualDensity: VisualDensity.compact,
                                    materialTapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                  ),
                                )
                                .toList(),
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
        ],
      ),
    );
  }
}

class _CameraPreview extends StatelessWidget {
  final CameraController controller;

  const _CameraPreview({required this.controller});

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

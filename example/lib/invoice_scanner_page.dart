import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import 'package:flutter_ocr_kit/flutter_ocr_kit.dart';

import 'invoice_list_page.dart';

/// Camera Invoice Scanner Page
///
/// Real-time scanning with:
/// - OCR text recognition
/// - Invoice info extraction
/// - Duplicate detection (by invoice number)
/// - Results stored in memory
class InvoiceScannerPage extends StatefulWidget {
  const InvoiceScannerPage({super.key});

  @override
  State<InvoiceScannerPage> createState() => _InvoiceScannerPageState();
}

class _InvoiceScannerPageState extends State<InvoiceScannerPage> {
  CameraController? _cameraController;
  List<CameraDescription>? _cameras;
  bool _isCameraInitialized = false;
  bool _isProcessing = false;
  bool _isScanning = true;
  String _status = 'Initializing camera...';

  // OCR & Invoice extraction
  final InvoiceExtractor _extractor = InvoiceExtractor();
  InvoiceInfo? _lastInvoice;
  OcrResult? _lastOcrResult;
  Size? _imageSize;

  // Scanned invoices storage (deduplicated by unique key)
  final Map<String, ScannedInvoice> _scannedInvoices = {};

  /// Generate unique key for deduplication
  /// Uses only the 8-digit portion of invoice number
  String _getDedupeKey(InvoiceInfo info) {
    return info.invoiceNumber!.replaceAll(RegExp(r'[^0-9]'), '');
  }

  // FPS tracking
  int _frameCount = 0;
  double _currentFps = 0;
  DateTime? _fpsStartTime;

  // Last added invoice (for UI feedback)
  String? _lastAddedInvoice;
  DateTime? _lastAddedTime;

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
        _isScanning = true;
        _status = 'Scanning...';
        _frameCount = 0;
        _fpsStartTime = DateTime.now();
      });

      _processNextFrame();
    } catch (e) {
      setState(() => _status = 'Camera init failed: $e');
    }
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

      // Run OCR
      final ocrResult = await OcrKit.recognizeNative(file.path);

      // Extract invoice info
      final invoiceInfo = _extractor.extract(ocrResult);

      // Update FPS
      _frameCount++;
      final elapsed = DateTime.now().difference(_fpsStartTime!).inMilliseconds;
      if (elapsed > 0) {
        _currentFps = (_frameCount / elapsed) * 1000;
      }

      // Check if valid and not duplicate
      if (invoiceInfo.isValid) {
        final dedupeKey = _getDedupeKey(invoiceInfo);
        if (!_scannedInvoices.containsKey(dedupeKey)) {
          // New invoice found!
          final scanned = ScannedInvoice.fromInfo(invoiceInfo);
          _scannedInvoices[dedupeKey] = scanned;
          _lastAddedInvoice = invoiceInfo.invoiceNumber;
          _lastAddedTime = DateTime.now();
        } else {
          // Update existing invoice with new high-confidence data
          _scannedInvoices[dedupeKey]!.updateFrom(invoiceInfo);
        }
      }

      // Clear "just added" feedback after 2 seconds
      if (_lastAddedTime != null &&
          DateTime.now().difference(_lastAddedTime!).inSeconds >= 2) {
        _lastAddedInvoice = null;
      }

      if (mounted) {
        setState(() {
          _lastOcrResult = ocrResult;
          _lastInvoice = invoiceInfo;
          _imageSize = Size(
            ocrResult.imageWidth.toDouble(),
            ocrResult.imageHeight.toDouble(),
          );

          if (invoiceInfo.isValid) {
            _status = '${invoiceInfo.invoiceNumber} | ${invoiceInfo.displayAmount}';
          } else {
            _status = '${ocrResult.count} texts | ${_currentFps.toStringAsFixed(1)} FPS';
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
    setState(() {
      _isScanning = !_isScanning;
      if (_isScanning) {
        _frameCount = 0;
        _fpsStartTime = DateTime.now();
        _processNextFrame();
      }
    });
  }

  void _viewResults() {
    // Pause scanning when viewing results
    setState(() {
      _isScanning = false;
    });

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => InvoiceListPage(
          invoices: _scannedInvoices.values.toList(),
        ),
      ),
    );
  }

  void _clearAll() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear All'),
        content: Text('Delete all ${_scannedInvoices.length} scanned invoices?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              setState(() {
                _scannedInvoices.clear();
                _lastAddedInvoice = null;
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
    final invoiceCount = _scannedInvoices.length;
    final totalAmount = _scannedInvoices.values
        .where((i) => i.amount != null)
        .fold<int>(0, (sum, i) => sum + i.amount!);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Invoice Scanner'),
        backgroundColor: _lastInvoice?.isValid == true ? Colors.green : Colors.deepOrange,
        foregroundColor: Colors.white,
        actions: [
          if (invoiceCount > 0)
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
            color: _lastInvoice?.isValid == true
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
                      color: _lastInvoice?.isValid == true
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

                      // Invoice highlight overlay
                      if (_imageSize != null && _lastInvoice?.isValid == true)
                        CustomPaint(
                          painter: _InvoiceOverlayPainter(
                            invoice: _lastInvoice!,
                            imageSize: _imageSize!,
                          ),
                        ),

                      // "Just added" feedback
                      if (_lastAddedInvoice != null)
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
                                    'Added: $_lastAddedInvoice',
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

          // Bottom panel: scanned count + view results button
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
                        icon: Icons.receipt_long,
                        label: 'Invoices',
                        value: '$invoiceCount',
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
                          onPressed: _toggleScanning,
                          icon: Icon(_isScanning ? Icons.pause : Icons.play_arrow),
                          label: Text(_isScanning ? 'Pause' : 'Resume'),
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
                          onPressed: invoiceCount > 0 ? _viewResults : null,
                          icon: const Icon(Icons.list),
                          label: Text('View Results ($invoiceCount)'),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            backgroundColor: Colors.deepOrange,
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
        Icon(icon, size: 28, color: Colors.deepOrange),
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

/// Overlay painter for highlighting detected invoice
class _InvoiceOverlayPainter extends CustomPainter {
  final InvoiceInfo invoice;
  final Size imageSize;

  _InvoiceOverlayPainter({required this.invoice, required this.imageSize});

  @override
  void paint(Canvas canvas, Size size) {
    if (imageSize.width == 0 || imageSize.height == 0) return;

    final scaleX = size.width / imageSize.width;
    final scaleY = size.height / imageSize.height;

    // Draw invoice number box
    if (invoice.invoiceNumberRect != null) {
      final rect = invoice.invoiceNumberRect!;
      final scaledRect = Rect.fromLTRB(
        rect.left * scaleX,
        rect.top * scaleY,
        rect.right * scaleX,
        rect.bottom * scaleY,
      );

      final fillPaint = Paint()
        ..color = Colors.green.withOpacity(0.3)
        ..style = PaintingStyle.fill;

      final strokePaint = Paint()
        ..color = Colors.green
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3;

      canvas.drawRect(scaledRect, fillPaint);
      canvas.drawRect(scaledRect, strokePaint);

      // Label
      _drawLabel(canvas, scaledRect, 'Invoice', Colors.green);
    }

    // Draw amount box
    if (invoice.amountRect != null) {
      final rect = invoice.amountRect!;
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

      // Label
      _drawLabel(canvas, scaledRect, 'Amount', Colors.orange);
    }
  }

  void _drawLabel(Canvas canvas, Rect rect, String text, Color color) {
    final textSpan = TextSpan(
      text: ' $text ',
      style: TextStyle(
        color: Colors.white,
        fontSize: 12,
        fontWeight: FontWeight.bold,
        backgroundColor: color,
      ),
    );
    final textPainter = TextPainter(
      text: textSpan,
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();

    final labelY = rect.top - textPainter.height - 2;
    textPainter.paint(
      canvas,
      Offset(rect.left, labelY > 0 ? labelY : rect.top),
    );
  }

  @override
  bool shouldRepaint(covariant _InvoiceOverlayPainter oldDelegate) {
    return invoice != oldDelegate.invoice || imageSize != oldDelegate.imageSize;
  }
}

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'package:flutter_ocr_kit/flutter_ocr_kit.dart';

import 'quotation_list_page.dart';

/// Demo quotation images
const List<String> _demoQuotations = [
  'assets/quotation_1.png',
  'assets/quotation_2.png',
  'assets/quotation_3.png',
];

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

/// Quotation Scanner Page
///
/// Scan quotations/delivery notes using:
/// - Layout Detection (find Table regions)
/// - OCR (extract text)
/// - QuotationExtractor (parse structured data)
class QuotationScannerPage extends StatefulWidget {
  final Map<String, ScannedQuotation> sharedStorage;

  const QuotationScannerPage({
    super.key,
    required this.sharedStorage,
  });

  @override
  State<QuotationScannerPage> createState() => _QuotationScannerPageState();
}

class _QuotationScannerPageState extends State<QuotationScannerPage> {
  String? _layoutModelPath;
  String _status = 'Initializing...';
  bool _isProcessing = false;
  bool _isLayoutInitialized = false;
  bool _isInitializing = false;

  String? _currentImagePath;
  LayoutResult? _layoutResult;
  OcrResult? _ocrResult;
  QuotationInfo? _lastQuotation;

  final QuotationExtractor _extractor = QuotationExtractor();

  // Track which demo images have been processed
  final Set<int> _processedImages = {};

  // Last added time (for UI feedback timing)
  DateTime? _lastAddedTime;

  /// Generate unique key for deduplication
  /// Uses only the numeric portion of quotation number
  String _getDedupeKey(String quotationNumber) {
    return quotationNumber.replaceAll(RegExp(r'[^0-9]'), '');
  }

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
        _status = 'Ready (warmup: ${warmupTime}ms). Select a demo image.';
      });
    } catch (e) {
      setState(() {
        _isInitializing = false;
        _status = 'Failed to init: $e';
      });
    }
  }

  Future<void> _processAsset(int index) async {
    if (_isProcessing || !_isLayoutInitialized) return;
    if (index < 0 || index >= _demoQuotations.length) return;

    final assetPath = _demoQuotations[index];

    // Copy asset to temp file
    final data = await rootBundle.load(assetPath);
    final bytes = data.buffer.asUint8List();
    final appDir = await getApplicationDocumentsDirectory();
    final tempPath = '${appDir.path}/temp_quotation_$index.png';
    await File(tempPath).writeAsBytes(bytes);

    _processedImages.add(index);
    await _processImage(tempPath);
  }

  Future<void> _processImage(String imagePath) async {
    setState(() {
      _isProcessing = true;
      _status = 'Processing...';
      _currentImagePath = imagePath;
      _layoutResult = null;
      _ocrResult = null;
      _lastQuotation = null;
    });

    try {
      // Step 1: Layout Detection
      setState(() => _status = 'Running Layout Detection...');
      final layoutJson = await compute(_detectLayoutInBackground, {
        'modelPath': _layoutModelPath!,
        'imagePath': imagePath,
      });
      final layoutResult = LayoutResult.fromJson(layoutJson);

      // Step 2: OCR
      setState(() => _status = 'Running OCR...');
      final ocrResult = await OcrKit.recognizeNative(imagePath);

      // Step 3: Extract quotation info
      setState(() => _status = 'Extracting quotation data...');
      final quotationInfo = _extractor.extract(ocrResult, layoutResult: layoutResult);

      // Check if valid and meets confidence threshold
      // Confidence threshold for adding new entries
      const double addThreshold = 0.60;

      debugPrint('[QuotationScanner] OCR confidence: ${(quotationInfo.confidence * 100).toStringAsFixed(1)}%, isValid: ${quotationInfo.isValid}, number: ${quotationInfo.quotationNumber}');

      if (quotationInfo.isValid) {
        final dedupeKey = _getDedupeKey(quotationInfo.quotationNumber!);
        if (!widget.sharedStorage.containsKey(dedupeKey)) {
          // Only add new entry if confidence >= 90%
          if (quotationInfo.confidence >= addThreshold) {
            final scanned = ScannedQuotation.fromInfo(quotationInfo);
            widget.sharedStorage[dedupeKey] = scanned;
            _lastAddedTime = DateTime.now();
            debugPrint('[QuotationScanner] Added new: ${quotationInfo.quotationNumber} (conf: ${(quotationInfo.confidence * 100).toStringAsFixed(1)}%)');
          } else {
            debugPrint('[QuotationScanner] Skipped (low confidence): ${quotationInfo.quotationNumber} (conf: ${(quotationInfo.confidence * 100).toStringAsFixed(1)}%)');
          }
        } else {
          // Update existing (threshold check is inside updateFrom)
          widget.sharedStorage[dedupeKey]!.updateFrom(quotationInfo);
          debugPrint('[QuotationScanner] Updated: ${quotationInfo.quotationNumber} (conf: ${(quotationInfo.confidence * 100).toStringAsFixed(1)}%)');
        }
      }

      // Clear feedback timing after 3 seconds
      if (_lastAddedTime != null &&
          DateTime.now().difference(_lastAddedTime!).inSeconds >= 3) {
        _lastAddedTime = null;
      }

      setState(() {
        _layoutResult = layoutResult;
        _ocrResult = ocrResult;
        _lastQuotation = quotationInfo;
        _isProcessing = false;

        if (quotationInfo.isValid) {
          _status = '${quotationInfo.quotationNumber} | ${quotationInfo.displayTotal} | ${quotationInfo.itemCount} items';
        } else {
          _status = 'Layout: ${layoutResult.count} regions, OCR: ${ocrResult.count} texts';
        }
      });

      // Log results
      debugPrint('========== QUOTATION EXTRACTION ==========');
      debugPrint('Quotation Number: ${quotationInfo.quotationNumber}');
      debugPrint('Date: ${quotationInfo.quotationDate}');
      debugPrint('Customer: ${quotationInfo.customerName}');
      debugPrint('Order Number: ${quotationInfo.orderNumber}');
      debugPrint('Items: ${quotationInfo.items.length}');
      for (final item in quotationInfo.items) {
        debugPrint('  - ${item.name}: ${item.quantity} x \$${item.unitPrice} = \$${item.amount}');
      }
      debugPrint('Subtotal: ${quotationInfo.subtotal}');
      debugPrint('Tax: ${quotationInfo.tax}');
      debugPrint('Total: ${quotationInfo.total}');
      debugPrint('==========================================');

    } catch (e) {
      setState(() {
        _status = 'Error: $e';
        _isProcessing = false;
      });
    }
  }

  void _viewResults() {
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
                _processedImages.clear();
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
  Widget build(BuildContext context) {
    final quotationCount = widget.sharedStorage.length;
    final totalAmount = widget.sharedStorage.values
        .where((q) => q.total != null)
        .fold<int>(0, (sum, q) => sum + q.total!);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Quotation Scanner'),
        backgroundColor: _lastQuotation?.isValid == true ? Colors.green : Colors.purple,
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
          // Scrollable content area
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  // Status bar
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    color: _lastQuotation?.isValid == true
                        ? Colors.green.shade100
                        : (_isProcessing || _isInitializing
                            ? Colors.blue.shade100
                            : Colors.grey.shade200),
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
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              color: _lastQuotation?.isValid == true
                                  ? Colors.green.shade800
                                  : Colors.black,
                            ),
                          ),
                        ),
                        if (_lastQuotation?.isValid == true)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.green,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Text(
                              'VALID',
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

                  // Image preview area
                  if (_currentImagePath != null && _ocrResult != null)
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final imageWidth = _ocrResult!.imageWidth.toDouble();
                          final imageHeight = _ocrResult!.imageHeight.toDouble();
                          final aspectRatio = imageWidth / imageHeight;

                          // Use full available width, calculate height by aspect ratio
                          final displayWidth = constraints.maxWidth;
                          final displayHeight = displayWidth / aspectRatio;
                          final scale = displayWidth / imageWidth;

                          return SizedBox(
                            width: displayWidth,
                            height: displayHeight,
                            child: Stack(
                              children: [
                                Image.file(
                                  File(_currentImagePath!),
                                  width: displayWidth,
                                  height: displayHeight,
                                  fit: BoxFit.fill,
                                ),
                                if (_layoutResult != null)
                                  CustomPaint(
                                    size: Size(displayWidth, displayHeight),
                                    painter: _QuotationOverlayPainter(
                                      layoutResult: _layoutResult!,
                                      quotationInfo: _lastQuotation,
                                      scale: scale,
                                    ),
                                  ),
                              ],
                            ),
                          );
                        },
                      ),
                    )
                  else if (_isInitializing)
                    const Padding(
                      padding: EdgeInsets.all(64),
                      child: CircularProgressIndicator(),
                    )
                  else
                    Padding(
                      padding: const EdgeInsets.all(64),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.description,
                            size: 64,
                            color: Colors.grey.shade400,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Select a demo image below to scan',
                            style: TextStyle(
                              color: Colors.grey.shade600,
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                    ),

                  // Quotation details panel
                  if (_lastQuotation?.isValid == true)
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 8),
                      child: Card(
                        color: Colors.green.shade50,
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            children: [
                              _buildInfoRow('Quotation #', _lastQuotation!.quotationNumber ?? '-'),
                              _buildInfoRow('Date', _lastQuotation!.quotationDate ?? '-'),
                              _buildInfoRow('Customer', _lastQuotation!.customerName ?? '-'),
                              _buildInfoRow('Items', '${_lastQuotation!.itemCount}'),
                              _buildInfoRow('Total', _lastQuotation!.displayTotal),
                            ],
                          ),
                        ),
                      ),
                    ),

                  const SizedBox(height: 16),
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
                  color: Colors.black.withValues(alpha: 0.1),
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

                  // Demo images row
                  Row(
                    children: List.generate(_demoQuotations.length, (index) {
                      final isProcessed = _processedImages.contains(index);
                      return Expanded(
                        child: Padding(
                          padding: EdgeInsets.only(
                            left: index == 0 ? 0 : 4,
                            right: index == _demoQuotations.length - 1 ? 0 : 4,
                          ),
                          child: InkWell(
                            onTap: (!_isProcessing && _isLayoutInitialized)
                                ? () => _processAsset(index)
                                : null,
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              height: 120,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: isProcessed ? Colors.green : Colors.grey.shade300,
                                  width: isProcessed ? 2 : 1,
                                ),
                              ),
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(7),
                                    child: Image.asset(
                                      _demoQuotations[index],
                                      fit: BoxFit.cover,
                                    ),
                                  ),
                                  if (isProcessed)
                                    Positioned(
                                      top: 4,
                                      right: 4,
                                      child: Container(
                                        padding: const EdgeInsets.all(2),
                                        decoration: const BoxDecoration(
                                          color: Colors.green,
                                          shape: BoxShape.circle,
                                        ),
                                        child: const Icon(
                                          Icons.check,
                                          color: Colors.white,
                                          size: 12,
                                        ),
                                      ),
                                    ),
                                  if (!_isLayoutInitialized || _isProcessing)
                                    Container(
                                      decoration: BoxDecoration(
                                        color: Colors.black.withValues(alpha: 0.3),
                                        borderRadius: BorderRadius.circular(7),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
                  const SizedBox(height: 12),

                  // View results button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: quotationCount > 0 ? _viewResults : null,
                      icon: const Icon(Icons.list),
                      label: Text('View Results ($quotationCount)'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        backgroundColor: Colors.purple.shade700,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: TextStyle(
                color: Colors.grey.shade700,
                fontSize: 13,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
          ),
        ],
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
        Icon(icon, size: 28, color: Colors.purple),
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

/// Overlay painter for quotation
class _QuotationOverlayPainter extends CustomPainter {
  final LayoutResult layoutResult;
  final QuotationInfo? quotationInfo;
  final double scale;

  _QuotationOverlayPainter({
    required this.layoutResult,
    this.quotationInfo,
    this.scale = 1.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Draw Layout regions
    for (final region in layoutResult.detections) {
      final color = _getRegionColor(region.className);

      final fillPaint = Paint()
        ..color = color.withValues(alpha: 0.15)
        ..style = PaintingStyle.fill;

      final borderPaint = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2 * scale;

      final rect = Rect.fromLTRB(
        region.x1 * scale,
        region.y1 * scale,
        region.x2 * scale,
        region.y2 * scale,
      );
      canvas.drawRect(rect, fillPaint);
      canvas.drawRect(rect, borderPaint);

      // Label
      final labelSpan = TextSpan(
        text: ' ${region.className} ',
        style: TextStyle(
          color: Colors.white,
          fontSize: 14 * scale,
          fontWeight: FontWeight.bold,
          backgroundColor: color,
        ),
      );
      final labelPainter = TextPainter(
        text: labelSpan,
        textDirection: TextDirection.ltr,
      );
      labelPainter.layout();
      final labelY = region.y1 * scale - labelPainter.height - 4;
      labelPainter.paint(
        canvas,
        Offset(region.x1 * scale, labelY > 0 ? labelY : region.y1 * scale),
      );
    }

    // Highlight quotation number if found
    if (quotationInfo?.quotationNumberRect != null) {
      final originalRect = quotationInfo!.quotationNumberRect!;
      final rect = Rect.fromLTRB(
        originalRect.left * scale,
        originalRect.top * scale,
        originalRect.right * scale,
        originalRect.bottom * scale,
      );

      final highlightPaint = Paint()
        ..color = Colors.green.withValues(alpha: 0.3)
        ..style = PaintingStyle.fill;

      final borderPaint = Paint()
        ..color = Colors.green
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3 * scale;

      canvas.drawRect(rect, highlightPaint);
      canvas.drawRect(rect, borderPaint);
    }
  }

  Color _getRegionColor(String className) {
    switch (className.toLowerCase()) {
      case 'table':
        return const Color(0xFF4CAF50);
      case 'text':
        return const Color(0xFF2196F3);
      case 'title':
      case 'doc_title':
        return const Color(0xFFFF9800);
      case 'paragraph_title':
        return const Color(0xFFE91E63);
      case 'figure':
        return const Color(0xFF9C27B0);
      default:
        return const Color(0xFF9E9E9E);
    }
  }

  @override
  bool shouldRepaint(covariant _QuotationOverlayPainter oldDelegate) {
    return layoutResult != oldDelegate.layoutResult ||
        quotationInfo != oldDelegate.quotationInfo ||
        scale != oldDelegate.scale;
  }
}

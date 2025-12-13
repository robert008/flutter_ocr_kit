import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'package:flutter_ocr_kit/flutter_ocr_kit.dart';

import '../painters/image_ocr_overlay_painter.dart';

/// Image OCR Page - Separate page for image OCR
class ImageOcrPage extends StatefulWidget {
  final String assetPath;
  final String searchText;

  const ImageOcrPage({
    super.key,
    required this.assetPath,
    this.searchText = '',
  });

  @override
  State<ImageOcrPage> createState() => _ImageOcrPageState();
}

class _ImageOcrPageState extends State<ImageOcrPage> {
  String? _imagePath;
  String _status = 'Loading...';
  bool _isProcessing = true;
  OcrResult? _ocrResult;
  List<TextLine> _matchedLines = [];

  @override
  void initState() {
    super.initState();
    _runOcr();
  }

  Future<void> _runOcr() async {
    try {
      // Load image from assets
      final data = await rootBundle.load(widget.assetPath);
      final imageBytes = data.buffer.asUint8List();

      final appDir = await getApplicationDocumentsDirectory();
      final fileName = 'ocr_${widget.assetPath.split('/').last}';
      final imagePath = '${appDir.path}/$fileName';
      await File(imagePath).writeAsBytes(imageBytes);

      setState(() {
        _imagePath = imagePath;
        _status = 'Running OCR...';
      });

      // Run OCR
      final result = await OcrKit.recognizeNative(imagePath);

      // Find matches if search text provided (use precise word-level boxes)
      List<TextLine> matches = [];
      if (widget.searchText.isNotEmpty) {
        matches = result.findTextPrecise(widget.searchText);
      }

      setState(() {
        _ocrResult = result;
        _matchedLines = matches;
        _isProcessing = false;
        _status = 'OCR: ${result.inferenceTimeMs}ms, ${result.count} texts';
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
          widget.searchText.isEmpty
              ? 'Image OCR'
              : 'Search: ${widget.searchText}',
        ),
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
                      color: _matchedLines.isNotEmpty
                          ? Colors.green.shade800
                          : Colors.black,
                    ),
                  ),
                ),
                if (_matchedLines.isNotEmpty)
                  Chip(
                    label: Text('${_matchedLines.length} FOUND'),
                    backgroundColor: Colors.green,
                    labelStyle: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                    ),
                  ),
              ],
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
                            CustomPaint(
                              size: Size(
                                _ocrResult!.imageWidth.toDouble(),
                                _ocrResult!.imageHeight.toDouble(),
                              ),
                              painter: ImageOcrOverlayPainter(
                                matchedLines: _matchedLines,
                                allLines: _ocrResult!.results,
                                showAllBoxes: widget.searchText.isEmpty,
                                searchText: widget.searchText,
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
          else if (_imagePath != null)
            Expanded(
              flex: 2,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Image.file(File(_imagePath!), fit: BoxFit.contain),
              ),
            ),

          // OCR Results
          if (_ocrResult != null)
            Expanded(
              flex: 3,
              child: Card(
                margin: const EdgeInsets.all(8),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            'OCR Result (${_ocrResult!.count} lines)',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const Spacer(),
                          IconButton(
                            icon: const Icon(Icons.copy, size: 18),
                            onPressed: () {
                              final allText = _ocrResult!.results
                                  .map((l) => l.text)
                                  .join('\n');
                              Clipboard.setData(ClipboardData(text: allText));
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Copied to clipboard'),
                                ),
                              );
                            },
                            tooltip: 'Copy all text',
                          ),
                        ],
                      ),
                      const Divider(),
                      Expanded(
                        child: SingleChildScrollView(
                          child: SelectableText(
                            _ocrResult!.results.isEmpty
                                ? '(No text recognized)'
                                : _ocrResult!.results
                                    .map((l) => l.text)
                                    .join('\n'),
                            style: const TextStyle(
                              fontSize: 14,
                              fontFamily: 'monospace',
                            ),
                          ),
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
}

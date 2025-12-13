import 'package:flutter/material.dart';

import 'package:flutter_ocr_kit/flutter_ocr_kit.dart';

/// Image OCR Overlay Painter
class ImageOcrOverlayPainter extends CustomPainter {
  final List<TextLine> matchedLines;
  final List<TextLine> allLines;
  final bool showAllBoxes;
  final String searchText;

  ImageOcrOverlayPainter({
    required this.matchedLines,
    required this.allLines,
    this.showAllBoxes = false,
    this.searchText = '',
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Draw all detected text boxes (faint blue)
    if (showAllBoxes || matchedLines.isEmpty) {
      final allPaint = Paint()
        ..color = Colors.blue.withOpacity(0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;

      for (final line in allLines) {
        final rect = Rect.fromLTRB(line.x1, line.y1, line.x2, line.y2);
        canvas.drawRect(rect, allPaint);
      }
    }

    // Draw matched text boxes (highlighted green) - using precise word-level boxes
    if (matchedLines.isNotEmpty && searchText.isNotEmpty) {
      final matchPaint = Paint()
        ..color = Colors.green
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4;

      final matchFillPaint = Paint()
        ..color = Colors.green.withOpacity(0.3)
        ..style = PaintingStyle.fill;

      for (final line in matchedLines) {
        // Use precise word-level bounding box directly
        final rect = line.rect;

        canvas.drawRect(rect, matchFillPaint);
        canvas.drawRect(rect, matchPaint);

        // Draw "FOUND" label
        final textSpan = TextSpan(
          text: ' FOUND ',
          style: TextStyle(
            color: Colors.white,
            fontSize: 24,
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
          Offset(rect.left, rect.top - textPainter.height - 4),
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant ImageOcrOverlayPainter oldDelegate) {
    return matchedLines != oldDelegate.matchedLines ||
        allLines != oldDelegate.allLines ||
        showAllBoxes != oldDelegate.showAllBoxes ||
        searchText != oldDelegate.searchText;
  }
}

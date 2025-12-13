import 'package:flutter/material.dart';

import 'package:flutter_ocr_kit/flutter_ocr_kit.dart';

/// KIE Overlay Painter
class KieOverlayPainter extends CustomPainter {
  final List<ExtractedEntity> entities;

  KieOverlayPainter({required this.entities});

  @override
  void paint(Canvas canvas, Size size) {
    for (final entity in entities) {
      final color = entity.type.color;

      // Fill
      final fillPaint = Paint()
        ..color = color.withOpacity(0.3)
        ..style = PaintingStyle.fill;

      // Stroke
      final strokePaint = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;

      canvas.drawRect(entity.rect, fillPaint);
      canvas.drawRect(entity.rect, strokePaint);

      // Label
      final textSpan = TextSpan(
        text: ' ${entity.type.label} ',
        style: TextStyle(
          color: Colors.white,
          fontSize: 16,
          fontWeight: FontWeight.bold,
          backgroundColor: color,
        ),
      );
      final textPainter = TextPainter(
        text: textSpan,
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();

      // Position label above the box
      final labelY = entity.y1 - textPainter.height - 2;
      textPainter.paint(
        canvas,
        Offset(entity.x1, labelY > 0 ? labelY : entity.y1),
      );
    }
  }

  @override
  bool shouldRepaint(covariant KieOverlayPainter oldDelegate) {
    return entities != oldDelegate.entities;
  }
}

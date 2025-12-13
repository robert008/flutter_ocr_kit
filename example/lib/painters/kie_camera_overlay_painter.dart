import 'package:flutter/material.dart';

import 'package:flutter_ocr_kit/flutter_ocr_kit.dart';

/// KIE Camera Overlay Painter (scaled)
class KieCameraOverlayPainter extends CustomPainter {
  final List<ExtractedEntity> entities;
  final Size imageSize;

  KieCameraOverlayPainter({required this.entities, required this.imageSize});

  @override
  void paint(Canvas canvas, Size size) {
    if (imageSize.width == 0 || imageSize.height == 0) return;

    final scaleX = size.width / imageSize.width;
    final scaleY = size.height / imageSize.height;

    for (final entity in entities) {
      final color = entity.type.color;

      final rect = Rect.fromLTRB(
        entity.x1 * scaleX,
        entity.y1 * scaleY,
        entity.x2 * scaleX,
        entity.y2 * scaleY,
      );

      final fillPaint = Paint()
        ..color = color.withOpacity(0.3)
        ..style = PaintingStyle.fill;

      final strokePaint = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;

      canvas.drawRect(rect, fillPaint);
      canvas.drawRect(rect, strokePaint);

      // Label
      final textSpan = TextSpan(
        text: ' ${entity.type.label} ',
        style: TextStyle(
          color: Colors.white,
          fontSize: 10,
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
  }

  @override
  bool shouldRepaint(covariant KieCameraOverlayPainter oldDelegate) {
    return entities != oldDelegate.entities ||
        imageSize != oldDelegate.imageSize;
  }
}

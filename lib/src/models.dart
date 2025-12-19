import 'dart:ui';

/// Detection bounding box (for layout detection)
class DetectionBox {
  final double x1;
  final double y1;
  final double x2;
  final double y2;
  final double score;
  final int classId;
  final String className;

  DetectionBox({
    required this.x1,
    required this.y1,
    required this.x2,
    required this.y2,
    required this.score,
    required this.classId,
    required this.className,
  });

  double get width => x2 - x1;
  double get height => y2 - y1;

  Rect get rect => Rect.fromLTRB(x1, y1, x2, y2);

  factory DetectionBox.fromJson(Map<String, dynamic> json) {
    return DetectionBox(
      x1: (json['x1'] as num).toDouble(),
      y1: (json['y1'] as num).toDouble(),
      x2: (json['x2'] as num).toDouble(),
      y2: (json['y2'] as num).toDouble(),
      score: (json['score'] as num).toDouble(),
      classId: json['class_id'] as int,
      className: json['class_name'] as String,
    );
  }

  Map<String, dynamic> toJson() => {
    'x1': x1,
    'y1': y1,
    'x2': x2,
    'y2': y2,
    'score': score,
    'class_id': classId,
    'class_name': className,
  };

  @override
  String toString() {
    return 'DetectionBox($className: score=${score.toStringAsFixed(3)})';
  }
}

// ========================
// OCR Models
// ========================

/// Single text line result from OCR
class TextLine {
  final double x1;
  final double y1;
  final double x2;
  final double y2;
  final double score;
  final String text;

  TextLine({
    required this.x1,
    required this.y1,
    required this.x2,
    required this.y2,
    required this.score,
    required this.text,
  });

  double get width => x2 - x1;
  double get height => y2 - y1;

  Rect get rect => Rect.fromLTRB(x1, y1, x2, y2);

  /// Check if this text line contains the search text (case-insensitive)
  bool contains(String searchText, {bool caseSensitive = false}) {
    if (caseSensitive) {
      return text.contains(searchText);
    }
    return text.toLowerCase().contains(searchText.toLowerCase());
  }

  factory TextLine.fromJson(Map<String, dynamic> json) {
    return TextLine(
      x1: (json['x1'] as num).toDouble(),
      y1: (json['y1'] as num).toDouble(),
      x2: (json['x2'] as num).toDouble(),
      y2: (json['y2'] as num).toDouble(),
      score: (json['score'] as num).toDouble(),
      text: json['text'] as String,
    );
  }

  Map<String, dynamic> toJson() => {
    'x1': x1,
    'y1': y1,
    'x2': x2,
    'y2': y2,
    'score': score,
    'text': text,
  };

  @override
  String toString() {
    return 'TextLine("$text": score=${score.toStringAsFixed(3)})';
  }
}

/// OCR recognition result
class OcrResult {
  final List<TextLine> results;
  final List<TextLine> words;  // Word-level bounding boxes for precise highlighting
  final int count;
  final int inferenceTimeMs;
  final int imageWidth;
  final int imageHeight;
  final String? error;

  OcrResult({
    required this.results,
    this.words = const [],
    required this.count,
    required this.inferenceTimeMs,
    required this.imageWidth,
    required this.imageHeight,
    this.error,
  });

  bool get hasError => error != null;
  bool get isSuccess => error == null;

  /// Get all recognized text as a single string
  String get fullText => results.map((r) => r.text).join('\n');

  /// Find all text lines containing the search text
  List<TextLine> findText(String searchText, {bool caseSensitive = false}) {
    return results
        .where((r) => r.contains(searchText, caseSensitive: caseSensitive))
        .toList();
  }

  /// Find matching words with precise bounding boxes
  ///
  /// Returns word-level matches for precise highlighting.
  /// Falls back to line-level if no words available.
  List<TextLine> findTextPrecise(String searchText, {bool caseSensitive = false}) {
    // First try to match at word level for precise boxes
    if (words.isNotEmpty) {
      final wordMatches = words
          .where((w) => w.contains(searchText, caseSensitive: caseSensitive))
          .toList();
      if (wordMatches.isNotEmpty) {
        return wordMatches;
      }
    }

    // Fall back to line-level matches
    return findText(searchText, caseSensitive: caseSensitive);
  }

  factory OcrResult.fromJson(Map<String, dynamic> json) {
    if (json.containsKey('error') && json['error'] != null) {
      return OcrResult(
        results: [],
        words: [],
        count: 0,
        inferenceTimeMs: 0,
        imageWidth: 0,
        imageHeight: 0,
        error: json['error'] as String,
      );
    }

    final resultsJson = json['results'] as List<dynamic>;
    final results = resultsJson
        .map((r) => TextLine.fromJson(r as Map<String, dynamic>))
        .toList();

    // Parse word-level bounding boxes if available
    final wordsJson = json['words'] as List<dynamic>? ?? [];
    final words = wordsJson
        .map((w) => TextLine.fromJson(w as Map<String, dynamic>))
        .toList();

    return OcrResult(
      results: results,
      words: words,
      count: json['count'] as int,
      inferenceTimeMs: json['inference_time_ms'] as int,
      imageWidth: json['image_width'] as int,
      imageHeight: json['image_height'] as int,
    );
  }

  Map<String, dynamic> toJson() {
    if (error != null) {
      return {'error': error};
    }
    return {
      'results': results.map((r) => r.toJson()).toList(),
      'words': words.map((w) => w.toJson()).toList(),
      'count': count,
      'inference_time_ms': inferenceTimeMs,
      'image_width': imageWidth,
      'image_height': imageHeight,
    };
  }

  @override
  String toString() {
    if (hasError) {
      return 'OcrResult(error: $error)';
    }
    return 'OcrResult(count: $count, words: ${words.length}, time: ${inferenceTimeMs}ms)';
  }
}

/// Text box from detection (4 corner points)
class TextBox {
  final List<Offset> points;
  final double score;

  TextBox({
    required this.points,
    required this.score,
  });

  /// Get axis-aligned bounding rectangle
  Rect get boundingRect {
    if (points.isEmpty) return Rect.zero;
    double minX = points[0].dx, maxX = points[0].dx;
    double minY = points[0].dy, maxY = points[0].dy;
    for (final pt in points) {
      if (pt.dx < minX) minX = pt.dx;
      if (pt.dx > maxX) maxX = pt.dx;
      if (pt.dy < minY) minY = pt.dy;
      if (pt.dy > maxY) maxY = pt.dy;
    }
    return Rect.fromLTRB(minX, minY, maxX, maxY);
  }

  factory TextBox.fromJson(Map<String, dynamic> json) {
    final pointsJson = json['points'] as List<dynamic>;
    final points = pointsJson.map((p) {
      final pt = p as List<dynamic>;
      return Offset((pt[0] as num).toDouble(), (pt[1] as num).toDouble());
    }).toList();

    return TextBox(
      points: points,
      score: (json['score'] as num).toDouble(),
    );
  }
}

/// Text detection result (boxes only, without recognition)
class TextDetectionResult {
  final List<TextBox> boxes;
  final int count;
  final int inferenceTimeMs;
  final int imageWidth;
  final int imageHeight;
  final String? error;

  TextDetectionResult({
    required this.boxes,
    required this.count,
    required this.inferenceTimeMs,
    required this.imageWidth,
    required this.imageHeight,
    this.error,
  });

  bool get hasError => error != null;
  bool get isSuccess => error == null;

  factory TextDetectionResult.fromJson(Map<String, dynamic> json) {
    if (json.containsKey('error')) {
      return TextDetectionResult(
        boxes: [],
        count: 0,
        inferenceTimeMs: 0,
        imageWidth: 0,
        imageHeight: 0,
        error: json['error'] as String,
      );
    }

    final boxesJson = json['boxes'] as List<dynamic>;
    final boxes = boxesJson
        .map((b) => TextBox.fromJson(b as Map<String, dynamic>))
        .toList();

    return TextDetectionResult(
      boxes: boxes,
      count: json['count'] as int,
      inferenceTimeMs: json['inference_time_ms'] as int,
      imageWidth: json['image_width'] as int,
      imageHeight: json['image_height'] as int,
    );
  }

  @override
  String toString() {
    if (hasError) {
      return 'TextDetectionResult(error: $error)';
    }
    return 'TextDetectionResult(count: $count, time: ${inferenceTimeMs}ms)';
  }
}

/// Layout detection result (for demo)
class LayoutResult {
  final List<DetectionBox> detections;
  final int count;
  final int inferenceTimeMs;
  final int imageWidth;
  final int imageHeight;
  final String? error;

  LayoutResult({
    required this.detections,
    required this.count,
    required this.inferenceTimeMs,
    required this.imageWidth,
    required this.imageHeight,
    this.error,
  });

  bool get hasError => error != null;
  bool get isSuccess => error == null;

  factory LayoutResult.fromJson(Map<String, dynamic> json) {
    if (json.containsKey('error')) {
      return LayoutResult(
        detections: [],
        count: 0,
        inferenceTimeMs: 0,
        imageWidth: 0,
        imageHeight: 0,
        error: json['error'] as String,
      );
    }

    final detectionsJson = json['detections'] as List<dynamic>;
    final detections = detectionsJson
        .map((d) => DetectionBox.fromJson(d as Map<String, dynamic>))
        .toList();

    return LayoutResult(
      detections: detections,
      count: json['count'] as int,
      inferenceTimeMs: json['inference_time_ms'] as int,
      imageWidth: json['image_width'] as int,
      imageHeight: json['image_height'] as int,
    );
  }

  Map<String, dynamic> toJson() {
    if (error != null) {
      return {'error': error};
    }
    return {
      'detections': detections.map((d) => d.toJson()).toList(),
      'count': count,
      'inference_time_ms': inferenceTimeMs,
      'image_width': imageWidth,
      'image_height': imageHeight,
    };
  }

  @override
  String toString() {
    if (hasError) {
      return 'LayoutResult(error: $error)';
    }
    return 'LayoutResult(count: $count, time: ${inferenceTimeMs}ms)';
  }
}

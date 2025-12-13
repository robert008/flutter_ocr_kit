import 'package:flutter/material.dart';
import 'models.dart';

/// Entity types for KIE extraction
enum EntityType {
  date,
  time,
  phoneMobileTw,
  phoneLandlineTw,
  email,
  currencyAmount,
  percentage,
  url,
  ipAddress,
}

/// Extension for EntityType display properties
extension EntityTypeExtension on EntityType {
  String get label {
    switch (this) {
      case EntityType.date:
        return 'DATE';
      case EntityType.time:
        return 'TIME';
      case EntityType.phoneMobileTw:
        return 'MOBILE';
      case EntityType.phoneLandlineTw:
        return 'LANDLINE';
      case EntityType.email:
        return 'EMAIL';
      case EntityType.currencyAmount:
        return 'AMOUNT';
      case EntityType.percentage:
        return 'PERCENT';
      case EntityType.url:
        return 'URL';
      case EntityType.ipAddress:
        return 'IP';
    }
  }

  Color get color {
    switch (this) {
      case EntityType.date:
        return Colors.blue;
      case EntityType.time:
        return Colors.indigo;
      case EntityType.phoneMobileTw:
        return Colors.green;
      case EntityType.phoneLandlineTw:
        return Colors.teal;
      case EntityType.email:
        return Colors.orange;
      case EntityType.currencyAmount:
        return Colors.red;
      case EntityType.percentage:
        return Colors.purple;
      case EntityType.url:
        return Colors.cyan;
      case EntityType.ipAddress:
        return Colors.brown;
    }
  }
}

/// Extracted entity with bounding box
class ExtractedEntity {
  final EntityType type;
  final String value;
  final TextLine sourceLine;
  final double x1, y1, x2, y2;

  ExtractedEntity({
    required this.type,
    required this.value,
    required this.sourceLine,
    required this.x1,
    required this.y1,
    required this.x2,
    required this.y2,
  });

  Rect get rect => Rect.fromLTRB(x1, y1, x2, y2);

  @override
  String toString() => '${type.label}: $value';
}

/// KIE extraction result
class KieResult {
  final List<ExtractedEntity> entities;
  final Map<EntityType, List<ExtractedEntity>> byType;

  KieResult({required this.entities})
      : byType = _groupByType(entities);

  static Map<EntityType, List<ExtractedEntity>> _groupByType(
      List<ExtractedEntity> entities) {
    final map = <EntityType, List<ExtractedEntity>>{};
    for (final entity in entities) {
      map.putIfAbsent(entity.type, () => []).add(entity);
    }
    return map;
  }

  List<ExtractedEntity> ofType(EntityType type) => byType[type] ?? [];

  int get count => entities.length;

  bool get isEmpty => entities.isEmpty;
  bool get isNotEmpty => entities.isNotEmpty;
}

/// KIE mode for mutual exclusion
enum KieMode {
  none,
  simple,   // Regex-based
  spatial,  // Label + position based (TODO)
  layout,   // Layout region based (TODO)
}

/// Simple KIE Extractor using regex patterns
class SimpleKieExtractor {
  // ============================================
  // Date patterns
  // ============================================
  static final _datePatterns = [
    // ISO format: 2024-01-15, 2024/01/15, 2024.01.15
    RegExp(r'\b\d{4}[-/\.]\d{1,2}[-/\.]\d{1,2}\b'),
    // Chinese format: 2024年1月15日
    RegExp(r'\b\d{4}年\d{1,2}月\d{1,2}日\b'),
    // US format: 01/15/2024, 01-15-2024
    RegExp(r'\b\d{1,2}[-/]\d{1,2}[-/]\d{4}\b'),
    // Short format: 01/15/24
    RegExp(r'\b\d{1,2}[-/]\d{1,2}[-/]\d{2}\b'),
    // Chinese short: 1月15日
    RegExp(r'\b\d{1,2}月\d{1,2}日\b'),
  ];

  // ============================================
  // Time patterns
  // ============================================
  static final _timePatterns = [
    // 24-hour format: 14:30, 14:30:45
    RegExp(r'\b([01]?\d|2[0-3]):[0-5]\d(:[0-5]\d)?\b'),
    // 12-hour format: 2:30 PM, 2:30PM
    RegExp(r'\b(1[0-2]|0?[1-9]):[0-5]\d\s*[APap][Mm]\b'),
    // Chinese format: 下午2點30分
    RegExp(r'[上下]午\d{1,2}[點时]\d{0,2}分?'),
  ];

  // ============================================
  // Taiwan Mobile Phone: 09xx-xxx-xxx
  // ============================================
  static final _phoneMobileTwPatterns = [
    // With separators: 0912-345-678, 0912 345 678
    RegExp(r'\b09\d{2}[-\s]?\d{3}[-\s]?\d{3}\b'),
    // International: +886 912 345 678
    RegExp(r'\+886[-\s]?9\d{2}[-\s]?\d{3}[-\s]?\d{3}\b'),
  ];

  // ============================================
  // Taiwan Landline: (0x) xxxx-xxxx
  // ============================================
  static final _phoneLandlineTwPatterns = [
    // Taipei: (02) 2345-6789, 02-2345-6789
    RegExp(r'\(0[2-8]\)[-\s]?\d{4}[-\s]?\d{4}\b'),
    RegExp(r'\b0[2-8][-\s]?\d{4}[-\s]?\d{4}\b'),
    // With area code: 04-2345-6789
    RegExp(r'\b0[3-8][-\s]?\d{3,4}[-\s]?\d{4}\b'),
  ];

  // ============================================
  // Email
  // ============================================
  static final _emailPatterns = [
    RegExp(r'\b[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}\b'),
  ];

  // ============================================
  // Currency Amount
  // ============================================
  static final _currencyAmountPatterns = [
    // NT$ or NTD format: NT$1,234.56, NTD 1,234
    RegExp(r'NT\$?\s?[\d,]+\.?\d*'),
    RegExp(r'NTD\s?[\d,]+\.?\d*'),
    // Dollar sign: $1,234.56
    RegExp(r'\$[\d,]+\.?\d*'),
    // Chinese Yuan: ¥1,234
    RegExp(r'¥[\d,]+\.?\d*'),
    // With 元: 1,234元, 1234 元
    RegExp(r'[\d,]+\.?\d*\s?元'),
    // USD, EUR, etc.
    RegExp(r'(USD|EUR|JPY|GBP|CNY)\s?[\d,]+\.?\d*'),
  ];

  // ============================================
  // Percentage
  // ============================================
  static final _percentagePatterns = [
    // 12.5%, 100%
    RegExp(r'\b\d+\.?\d*\s?%'),
    // Chinese: 百分之十二
    RegExp(r'百分之[零一二三四五六七八九十百]+'),
  ];

  // ============================================
  // URL
  // ============================================
  static final _urlPatterns = [
    // http/https URLs
    RegExp(r'https?://[^\s<>"{}|\\^`\[\]]+'),
    // www URLs
    RegExp(r'\bwww\.[^\s<>"{}|\\^`\[\]]+'),
  ];

  // ============================================
  // IP Address
  // ============================================
  static final _ipAddressPatterns = [
    // IPv4: 192.168.1.1
    RegExp(r'\b(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\b'),
    // IPv4 with port: 192.168.1.1:8080
    RegExp(r'\b(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?):\d{1,5}\b'),
  ];

  /// Extract entities from OCR result
  ///
  /// [enabledTypes] - If provided, only extract these entity types.
  ///                  If null or empty, extract all types.
  KieResult extract(OcrResult ocr, {List<EntityType>? enabledTypes}) {
    final entities = <ExtractedEntity>[];
    final typesToExtract = (enabledTypes == null || enabledTypes.isEmpty)
        ? EntityType.values
        : enabledTypes;

    // Process each text line
    for (final line in ocr.results) {
      if (typesToExtract.contains(EntityType.date)) {
        entities.addAll(_extractFromLine(line, EntityType.date, _datePatterns));
      }
      if (typesToExtract.contains(EntityType.time)) {
        entities.addAll(_extractFromLine(line, EntityType.time, _timePatterns));
      }
      if (typesToExtract.contains(EntityType.phoneMobileTw)) {
        entities.addAll(_extractFromLine(line, EntityType.phoneMobileTw, _phoneMobileTwPatterns));
      }
      if (typesToExtract.contains(EntityType.phoneLandlineTw)) {
        entities.addAll(_extractFromLine(line, EntityType.phoneLandlineTw, _phoneLandlineTwPatterns));
      }
      if (typesToExtract.contains(EntityType.email)) {
        entities.addAll(_extractFromLine(line, EntityType.email, _emailPatterns));
      }
      if (typesToExtract.contains(EntityType.currencyAmount)) {
        entities.addAll(_extractFromLine(line, EntityType.currencyAmount, _currencyAmountPatterns));
      }
      if (typesToExtract.contains(EntityType.percentage)) {
        entities.addAll(_extractFromLine(line, EntityType.percentage, _percentagePatterns));
      }
      if (typesToExtract.contains(EntityType.url)) {
        entities.addAll(_extractFromLine(line, EntityType.url, _urlPatterns));
      }
      if (typesToExtract.contains(EntityType.ipAddress)) {
        entities.addAll(_extractFromLine(line, EntityType.ipAddress, _ipAddressPatterns));
      }
    }

    // Remove duplicates (same value at same position)
    final uniqueEntities = _removeDuplicates(entities);

    return KieResult(entities: uniqueEntities);
  }

  /// Extract entities of a specific type from a text line
  List<ExtractedEntity> _extractFromLine(
    TextLine line,
    EntityType type,
    List<RegExp> patterns,
  ) {
    final entities = <ExtractedEntity>[];
    final text = line.text;

    for (final pattern in patterns) {
      for (final match in pattern.allMatches(text)) {
        final value = match.group(0)!;

        // Calculate bounding box based on character position
        final lineWidth = line.x2 - line.x1;
        final charWidth = lineWidth / text.length;

        final x1 = line.x1 + (match.start * charWidth);
        final x2 = line.x1 + (match.end * charWidth);

        entities.add(ExtractedEntity(
          type: type,
          value: value,
          sourceLine: line,
          x1: x1,
          y1: line.y1,
          x2: x2,
          y2: line.y2,
        ));
      }
    }

    return entities;
  }

  /// Remove duplicate entities (same type and overlapping positions)
  List<ExtractedEntity> _removeDuplicates(List<ExtractedEntity> entities) {
    final unique = <ExtractedEntity>[];

    for (final entity in entities) {
      final isDuplicate = unique.any((e) =>
          e.type == entity.type &&
          e.value == entity.value &&
          _rectsOverlap(e.rect, entity.rect));

      if (!isDuplicate) {
        unique.add(entity);
      }
    }

    return unique;
  }

  bool _rectsOverlap(Rect a, Rect b) {
    return a.left < b.right &&
        a.right > b.left &&
        a.top < b.bottom &&
        a.bottom > b.top;
  }
}

// ============================================
// Spatial KIE - Label + Position based
// ============================================

/// Direction to search for value relative to label
enum SpatialDirection {
  right,   // Value is to the right of label
  below,   // Value is below the label
  rightOrBelow,  // Try right first, then below
}

/// Label pattern configuration
class LabelPattern {
  final String name;
  final List<String> patterns;
  final SpatialDirection direction;
  final Color color;

  const LabelPattern({
    required this.name,
    required this.patterns,
    this.direction = SpatialDirection.right,
    this.color = Colors.blue,
  });

  /// Check if text matches any pattern
  bool matches(String text) {
    final lowerText = text.toLowerCase().trim();
    for (final pattern in patterns) {
      if (lowerText.contains(pattern.toLowerCase())) {
        return true;
      }
    }
    return false;
  }
}

/// Extracted spatial entity (label + value pair)
class SpatialEntity {
  final String labelName;
  final String labelText;
  final String value;
  final TextLine labelLine;
  final TextLine valueLine;
  final Color color;

  SpatialEntity({
    required this.labelName,
    required this.labelText,
    required this.value,
    required this.labelLine,
    required this.valueLine,
    required this.color,
  });

  Rect get labelRect => labelLine.rect;
  Rect get valueRect => valueLine.rect;

  @override
  String toString() => '$labelName: $value';
}

/// Spatial KIE extraction result
class SpatialKieResult {
  final List<SpatialEntity> entities;
  final Map<String, List<SpatialEntity>> byLabel;

  SpatialKieResult({required this.entities})
      : byLabel = _groupByLabel(entities);

  static Map<String, List<SpatialEntity>> _groupByLabel(
      List<SpatialEntity> entities) {
    final map = <String, List<SpatialEntity>>{};
    for (final entity in entities) {
      map.putIfAbsent(entity.labelName, () => []).add(entity);
    }
    return map;
  }

  List<SpatialEntity> ofLabel(String name) => byLabel[name] ?? [];

  int get count => entities.length;

  bool get isEmpty => entities.isEmpty;
  bool get isNotEmpty => entities.isNotEmpty;
}

/// Default label patterns for common fields
class DefaultLabelPatterns {
  static const name = LabelPattern(
    name: 'NAME',
    patterns: ['姓名', '收件人', '客戶', '名稱', '聯絡人', 'name', 'recipient'],
    direction: SpatialDirection.rightOrBelow,
    color: Colors.blue,
  );

  static const phone = LabelPattern(
    name: 'PHONE',
    patterns: ['電話', '手機', '聯絡電話', 'tel', 'phone', 'mobile'],
    direction: SpatialDirection.right,
    color: Colors.green,
  );

  static const email = LabelPattern(
    name: 'EMAIL',
    patterns: ['信箱', '郵件', 'email', 'e-mail', 'mail'],
    direction: SpatialDirection.right,
    color: Colors.orange,
  );

  static const address = LabelPattern(
    name: 'ADDRESS',
    patterns: ['地址', '住址', '送貨地址', 'address'],
    direction: SpatialDirection.rightOrBelow,
    color: Colors.purple,
  );

  static const date = LabelPattern(
    name: 'DATE',
    patterns: ['日期', '發票日期', '交易日期', 'date'],
    direction: SpatialDirection.right,
    color: Colors.indigo,
  );

  static const amount = LabelPattern(
    name: 'AMOUNT',
    patterns: ['金額', '總計', '合計', '應付', '小計', 'total', 'amount', 'subtotal'],
    direction: SpatialDirection.right,
    color: Colors.red,
  );

  static const invoiceNo = LabelPattern(
    name: 'INVOICE_NO',
    patterns: ['發票號碼', '統一編號', '編號', 'invoice', 'no.', 'number'],
    direction: SpatialDirection.right,
    color: Colors.teal,
  );

  static const company = LabelPattern(
    name: 'COMPANY',
    patterns: ['公司', '商店', '店名', 'company', 'store'],
    direction: SpatialDirection.rightOrBelow,
    color: Colors.brown,
  );

  static List<LabelPattern> get all => [
    name,
    phone,
    email,
    address,
    date,
    amount,
    invoiceNo,
    company,
  ];
}

/// Spatial KIE Extractor - finds values based on label positions
class SpatialKieExtractor {
  final List<LabelPattern> patterns;

  /// Tolerance for "same line" detection (vertical overlap)
  final double verticalTolerance;

  /// Maximum horizontal distance to consider as "right of"
  final double maxHorizontalDistance;

  /// Maximum vertical distance to consider as "below"
  final double maxVerticalDistance;

  SpatialKieExtractor({
    List<LabelPattern>? patterns,
    this.verticalTolerance = 0.5,  // 50% overlap
    this.maxHorizontalDistance = 500,
    this.maxVerticalDistance = 100,
  }) : patterns = patterns ?? DefaultLabelPatterns.all;

  /// Extract entities from OCR result
  SpatialKieResult extract(OcrResult ocr, {List<LabelPattern>? enabledPatterns}) {
    final entities = <SpatialEntity>[];
    final patternsToUse = enabledPatterns ?? patterns;

    final lines = ocr.results;
    if (lines.isEmpty) return SpatialKieResult(entities: []);

    // For each pattern, find matching labels and their values
    for (final pattern in patternsToUse) {
      for (int i = 0; i < lines.length; i++) {
        final line = lines[i];

        if (pattern.matches(line.text)) {
          // Found a label, now find the value
          final value = _findValue(line, lines, pattern.direction);

          if (value != null && value.text.trim().isNotEmpty) {
            // Make sure value is different from label
            if (!pattern.matches(value.text)) {
              entities.add(SpatialEntity(
                labelName: pattern.name,
                labelText: line.text,
                value: value.text.trim(),
                labelLine: line,
                valueLine: value,
                color: pattern.color,
              ));
            }
          }
        }
      }
    }

    return SpatialKieResult(entities: entities);
  }

  /// Find value based on direction
  TextLine? _findValue(TextLine label, List<TextLine> allLines, SpatialDirection direction) {
    switch (direction) {
      case SpatialDirection.right:
        return _findRightOf(label, allLines);
      case SpatialDirection.below:
        return _findBelow(label, allLines);
      case SpatialDirection.rightOrBelow:
        return _findRightOf(label, allLines) ?? _findBelow(label, allLines);
    }
  }

  /// Find text to the right of label (same line)
  TextLine? _findRightOf(TextLine label, List<TextLine> allLines) {
    TextLine? best;
    double bestDistance = double.infinity;

    for (final line in allLines) {
      // Skip if same line
      if (line == label) continue;

      // Must be to the right
      if (line.x1 <= label.x2) continue;

      // Check vertical overlap (same line)
      if (!_isSameLine(label, line)) continue;

      // Check horizontal distance
      final distance = line.x1 - label.x2;
      if (distance > maxHorizontalDistance) continue;

      if (distance < bestDistance) {
        bestDistance = distance;
        best = line;
      }
    }

    return best;
  }

  /// Find text below the label
  TextLine? _findBelow(TextLine label, List<TextLine> allLines) {
    TextLine? best;
    double bestDistance = double.infinity;

    for (final line in allLines) {
      // Skip if same line
      if (line == label) continue;

      // Must be below
      if (line.y1 <= label.y2) continue;

      // Check horizontal overlap (roughly aligned)
      if (!_hasHorizontalOverlap(label, line)) continue;

      // Check vertical distance
      final distance = line.y1 - label.y2;
      if (distance > maxVerticalDistance) continue;

      if (distance < bestDistance) {
        bestDistance = distance;
        best = line;
      }
    }

    return best;
  }

  /// Check if two lines are on the same line (vertical overlap)
  bool _isSameLine(TextLine a, TextLine b) {
    final aHeight = a.y2 - a.y1;
    final bHeight = b.y2 - b.y1;
    final minHeight = aHeight < bHeight ? aHeight : bHeight;

    final overlapTop = a.y1 > b.y1 ? a.y1 : b.y1;
    final overlapBottom = a.y2 < b.y2 ? a.y2 : b.y2;
    final overlap = overlapBottom - overlapTop;

    return overlap > (minHeight * verticalTolerance);
  }

  /// Check if two lines have horizontal overlap
  bool _hasHorizontalOverlap(TextLine a, TextLine b) {
    // Check if b starts within label bounds (with some tolerance)
    final labelCenter = (a.x1 + a.x2) / 2;
    final labelWidth = a.x2 - a.x1;

    // Value should start near the label's horizontal area
    return b.x1 < (labelCenter + labelWidth) && b.x2 > (a.x1 - labelWidth * 0.5);
  }
}

// ===========================================
// Layout KIE - Region-based extraction
// ===========================================

/// Target region types for KIE extraction
class TargetRegions {
  static const table = 'Table';
  static const text = 'Text';
  static const title = 'Title';
  static const figure = 'Figure';
  static const figureCaption = 'Figure caption';
  static const tableCaption = 'Table caption';
  static const header = 'Header';
  static const footer = 'Footer';
  static const reference = 'Reference';
  static const equation = 'Equation';

  /// Regions to extract key-value pairs from
  static const List<String> extractionTargets = [table, text];

  /// All region types
  static const List<String> all = [
    table,
    text,
    title,
    figure,
    figureCaption,
    tableCaption,
    header,
    footer,
    reference,
    equation,
  ];
}

/// A region from Layout Detection with its OCR texts
class LayoutRegion {
  final String className;
  final Rect rect;
  final double score;
  final List<TextLine> texts;

  LayoutRegion({
    required this.className,
    required this.rect,
    required this.score,
    required this.texts,
  });

  bool get isExtractionTarget =>
      TargetRegions.extractionTargets.contains(className);

  /// Get color for this region type
  Color get color {
    switch (className) {
      case TargetRegions.table:
        return const Color(0xFF4CAF50); // Green
      case TargetRegions.text:
        return const Color(0xFF2196F3); // Blue
      case TargetRegions.title:
        return const Color(0xFFFF9800); // Orange
      case TargetRegions.figure:
        return const Color(0xFF9C27B0); // Purple
      case TargetRegions.figureCaption:
      case TargetRegions.tableCaption:
        return const Color(0xFF795548); // Brown
      case TargetRegions.header:
      case TargetRegions.footer:
        return const Color(0xFF607D8B); // Blue Grey
      case TargetRegions.reference:
        return const Color(0xFF00BCD4); // Cyan
      case TargetRegions.equation:
        return const Color(0xFFE91E63); // Pink
      default:
        return const Color(0xFF9E9E9E); // Grey
    }
  }
}

/// Result from Layout KIE extraction
class LayoutKieResult {
  final List<LayoutRegion> regions;
  final List<SpatialEntity> entities;
  final int layoutTimeMs;
  final int ocrTimeMs;

  LayoutKieResult({
    required this.regions,
    required this.entities,
    required this.layoutTimeMs,
    required this.ocrTimeMs,
  });

  int get totalTimeMs => layoutTimeMs + ocrTimeMs;
  int get regionCount => regions.length;
  int get entityCount => entities.length;
  bool get isEmpty => entities.isEmpty;
  bool get isNotEmpty => entities.isNotEmpty;

  /// Group entities by label name
  Map<String, List<SpatialEntity>> get byLabel {
    final map = <String, List<SpatialEntity>>{};
    for (final e in entities) {
      map.putIfAbsent(e.labelName, () => []).add(e);
    }
    return map;
  }

  /// Get regions by type
  List<LayoutRegion> getRegionsByType(String type) =>
      regions.where((r) => r.className == type).toList();
}

/// Layout KIE Extractor - uses Layout Detection + OCR + SpatialKIE
class LayoutKieExtractor {
  final SpatialKieExtractor spatialExtractor;
  final List<String> targetRegions;
  final double iouThreshold;

  LayoutKieExtractor({
    SpatialKieExtractor? spatialExtractor,
    List<String>? targetRegions,
    this.iouThreshold = 0.3,
  })  : spatialExtractor = spatialExtractor ?? SpatialKieExtractor(),
        targetRegions = targetRegions ?? TargetRegions.extractionTargets;

  /// Extract key-value pairs from layout regions
  ///
  /// [layout] - Layout Detection result
  /// [ocr] - OCR result
  /// [enabledPatterns] - Label patterns to use (optional, uses all if null)
  LayoutKieResult extract({
    required LayoutResult layout,
    required OcrResult ocr,
    List<LabelPattern>? enabledPatterns,
  }) {
    // 1. Assign OCR texts to layout regions
    final regions = _assignTextsToRegions(layout, ocr);

    // 2. Extract entities from target regions
    final allEntities = <SpatialEntity>[];

    for (final region in regions) {
      if (!targetRegions.contains(region.className)) continue;
      if (region.texts.isEmpty) continue;

      // Create a synthetic OcrResult for this region
      final regionOcr = OcrResult(
        results: region.texts,
        words: ocr.words
            .where((w) => _isInRect(w, region.rect))
            .toList(),
        count: region.texts.length,
        inferenceTimeMs: 0,
        imageWidth: ocr.imageWidth,
        imageHeight: ocr.imageHeight,
      );

      // Run SpatialKIE on this region
      final result = spatialExtractor.extract(
        regionOcr,
        enabledPatterns: enabledPatterns,
      );

      allEntities.addAll(result.entities);
    }

    return LayoutKieResult(
      regions: regions,
      entities: allEntities,
      layoutTimeMs: layout.inferenceTimeMs,
      ocrTimeMs: ocr.inferenceTimeMs,
    );
  }

  /// Assign OCR text lines to layout regions
  List<LayoutRegion> _assignTextsToRegions(LayoutResult layout, OcrResult ocr) {
    final regions = <LayoutRegion>[];

    for (final det in layout.detections) {
      final regionRect = Rect.fromLTRB(det.x1, det.y1, det.x2, det.y2);

      // Find texts that belong to this region
      final textsInRegion = ocr.results.where((text) {
        return _isInRect(text, regionRect);
      }).toList();

      regions.add(LayoutRegion(
        className: det.className,
        rect: regionRect,
        score: det.score,
        texts: textsInRegion,
      ));
    }

    return regions;
  }

  /// Check if a text line is inside a region (by IoU or containment)
  bool _isInRect(TextLine text, Rect region) {
    final textRect = Rect.fromLTRB(text.x1, text.y1, text.x2, text.y2);

    // Calculate intersection
    final intersection = textRect.intersect(region);
    if (intersection.isEmpty) return false;

    // Check if most of the text is inside the region
    final textArea = textRect.width * textRect.height;
    if (textArea <= 0) return false;

    final intersectionArea = intersection.width * intersection.height;
    final containment = intersectionArea / textArea;

    return containment >= iouThreshold;
  }
}

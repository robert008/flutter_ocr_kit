import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'models.dart';

/// Taiwan Invoice information
class InvoiceInfo {
  final String? invoiceNumber;    // XX-XXXXXXXX
  final String? period;           // 114年09-10月
  final String? storeName;        // 店家名稱
  final int? amount;              // 總金額 (數字)
  final String? date;             // 交易日期
  final String? time;             // 交易時間
  final String? randomCode;       // 隨機碼

  final Rect? invoiceNumberRect;  // 發票號碼位置 (用於 UI 高亮)
  final Rect? amountRect;         // 金額位置
  final double? invoiceNumberScore; // 發票號碼 OCR 信心值
  final double? periodScore;      // 期別 OCR 信心值
  final double? dateScore;        // 日期 OCR 信心值
  final double? amountScore;      // 金額 OCR 信心值
  final double? storeNameScore;   // 店家名稱 OCR 信心值

  InvoiceInfo({
    this.invoiceNumber,
    this.period,
    this.storeName,
    this.amount,
    this.date,
    this.time,
    this.randomCode,
    this.invoiceNumberRect,
    this.amountRect,
    this.invoiceNumberScore,
    this.periodScore,
    this.dateScore,
    this.amountScore,
    this.storeNameScore,
  });

  /// Minimum confidence threshold (Android is 10% lower)
  static final double minConfidenceThreshold = Platform.isAndroid ? 0.8 : 0.9;
  static final double amountConfidenceThreshold = Platform.isAndroid ? 0.6 : 0.7;

  bool get isValid => invoiceNumber != null && hasHighConfidence;
  bool get hasHighConfidence => invoiceNumberScore == null || invoiceNumberScore! >= minConfidenceThreshold;
  bool get hasAmount => amount != null;

  String get displayAmount => amount != null ? '\$$amount' : '';

  @override
  String toString() {
    final parts = <String>[];
    if (invoiceNumber != null) parts.add(invoiceNumber!);
    if (period != null) parts.add(period!);
    if (amount != null) parts.add('\$$amount');
    if (storeName != null) parts.add(storeName!);
    return parts.join(' | ');
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is InvoiceInfo && other.invoiceNumber == invoiceNumber;
  }

  @override
  int get hashCode => invoiceNumber.hashCode;
}

/// Taiwan Invoice Extractor
///
/// Extracts key information from Taiwan electronic invoices using OCR results.
///
/// Taiwan e-invoice format:
/// ```
/// ┌─────────────────────┐
/// │     店家名稱         │
/// ├─────────────────────┤
/// │   電子發票證明聯      │  <- Anchor
/// │   1XX年MM-MM月       │  <- Period
/// │   XX-XXXXXXXX       │  <- Invoice Number
/// ├─────────────────────┤
/// │   日期時間           │
/// │   隨機碼             │
/// │   ...商品明細...     │
/// │   總計 $XXX          │  <- Amount
/// └─────────────────────┘
/// ```
class InvoiceExtractor {
  // Invoice number: XX-XXXXXXXX (2 letters + 8 digits)
  static final _invoiceNumberPattern = RegExp(
    r'\b([A-Z]{2})-?(\d{8})\b',
    caseSensitive: false,
  );

  // Period: 1XX年MM-MM月 or 1XX年MM月 (allow spaces)
  static final _periodPatterns = [
    RegExp(r'1\d{2}\s*年\s*\d{1,2}\s*-\s*\d{1,2}\s*月'),  // 114年09-10月, 114 年09-10月
    RegExp(r'1\d{2}\s*年\s*\d{1,2}\s*月'),                 // 114年09月
  ];

  // Date pattern for inferring period
  static final _fullDatePattern = RegExp(r'(\d{4})[-/](\d{1,2})[-/]\d{1,2}');

  // Total amount patterns (priority order)
  static final _amountPatterns = [
    RegExp(r'總\s*[計计]\s*[:：]?\s*\$?\s*([\d,]+)'),
    RegExp(r'合\s*[計计]\s*[:：]?\s*\$?\s*([\d,]+)'),
    RegExp(r'應付\s*[:：]?\s*\$?\s*([\d,]+)'),
    RegExp(r'金額\s*[:：]?\s*\$?\s*([\d,]+)'),
    RegExp(r'NT\$\s*([\d,]+)'),
  ];

  // Date: 2025-07-26 or 2025/07/26
  static final _datePattern = RegExp(r'(\d{4}[-/]\d{1,2}[-/]\d{1,2})');

  // Time: HH:MM:SS or HH:MM
  static final _timePattern = RegExp(r'(\d{1,2}:\d{2}(:\d{2})?)');

  // Random code: 4 digits
  static final _randomCodePattern = RegExp(r'隨機碼\s*[:：]?\s*(\d{4})');

  // Anchor: 電子發票證明聯
  static final _anchorPattern = RegExp(r'電子發票證明聯');

  /// Extract invoice info from OCR result
  InvoiceInfo extract(OcrResult ocr) {
    final lines = ocr.results;
    if (lines.isEmpty) return InvoiceInfo();

    // Find anchor line index
    int anchorIndex = -1;
    for (int i = 0; i < lines.length; i++) {
      if (_anchorPattern.hasMatch(lines[i].text)) {
        anchorIndex = i;
        break;
      }
    }

    // Extract fields
    final invoiceResult = _extractInvoiceNumber(lines, anchorIndex);
    final periodResult = _extractPeriod(lines, anchorIndex);
    final storeNameResult = _extractStoreName(lines, anchorIndex);
    final amountResult = _extractAmount(lines);
    final dateResult = _extractDate(lines);
    final time = _extractTime(lines);
    final randomCode = _extractRandomCode(lines);

    // Apply confidence threshold for optional fields
    final threshold = InvoiceInfo.minConfidenceThreshold;
    final amountThreshold = InvoiceInfo.amountConfidenceThreshold;
    final hasValidPeriod = periodResult != null && periodResult.$2 >= threshold;
    final hasValidAmount = amountResult != null && amountResult.$3 >= amountThreshold;
    final hasValidDate = dateResult != null && dateResult.$2 >= threshold;
    final hasValidStoreName = storeNameResult != null && storeNameResult.$2 >= threshold;

    // Debug log
    if (invoiceResult != null) {
      debugPrint('=== Invoice Extraction ===');
      debugPrint('Invoice: ${invoiceResult.$1} (${(invoiceResult.$3 * 100).toStringAsFixed(0)}%)');
      debugPrint('Period: ${periodResult?.$1 ?? "N/A"} (${periodResult != null ? (periodResult.$2 * 100).toStringAsFixed(0) : "N/A"}%) -> ${hasValidPeriod ? "OK" : "SKIP"}');
      debugPrint('Amount: ${amountResult?.$1 ?? "N/A"} (${amountResult != null ? (amountResult.$3 * 100).toStringAsFixed(0) : "N/A"}%) -> ${hasValidAmount ? "OK" : "SKIP"}');
      debugPrint('Store: ${storeNameResult?.$1 ?? "N/A"} (${storeNameResult != null ? (storeNameResult.$2 * 100).toStringAsFixed(0) : "N/A"}%) -> ${hasValidStoreName ? "OK" : "SKIP"}');
      debugPrint('Date: ${dateResult?.$1 ?? "N/A"} (${dateResult != null ? (dateResult.$2 * 100).toStringAsFixed(0) : "N/A"}%) -> ${hasValidDate ? "OK" : "SKIP"}');
      debugPrint('==========================');
    }

    return InvoiceInfo(
      invoiceNumber: invoiceResult?.$1,
      invoiceNumberRect: invoiceResult?.$2,
      invoiceNumberScore: invoiceResult?.$3,
      period: hasValidPeriod ? periodResult.$1 : null,
      periodScore: periodResult?.$2,
      storeName: hasValidStoreName ? storeNameResult.$1 : null,
      storeNameScore: storeNameResult?.$2,
      amount: hasValidAmount ? amountResult.$1 : null,
      amountRect: hasValidAmount ? amountResult.$2 : null,
      amountScore: amountResult?.$3,
      date: hasValidDate ? dateResult.$1 : null,
      dateScore: dateResult?.$2,
      time: time,
      randomCode: randomCode,
    );
  }

  /// Extract multiple invoices from OCR result (for multi-invoice photos)
  List<InvoiceInfo> extractMultiple(OcrResult ocr) {
    final lines = ocr.results;
    if (lines.isEmpty) return [];

    // Find all anchor positions
    final anchorIndices = <int>[];
    for (int i = 0; i < lines.length; i++) {
      if (_anchorPattern.hasMatch(lines[i].text)) {
        anchorIndices.add(i);
      }
    }

    if (anchorIndices.isEmpty) {
      // No anchor found, try to extract single invoice
      final single = extract(ocr);
      return single.isValid ? [single] : [];
    }

    // Extract invoice for each anchor
    final invoices = <InvoiceInfo>[];
    for (int i = 0; i < anchorIndices.length; i++) {
      final startIdx = anchorIndices[i];
      final endIdx = (i + 1 < anchorIndices.length)
          ? anchorIndices[i + 1]
          : lines.length;

      final regionLines = lines.sublist(
        (startIdx - 2).clamp(0, lines.length),
        endIdx,
      );

      // Create temporary OcrResult for this region
      final regionOcr = OcrResult(
        results: regionLines,
        count: regionLines.length,
        imageWidth: ocr.imageWidth,
        imageHeight: ocr.imageHeight,
        inferenceTimeMs: 0,
      );

      final invoice = extract(regionOcr);
      if (invoice.isValid) {
        invoices.add(invoice);
      }
    }

    return invoices;
  }

  /// Returns (invoiceNumber, rect, score)
  (String, Rect, double)? _extractInvoiceNumber(List<TextLine> lines, int anchorIndex) {
    // Search near anchor first (within 3 lines after)
    if (anchorIndex >= 0) {
      final searchEnd = (anchorIndex + 4).clamp(0, lines.length);
      for (int i = anchorIndex; i < searchEnd; i++) {
        final match = _invoiceNumberPattern.firstMatch(lines[i].text);
        if (match != null) {
          final number = '${match.group(1)!.toUpperCase()}-${match.group(2)}';
          return (number, lines[i].rect, lines[i].score);
        }
      }
    }

    // Fallback: search all lines
    for (final line in lines) {
      final match = _invoiceNumberPattern.firstMatch(line.text);
      if (match != null) {
        final number = '${match.group(1)!.toUpperCase()}-${match.group(2)}';
        return (number, line.rect, line.score);
      }
    }

    return null;
  }

  /// Returns (period, score)
  (String, double)? _extractPeriod(List<TextLine> lines, int anchorIndex) {
    // Strategy 1: Search for explicit period format (1XX年MM-MM月)
    final searchLines = anchorIndex >= 0
        ? lines.sublist(anchorIndex, (anchorIndex + 3).clamp(0, lines.length))
        : lines;

    for (final line in searchLines) {
      for (final pattern in _periodPatterns) {
        final match = pattern.firstMatch(line.text);
        if (match != null) return (match.group(0)!, line.score);
      }
    }

    // Fallback: search all lines for explicit period
    if (anchorIndex >= 0) {
      for (final line in lines) {
        for (final pattern in _periodPatterns) {
          final match = pattern.firstMatch(line.text);
          if (match != null) return (match.group(0)!, line.score);
        }
      }
    }

    // Strategy 2: Infer from date (2025-07-26 -> 114年07-08月)
    for (final line in lines) {
      final match = _fullDatePattern.firstMatch(line.text);
      if (match != null) {
        final year = int.tryParse(match.group(1)!);
        final month = int.tryParse(match.group(2)!);
        if (year != null && month != null) {
          final inferred = _inferPeriodFromDate(year, month);
          if (inferred != null) return (inferred, line.score);
        }
      }
    }

    return null;
  }

  /// Infer invoice period from date
  /// e.g., 2025-07-26 -> 114年07-08月
  String? _inferPeriodFromDate(int year, int month) {
    // Taiwan year = AD year - 1911
    final twYear = year - 1911;
    if (twYear < 100 || twYear > 200) return null;

    // Invoice periods are bi-monthly: 01-02, 03-04, 05-06, 07-08, 09-10, 11-12
    final periodStart = ((month - 1) ~/ 2) * 2 + 1;
    final periodEnd = periodStart + 1;

    return '$twYear年${periodStart.toString().padLeft(2, '0')}-${periodEnd.toString().padLeft(2, '0')}月';
  }

  /// Returns (storeName, score)
  (String, double)? _extractStoreName(List<TextLine> lines, int anchorIndex) {
    if (lines.isEmpty) return null;

    // Store name is usually above anchor or at the top
    if (anchorIndex > 0) {
      for (int i = 0; i < anchorIndex; i++) {
        final text = lines[i].text.trim();
        if (_isValidStoreName(text)) {
          return (text, lines[i].score);
        }
      }
    }

    // Fallback: first meaningful line
    for (final line in lines.take(3)) {
      final text = line.text.trim();
      if (_isValidStoreName(text)) {
        return (text, line.score);
      }
    }

    return null;
  }

  bool _isValidStoreName(String text) {
    if (text.length < 2) return false;
    if (RegExp(r'^\d+$').hasMatch(text)) return false;
    if (text.contains('統一編號')) return false;
    if (text.contains('營業人')) return false;
    if (text.contains('電子發票')) return false;
    if (text.contains('證明聯')) return false;
    return true;
  }

  /// Returns (amount, rect, score)
  (int, Rect, double)? _extractAmount(List<TextLine> lines) {
    for (final pattern in _amountPatterns) {
      for (final line in lines) {
        final match = pattern.firstMatch(line.text);
        if (match != null && match.groupCount >= 1) {
          final amountStr = match.group(1)!.replaceAll(',', '');
          final amount = int.tryParse(amountStr);
          if (amount != null && amount >= 1 && amount <= 10000000) {
            return (amount, line.rect, line.score);
          }
        }
      }
    }
    return null;
  }

  /// Returns (date, score)
  (String, double)? _extractDate(List<TextLine> lines) {
    for (final line in lines) {
      final match = _datePattern.firstMatch(line.text);
      if (match != null) return (match.group(1)!, line.score);
    }
    return null;
  }

  String? _extractTime(List<TextLine> lines) {
    for (final line in lines) {
      final match = _timePattern.firstMatch(line.text);
      if (match != null) return match.group(1);
    }
    return null;
  }

  String? _extractRandomCode(List<TextLine> lines) {
    for (final line in lines) {
      final match = _randomCodePattern.firstMatch(line.text);
      if (match != null) return match.group(1);
    }
    return null;
  }
}

/// Scanned invoice record (for storage)
class ScannedInvoice {
  final String invoiceNumber;
  String? period;
  int? amount;
  String? storeName;
  final DateTime scannedAt;

  ScannedInvoice({
    required this.invoiceNumber,
    this.period,
    this.amount,
    this.storeName,
    required this.scannedAt,
  });

  /// Create from InvoiceInfo
  factory ScannedInvoice.fromInfo(InvoiceInfo info) {
    return ScannedInvoice(
      invoiceNumber: info.invoiceNumber!,
      period: info.period,
      amount: info.amount,
      storeName: info.storeName,
      scannedAt: DateTime.now(),
    );
  }

  /// Update fields from InvoiceInfo (only if new value exists and old is null)
  void updateFrom(InvoiceInfo info) {
    if (period == null && info.period != null) {
      period = info.period;
    }
    if (amount == null && info.amount != null) {
      amount = info.amount;
    }
    if (storeName == null && info.storeName != null) {
      storeName = info.storeName;
    }
  }

  String get displayAmount => amount != null ? '\$$amount' : '-';

  /// Get period for grouping (e.g., "114年09-10月")
  String get groupKey => period ?? 'Unknown';

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ScannedInvoice && other.invoiceNumber == invoiceNumber;
  }

  @override
  int get hashCode => invoiceNumber.hashCode;
}

import 'dart:ui';

import 'package:flutter/foundation.dart';

import 'models.dart';

/// Quotation item from table
class QuotationItem {
  final int index;
  final String name;
  final String spec;
  final int quantity;
  final String unit;
  final int unitPrice;
  final int amount;
  final Rect? rect;

  QuotationItem({
    required this.index,
    required this.name,
    required this.spec,
    required this.quantity,
    required this.unit,
    required this.unitPrice,
    required this.amount,
    this.rect,
  });

  @override
  String toString() => '$name x$quantity = \$$amount';
}

/// Extracted quotation info
class QuotationInfo {
  final String? quotationNumber;
  final String? quotationDate;
  final String? customerName;
  final String? orderNumber;
  final List<QuotationItem> items;
  final int? subtotal;
  final int? tax;
  final int? total;
  final Rect? quotationNumberRect;
  final Rect? tableRect;
  final double confidence; // Average OCR confidence score

  QuotationInfo({
    this.quotationNumber,
    this.quotationDate,
    this.customerName,
    this.orderNumber,
    this.items = const [],
    this.subtotal,
    this.tax,
    this.total,
    this.quotationNumberRect,
    this.tableRect,
    this.confidence = 0.0,
  });

  bool get isValid => quotationNumber != null && quotationNumber!.isNotEmpty;

  String get displayTotal => total != null ? '\$$total' : 'N/A';

  int get itemCount => items.length;
}

/// Scanned quotation with metadata
class ScannedQuotation {
  String quotationNumber;
  String? quotationDate;
  String? customerName;
  String? orderNumber;
  List<QuotationItem> items;
  int? subtotal;
  int? tax;
  int? total;
  double confidence;
  final DateTime scannedAt;

  ScannedQuotation({
    required this.quotationNumber,
    this.quotationDate,
    this.customerName,
    this.orderNumber,
    this.items = const [],
    this.subtotal,
    this.tax,
    this.total,
    this.confidence = 0.0,
    required this.scannedAt,
  });

  factory ScannedQuotation.fromInfo(QuotationInfo info) {
    return ScannedQuotation(
      quotationNumber: info.quotationNumber!,
      quotationDate: info.quotationDate,
      customerName: info.customerName,
      orderNumber: info.orderNumber,
      items: info.items,
      subtotal: info.subtotal,
      tax: info.tax,
      total: info.total,
      confidence: info.confidence,
      scannedAt: DateTime.now(),
    );
  }

  String get displayTotal => total != null ? '\$$total' : 'N/A';

  /// Confidence threshold for updating existing data
  static const double updateThreshold = 0.60;

  /// Update with higher confidence data
  /// Note: quotationNumber is never updated (it's the ID)
  void updateFrom(QuotationInfo info) {
    final meetsThreshold = info.confidence >= updateThreshold;
    final isHigherConfidence = info.confidence > confidence;

    // quotationNumber is NEVER updated - it's the unique ID

    // Only update other fields if confidence meets threshold
    if (meetsThreshold) {
      // Fill in missing data
      if (quotationDate == null && info.quotationDate != null) {
        quotationDate = info.quotationDate;
      }
      if (customerName == null && info.customerName != null) {
        customerName = info.customerName;
      }
      if (orderNumber == null && info.orderNumber != null) {
        orderNumber = info.orderNumber;
      }

      // Update items if:
      // - We have no items and new info has items, OR
      // - New info has higher confidence and more/equal items
      if (info.items.isNotEmpty &&
          (items.isEmpty || (isHigherConfidence && info.items.length >= items.length))) {
        items = info.items;
      }

      // Update total if:
      // - We have no total and new info has total, OR
      // - New info has higher confidence
      if (info.total != null && (total == null || isHigherConfidence)) {
        subtotal = info.subtotal;
        tax = info.tax;
        total = info.total;
      }

      // Update confidence if higher
      if (isHigherConfidence) {
        confidence = info.confidence;
      }
    }
  }
}

/// Quotation extractor using Layout Detection + OCR
class QuotationExtractor {
  /// Extract quotation info from OCR result
  ///
  /// [ocrResult] - Full image OCR result
  /// [layoutResult] - Layout detection result (optional, for table region)
  QuotationInfo extract(OcrResult ocrResult, {LayoutResult? layoutResult}) {
    final texts = ocrResult.results;
    if (texts.isEmpty) {
      return QuotationInfo();
    }

    // Calculate average OCR confidence
    final avgConfidence = texts.isNotEmpty
        ? texts.map((t) => t.score).reduce((a, b) => a + b) / texts.length
        : 0.0;

    // Extract quotation number using spatial positioning
    final quotationNumberResult = _extractQuotationNumber(texts);

    // Extract date
    final dateResult = _extractDate(texts);

    // Extract customer name
    final customerResult = _extractCustomerName(texts);

    // Extract order number
    final orderNumberResult = _extractOrderNumber(texts);

    // Find table region from layout result
    Rect? tableRect;
    if (layoutResult != null) {
      final tables = layoutResult.detections
          .where((d) => d.className.toLowerCase() == 'table')
          .toList();
      if (tables.isNotEmpty) {
        // Use the largest table (main items table)
        tables.sort((a, b) => (b.width * b.height).compareTo(a.width * a.height));
        final mainTable = tables.first;
        tableRect = Rect.fromLTRB(mainTable.x1, mainTable.y1, mainTable.x2, mainTable.y2);
      }
    }

    // Extract table items
    final items = _extractTableItems(texts, tableRect);

    // Extract totals
    final totals = _extractTotals(texts);

    return QuotationInfo(
      quotationNumber: quotationNumberResult?.$1,
      quotationDate: dateResult,
      customerName: customerResult,
      orderNumber: orderNumberResult,
      items: items,
      subtotal: totals['subtotal'],
      tax: totals['tax'],
      total: totals['total'],
      quotationNumberRect: quotationNumberResult?.$2,
      tableRect: tableRect,
      confidence: avgConfidence,
    );
  }

  /// Extract quotation number using spatial positioning
  /// Find text that is:
  /// - On same Y level as label
  /// - To the right of label, left of date
  (String, Rect)? _extractQuotationNumber(List<TextLine> texts) {
    // Find the label text
    TextLine? labelLine;
    for (final text in texts) {
      final t = text.text.replaceAll(' ', '');
      if (t.contains('出貨單號') || t.contains('報價單號') || t.contains('訂單號')) {
        labelLine = text;
        break;
      }
    }

    if (labelLine == null) {
      // Fallback: look for pattern directly
      final pattern = RegExp(r'[A-Z]{2}-\d{10}');
      for (final text in texts) {
        final match = pattern.firstMatch(text.text);
        if (match != null) {
          return (match.group(0)!, text.rect);
        }
      }
      return null;
    }

    // Find date label to determine right boundary
    TextLine? dateLabelLine;
    for (final text in texts) {
      final t = text.text.replaceAll(' ', '');
      if (t.contains('出貨日期') || t.contains('報價日期') || t.contains('日期')) {
        // Must be on similar Y level
        if ((text.y1 - labelLine.y1).abs() < 50) {
          dateLabelLine = text;
          break;
        }
      }
    }

    // Find text on same Y level, between label and date
    final labelY = (labelLine.y1 + labelLine.y2) / 2;
    final labelRight = labelLine.x2;
    final dateLeft = dateLabelLine?.x1 ?? double.infinity;

    for (final text in texts) {
      final textY = (text.y1 + text.y2) / 2;

      // Check Y alignment (within 30 pixels)
      if ((textY - labelY).abs() > 30) continue;

      // Check X position (right of label, left of date)
      if (text.x1 <= labelRight) continue;
      if (text.x1 >= dateLeft) continue;

      // Check if it looks like a quotation number
      final cleaned = text.text.replaceAll(' ', '');
      if (RegExp(r'[A-Z]{2}-?\d{8,12}').hasMatch(cleaned) ||
          RegExp(r'\d{8,12}').hasMatch(cleaned)) {
        return (cleaned, text.rect);
      }
    }

    return null;
  }

  /// Extract date
  String? _extractDate(List<TextLine> texts) {
    // Look for date pattern: YYYY/MM/DD or YYYY-MM-DD
    final datePattern = RegExp(r'(\d{4})[/-](\d{1,2})[/-](\d{1,2})');

    for (final text in texts) {
      final match = datePattern.firstMatch(text.text);
      if (match != null) {
        return match.group(0);
      }
    }
    return null;
  }

  /// Extract customer name
  String? _extractCustomerName(List<TextLine> texts) {
    // Find label and get value to the right
    for (int i = 0; i < texts.length; i++) {
      final t = texts[i].text.replaceAll(' ', '');
      if (t.contains('客戶名稱') || t.contains('客戶')) {
        final labelY = (texts[i].y1 + texts[i].y2) / 2;
        final labelRight = texts[i].x2;

        // Find text on same line, to the right
        for (final text in texts) {
          final textY = (text.y1 + text.y2) / 2;
          if ((textY - labelY).abs() < 30 && text.x1 > labelRight) {
            final cleaned = text.text.trim();
            if (cleaned.isNotEmpty && !cleaned.contains('客戶')) {
              return cleaned;
            }
          }
        }
      }
    }
    return null;
  }

  /// Extract order number
  String? _extractOrderNumber(List<TextLine> texts) {
    final pattern = RegExp(r'PO-\d{8}-\d{3}');
    for (final text in texts) {
      final match = pattern.firstMatch(text.text);
      if (match != null) {
        return match.group(0);
      }
    }
    return null;
  }

  /// Extract table items
  /// Returns empty list if no table rect is provided (Layout Detection must find table)
  List<QuotationItem> _extractTableItems(List<TextLine> texts, Rect? tableRect) {
    // When Layout Detection doesn't find a table, skip item extraction
    if (tableRect == null) {
      debugPrint('[QuotationExtractor] NO TABLE RECT - skipping item extraction');
      return [];
    }

    final items = <QuotationItem>[];

    // Filter texts within table region (both X and Y must be inside)
    final tableTexts = texts.where((t) {
      final centerX = (t.x1 + t.x2) / 2;
      final centerY = (t.y1 + t.y2) / 2;
      return centerX >= tableRect.left && centerX <= tableRect.right &&
             centerY >= tableRect.top && centerY <= tableRect.bottom;
    }).toList();

    // Debug: print table rect and filtering results
    debugPrint('[QuotationExtractor] Table rect: (${tableRect.left.toInt()},${tableRect.top.toInt()})-(${tableRect.right.toInt()},${tableRect.bottom.toInt()})');
    debugPrint('[QuotationExtractor] Texts: total=${texts.length}, inTable=${tableTexts.length}, filtered=${texts.length - tableTexts.length}');

    // Find product names - they usually contain Chinese + code pattern
    // Pattern: Chinese characters followed by alphanumeric product code (e.g., "電路板 PCB-2024A")
    final productTexts = <TextLine>[];

    // Header keywords to skip
    final headerKeywords = ['品名', '規格', '數量', '單位', '單價', '金額', '項次', '次', '項',
                            '小計', '總計', '稅', '合計', '營業'];

    for (final text in tableTexts) {
      final t = text.text.trim();

      // Skip if it's a header or label
      bool isHeader = false;
      for (final keyword in headerKeywords) {
        if (t == keyword || (t.length <= 4 && t.contains(keyword))) {
          isHeader = true;
          break;
        }
      }
      if (isHeader) continue;

      // Skip prices
      if (t.startsWith('\$') || t.startsWith('＄')) continue;

      // Skip pure numbers
      if (RegExp(r'^\d+$').hasMatch(t)) continue;

      // Skip single characters
      if (t.length <= 2) continue;

      // Match product name: must contain Chinese AND alphanumeric code
      // Examples: "電路板 PCB-2024A", "電容器 CAP-100uF", "LED 燈珠 LED-W5"
      final hasChineseAndCode = RegExp(r'[\u4e00-\u9fff]').hasMatch(t) &&
                                 RegExp(r'[A-Z0-9]').hasMatch(t) &&
                                 t.length > 5;

      if (hasChineseAndCode) {
        productTexts.add(text);
        debugPrint('[QuotationExtractor] Found product: "${text.text}" at y=${text.y1.toInt()}');
      }
    }

    // Sort by Y position
    productTexts.sort((a, b) => a.y1.compareTo(b.y1));
    debugPrint('[QuotationExtractor] Total products found: ${productTexts.length}');

    // For each product, find other texts on the same row
    int itemIndex = 1;
    for (final productText in productTexts) {
      final productY = (productText.y1 + productText.y2) / 2;
      final productHeight = productText.y2 - productText.y1;
      final tolerance = productHeight * 1.2; // Flexible tolerance

      // Find all texts on the same row
      final row = tableTexts.where((t) {
        if (t == productText) return false;
        final textY = (t.y1 + t.y2) / 2;
        return (textY - productY).abs() < tolerance;
      }).toList();

      row.sort((a, b) => a.x1.compareTo(b.x1));

      // Extract values from row
      String name = productText.text.trim();
      String spec = '';
      int quantity = 0;
      String unit = '';
      int unitPrice = 0;
      int amount = 0;

      // Collect all prices from the row
      final prices = <int>[];

      for (final cell in row) {
        final cellText = cell.text.trim();

        // Skip the product name itself if it appears again
        if (cellText == name) continue;

        // Check for price (contains $ or comma-separated number)
        final priceMatch = RegExp(r'\$?([\d,]+)').firstMatch(cellText);
        if (priceMatch != null && cellText.contains('\$')) {
          final value = int.tryParse(priceMatch.group(1)!.replaceAll(',', '')) ?? 0;
          if (value > 0) {
            prices.add(value);
            continue;
          }
        }

        // Check for quantity (pure number, usually 2-4 digits)
        if (RegExp(r'^\d{1,4}$').hasMatch(cellText)) {
          final val = int.tryParse(cellText) ?? 0;
          if (val > 0 && val < 10000 && quantity == 0) {
            quantity = val;
            continue;
          }
        }

        // Check for unit (single Chinese character)
        if (cellText.length <= 2 && unit.isEmpty &&
            RegExp(r'^[片個組件台套塊顆]$').hasMatch(cellText)) {
          unit = cellText;
          continue;
        }

        // Check for spec (if product already has name, other Chinese+alphanumeric is spec)
        if (spec.isEmpty && cellText.length > 1 &&
            !RegExp(r'^\d+$').hasMatch(cellText) &&
            !cellText.startsWith('\$')) {
          spec = cellText;
        }
      }

      // Sort prices by value, last one is usually amount (largest), second last is unit price
      prices.sort();
      if (prices.length >= 2) {
        amount = prices.last;
        unitPrice = prices[prices.length - 2];
      } else if (prices.length == 1) {
        amount = prices.first;
        // Try to calculate unit price if we have quantity
        if (quantity > 0) {
          unitPrice = (amount / quantity).round();
        }
      }

      debugPrint('[QuotationExtractor] Item $itemIndex: $name, qty=$quantity, price=$unitPrice, amount=$amount');

      if (name.isNotEmpty && amount > 0) {
        items.add(QuotationItem(
          index: itemIndex,
          name: name,
          spec: spec,
          quantity: quantity,
          unit: unit,
          unitPrice: unitPrice,
          amount: amount,
        ));
        itemIndex++;
      }
    }

    return items;
  }

  /// Extract totals (subtotal, tax, total)
  Map<String, int?> _extractTotals(List<TextLine> texts) {
    int? subtotal;
    int? tax;
    int? total;

    // Sort texts by Y position (top to bottom)
    final sortedTexts = List<TextLine>.from(texts)
      ..sort((a, b) => a.y1.compareTo(b.y1));

    // First pass: find all labeled values
    final Map<String, List<(int, double)>> candidates = {
      'subtotal': [],
      'tax': [],
      'total': [],
    };

    for (int i = 0; i < sortedTexts.length; i++) {
      final t = sortedTexts[i].text.replaceAll(' ', '');
      final y = sortedTexts[i].y1;

      if (t.contains('總計') || t.contains('合計')) {
        final price = _findNearbyPrice(sortedTexts, i);
        if (price != null && price > 100) {
          candidates['total']!.add((price, y));
          debugPrint('[QuotationExtractor] Found total candidate: $price from "${sortedTexts[i].text}"');
        }
      } else if (t.contains('小計')) {
        final price = _findNearbyPrice(sortedTexts, i);
        if (price != null && price > 100) {
          candidates['subtotal']!.add((price, y));
          debugPrint('[QuotationExtractor] Found subtotal candidate: $price from "${sortedTexts[i].text}"');
        }
      } else if (t.contains('稅額') || t.contains('營業稅')) {
        final price = _findNearbyPrice(sortedTexts, i);
        if (price != null) {
          candidates['tax']!.add((price, y));
          debugPrint('[QuotationExtractor] Found tax candidate: $price from "${sortedTexts[i].text}"');
        }
      }
    }

    // Select the best candidates (prefer the one at highest Y = bottom of document)
    if (candidates['total']!.isNotEmpty) {
      candidates['total']!.sort((a, b) => b.$2.compareTo(a.$2)); // Sort by Y descending
      total = candidates['total']!.first.$1;
    }
    if (candidates['subtotal']!.isNotEmpty) {
      candidates['subtotal']!.sort((a, b) => b.$2.compareTo(a.$2));
      subtotal = candidates['subtotal']!.first.$1;
    }
    if (candidates['tax']!.isNotEmpty) {
      // Tax should be smaller than subtotal, filter out wrong values
      final validTaxes = candidates['tax']!.where((t) {
        if (subtotal != null) return t.$1 < subtotal;
        if (total != null) return t.$1 < total;
        return t.$1 < 10000; // Reasonable tax amount
      }).toList();
      if (validTaxes.isNotEmpty) {
        validTaxes.sort((a, b) => b.$2.compareTo(a.$2));
        tax = validTaxes.first.$1;
      }
    }

    debugPrint('[QuotationExtractor] Final: subtotal=$subtotal, tax=$tax, total=$total');

    // If total not found but subtotal exists, calculate total
    if (total == null && subtotal != null) {
      if (tax != null) {
        total = subtotal + tax;
      } else {
        total = subtotal;
      }
      debugPrint('[QuotationExtractor] Calculated total: $total');
    }

    // If still no total, find the largest price
    if (total == null) {
      final pricePattern = RegExp(r'\$(\d{1,3}(?:,\d{3})*|\d+)');
      int maxPrice = 0;
      for (final text in texts) {
        final match = pricePattern.firstMatch(text.text);
        if (match != null) {
          final price = int.tryParse(match.group(1)!.replaceAll(',', '')) ?? 0;
          if (price > maxPrice) maxPrice = price;
        }
      }
      if (maxPrice > 0) {
        total = maxPrice;
        debugPrint('[QuotationExtractor] Fallback total (max price): $total');
      }
    }

    return {
      'subtotal': subtotal,
      'tax': tax,
      'total': total,
    };
  }

  int? _findNearbyPrice(List<TextLine> texts, int labelIndex) {
    final labelLine = texts[labelIndex];
    final labelY = (labelLine.y1 + labelLine.y2) / 2;
    final labelHeight = labelLine.y2 - labelLine.y1;
    final tolerance = labelHeight * 1.5; // More flexible tolerance based on text height

    // Pattern to match prices with $ or just numbers
    final pricePattern = RegExp(r'\$?([\d,]+)');

    // Collect all candidates on the same line (to the right of label)
    final candidates = <(int price, double distance)>[];

    for (final text in texts) {
      if (text == labelLine) continue;

      final textY = (text.y1 + text.y2) / 2;

      // Must be on same line (within tolerance) and to the right
      if ((textY - labelY).abs() > tolerance) continue;
      if (text.x1 <= labelLine.x2) continue;

      final match = pricePattern.firstMatch(text.text);
      if (match != null) {
        final price = int.tryParse(match.group(1)!.replaceAll(',', ''));
        if (price != null && price > 0) {
          final distance = text.x1 - labelLine.x2;
          candidates.add((price, distance));
        }
      }
    }

    // Return the closest candidate (smallest distance)
    if (candidates.isNotEmpty) {
      candidates.sort((a, b) => a.$2.compareTo(b.$2));
      return candidates.first.$1;
    }

    // Check in label text itself (e.g., "總計 $13598")
    final match = pricePattern.firstMatch(labelLine.text);
    if (match != null) {
      final price = int.tryParse(match.group(1)!.replaceAll(',', ''));
      // Avoid returning small numbers that might be percentages
      if (price != null && price > 100) {
        return price;
      }
    }

    return null;
  }
}

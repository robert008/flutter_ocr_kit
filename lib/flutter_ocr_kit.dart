import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/services.dart';

import 'flutter_ocr_kit_bindings_generated.dart';
import 'src/models.dart';

export 'src/models.dart';
export 'src/ocr_service.dart';
export 'src/kie_extractor.dart';
export 'src/invoice_extractor.dart';
export 'src/quotation_extractor.dart';

/// OCR Kit - Flutter FFI plugin with Core ML / NNAPI acceleration
///
/// Provides both layout detection and OCR (text recognition) capabilities.
///
/// Usage:
/// ```dart
/// // Initialize layout detection
/// OcrKit.init('/path/to/layout_model.onnx');
///
/// // Initialize OCR (detection + recognition)
/// OcrKit.initOcr(
///   detModelPath: '/path/to/det.onnx',
///   recModelPath: '/path/to/rec.onnx',
///   dictPath: '/path/to/ppocr_keys_v1.txt',
/// );
///
/// // Recognize text
/// final result = OcrKit.recognizeText('/path/to/image.jpg');
/// for (final line in result.results) {
///   print('${line.text} at ${line.rect}');
/// }
///
/// // Find specific text
/// final matches = result.findText('Robert');
/// ```
class OcrKit {
  static OcrKitBindings? _bindings;
  static bool _isLayoutInitialized = false;
  static bool _isOcrInitialized = false;

  OcrKit._();

  static OcrKitBindings get _native {
    _bindings ??= OcrKitBindings(_loadLibrary());
    return _bindings!;
  }

  static DynamicLibrary _loadLibrary() {
    if (Platform.isIOS || Platform.isMacOS) {
      return DynamicLibrary.process();
    }
    if (Platform.isAndroid || Platform.isLinux) {
      return DynamicLibrary.open('libocr_kit.so');
    }
    if (Platform.isWindows) {
      return DynamicLibrary.open('ocr_kit.dll');
    }

    throw UnsupportedError('Unsupported platform: ${Platform.operatingSystem}');
  }

  /// Check if layout detection is initialized
  static bool get isInitialized => _isLayoutInitialized;

  /// Check if OCR is initialized
  static bool get isOcrInitialized => _isOcrInitialized;

  /// Get library version
  static String get version {
    final ptr = _native.getVersion();
    return ptr.cast<Utf8>().toDartString();
  }

  // ========================
  // Layout Detection API
  // ========================

  /// Initialize layout detection model
  static void init(String modelPath) {
    final pathPtr = modelPath.toNativeUtf8().cast<Char>();
    try {
      _native.initModel(pathPtr);
    } finally {
      calloc.free(pathPtr);
    }
    _isLayoutInitialized = true;
  }

  /// Detect layout from image file
  static LayoutResult detectLayout(
    String imagePath, {
    double confThreshold = 0.5,
  }) {
    _checkLayoutInitialized();

    final pathPtr = imagePath.toNativeUtf8().cast<Char>();
    Pointer<Char>? resultPtr;

    try {
      resultPtr = _native.detectLayout(pathPtr, confThreshold);
      final jsonStr = resultPtr.cast<Utf8>().toDartString();
      return LayoutResult.fromJson(jsonDecode(jsonStr));
    } finally {
      calloc.free(pathPtr);
      if (resultPtr != null) {
        _native.freeString(resultPtr);
      }
    }
  }

  // ========================
  // OCR API
  // ========================

  /// Initialize OCR models (detection + recognition + dictionary)
  ///
  /// [detModelPath] - Path to text detection model (e.g., ch_PP-OCRv4_det.onnx)
  /// [recModelPath] - Path to text recognition model (e.g., ch_PP-OCRv4_rec.onnx)
  /// [dictPath] - Path to character dictionary file (e.g., ppocr_keys_v1.txt)
  static void initOcr({
    required String detModelPath,
    required String recModelPath,
    required String dictPath,
  }) {
    final detPtr = detModelPath.toNativeUtf8().cast<Char>();
    final recPtr = recModelPath.toNativeUtf8().cast<Char>();
    final dictPtr = dictPath.toNativeUtf8().cast<Char>();

    try {
      _native.initOcrModels(detPtr, recPtr, dictPtr);
    } finally {
      calloc.free(detPtr);
      calloc.free(recPtr);
      calloc.free(dictPtr);
    }
    _isOcrInitialized = true;
  }

  /// Release OCR engine resources
  static void releaseOcr() {
    if (_isOcrInitialized) {
      _native.releaseOcrEngine();
      _isOcrInitialized = false;
    }
  }

  /// Recognize text from image file (full OCR: detect + recognize)
  ///
  /// [imagePath] - Path to image file
  /// [detThreshold] - Detection confidence threshold (0.0 - 1.0), default 0.3
  /// [recThreshold] - Recognition confidence threshold (0.0 - 1.0), default 0.5
  ///
  /// Returns [OcrResult] containing recognized text lines with bounding boxes.
  static OcrResult recognizeText(
    String imagePath, {
    double detThreshold = 0.3,
    double recThreshold = 0.5,
  }) {
    _checkOcrInitialized();

    final pathPtr = imagePath.toNativeUtf8().cast<Char>();
    Pointer<Char>? resultPtr;

    try {
      resultPtr = _native.recognizeTextFromPath(pathPtr, detThreshold, recThreshold);
      final jsonStr = resultPtr.cast<Utf8>().toDartString();
      return OcrResult.fromJson(jsonDecode(jsonStr));
    } finally {
      calloc.free(pathPtr);
      if (resultPtr != null) {
        _native.freeString(resultPtr);
      }
    }
  }

  /// Detect text regions only (without recognition)
  ///
  /// Faster than full OCR when you only need text locations.
  static TextDetectionResult detectText(
    String imagePath, {
    double threshold = 0.3,
  }) {
    _checkOcrInitialized();

    final pathPtr = imagePath.toNativeUtf8().cast<Char>();
    Pointer<Char>? resultPtr;

    try {
      resultPtr = _native.detectTextFromPath(pathPtr, threshold);
      final jsonStr = resultPtr.cast<Utf8>().toDartString();
      return TextDetectionResult.fromJson(jsonDecode(jsonStr));
    } finally {
      calloc.free(pathPtr);
      if (resultPtr != null) {
        _native.freeString(resultPtr);
      }
    }
  }

  static void _checkLayoutInitialized() {
    if (!_isLayoutInitialized) {
      throw StateError(
        'Layout detection is not initialized. Call OcrKit.init() first.',
      );
    }
  }

  static void _checkOcrInitialized() {
    if (!_isOcrInitialized) {
      throw StateError(
        'OCR is not initialized. Call OcrKit.initOcr() first.',
      );
    }
  }

  // ========================
  // Apple Vision OCR API (iOS only)
  // ========================

  /// Recognize text from image using Apple Vision Framework
  ///
  /// This uses Apple's native Vision framework for text recognition.
  /// No initialization required - works immediately on iOS.
  ///
  /// [imagePath] - Path to image file
  /// [languages] - List of language codes (e.g., ['zh-Hant', 'zh-Hans', 'en-US'])
  ///               If empty, defaults to Chinese + English with auto-detection on iOS 16+
  ///
  /// Returns [OcrResult] containing recognized text lines with bounding boxes.
  static OcrResult recognizeWithVision(
    String imagePath, {
    List<String> languages = const [],
  }) {
    if (!Platform.isIOS && !Platform.isMacOS) {
      throw UnsupportedError('Vision OCR is only available on iOS/macOS');
    }

    final pathPtr = imagePath.toNativeUtf8().cast<Char>();
    final langStr = languages.join(',');
    final langPtr = langStr.toNativeUtf8().cast<Char>();
    Pointer<Char>? resultPtr;

    try {
      resultPtr = _native.recognizeTextWithVision(pathPtr, langPtr);
      final jsonStr = resultPtr.cast<Utf8>().toDartString();
      return OcrResult.fromJson(jsonDecode(jsonStr));
    } finally {
      calloc.free(pathPtr);
      calloc.free(langPtr);
      if (resultPtr != null) {
        _native.freeString(resultPtr);
      }
    }
  }

  /// Recognize text from a cropped region using Apple Vision
  ///
  /// Use this with layout detection results to OCR specific regions.
  ///
  /// [imagePath] - Path to image file
  /// [x1], [y1], [x2], [y2] - Crop region coordinates in original image space
  /// [languages] - List of language codes
  ///
  /// Returns [OcrResult] with coordinates mapped back to original image space.
  static OcrResult recognizeRegionWithVision(
    String imagePath, {
    required double x1,
    required double y1,
    required double x2,
    required double y2,
    List<String> languages = const [],
  }) {
    if (!Platform.isIOS && !Platform.isMacOS) {
      throw UnsupportedError('Vision OCR is only available on iOS/macOS');
    }

    final pathPtr = imagePath.toNativeUtf8().cast<Char>();
    final langStr = languages.join(',');
    final langPtr = langStr.toNativeUtf8().cast<Char>();
    Pointer<Char>? resultPtr;

    try {
      resultPtr = _native.recognizeRegionWithVision(
        pathPtr, x1, y1, x2, y2, langPtr);
      final jsonStr = resultPtr.cast<Utf8>().toDartString();
      return OcrResult.fromJson(jsonDecode(jsonStr));
    } finally {
      calloc.free(pathPtr);
      calloc.free(langPtr);
      if (resultPtr != null) {
        _native.freeString(resultPtr);
      }
    }
  }

  /// Get supported languages for Vision OCR
  ///
  /// Returns list of supported language codes for text recognition.
  static List<String> getVisionSupportedLanguages() {
    if (!Platform.isIOS && !Platform.isMacOS) {
      throw UnsupportedError('Vision OCR is only available on iOS/macOS');
    }

    final resultPtr = _native.getVisionSupportedLanguages();
    try {
      final jsonStr = resultPtr.cast<Utf8>().toDartString();
      final List<dynamic> languages = jsonDecode(jsonStr);
      return languages.cast<String>();
    } finally {
      _native.freeString(resultPtr);
    }
  }

  // ========================
  // Google ML Kit OCR API (Android only)
  // ========================

  static const MethodChannel _channel = MethodChannel('flutter_ocr_kit');

  /// Recognize text from image using Google ML Kit (Android)
  ///
  /// This uses Google's ML Kit for text recognition.
  /// No initialization required - works immediately on Android.
  ///
  /// [imagePath] - Path to image file
  /// [languages] - List of language codes (e.g., ['zh-Hant', 'zh-Hans', 'en'])
  ///
  /// Returns [OcrResult] containing recognized text lines with bounding boxes.
  static Future<OcrResult> recognizeWithMlKit(
    String imagePath, {
    List<String> languages = const [],
  }) async {
    if (!Platform.isAndroid) {
      throw UnsupportedError('ML Kit OCR is only available on Android');
    }

    final String result = await _channel.invokeMethod('recognizeWithMlKit', {
      'imagePath': imagePath,
      'languages': languages,
    });

    return OcrResult.fromJson(jsonDecode(result));
  }

  /// Recognize text from a cropped region using Google ML Kit
  ///
  /// Use this with layout detection results to OCR specific regions.
  ///
  /// [imagePath] - Path to image file
  /// [x1], [y1], [x2], [y2] - Crop region coordinates in original image space
  /// [languages] - List of language codes
  ///
  /// Returns [OcrResult] with coordinates mapped back to original image space.
  static Future<OcrResult> recognizeRegionWithMlKit(
    String imagePath, {
    required double x1,
    required double y1,
    required double x2,
    required double y2,
    List<String> languages = const [],
  }) async {
    if (!Platform.isAndroid) {
      throw UnsupportedError('ML Kit OCR is only available on Android');
    }

    final String result = await _channel.invokeMethod('recognizeRegionWithMlKit', {
      'imagePath': imagePath,
      'x1': x1,
      'y1': y1,
      'x2': x2,
      'y2': y2,
      'languages': languages,
    });

    return OcrResult.fromJson(jsonDecode(result));
  }

  /// Get supported languages for ML Kit OCR
  ///
  /// Returns list of supported language codes for text recognition.
  static Future<List<String>> getMlKitSupportedLanguages() async {
    if (!Platform.isAndroid) {
      throw UnsupportedError('ML Kit OCR is only available on Android');
    }

    final List<dynamic> result = await _channel.invokeMethod('getMlKitSupportedLanguages');
    return result.cast<String>();
  }

  // ========================
  // Cross-Platform Native OCR API
  // ========================

  /// Recognize text using platform-native OCR
  ///
  /// Automatically uses:
  /// - Apple Vision on iOS/macOS
  /// - Google ML Kit on Android
  ///
  /// No initialization required - works immediately.
  ///
  /// [imagePath] - Path to image file
  /// [languages] - List of language codes (e.g., ['zh-Hant', 'zh-Hans', 'en'])
  ///
  /// Returns [OcrResult] containing recognized text lines with bounding boxes.
  static Future<OcrResult> recognizeNative(
    String imagePath, {
    List<String> languages = const [],
  }) async {
    if (Platform.isIOS || Platform.isMacOS) {
      return recognizeWithVision(imagePath, languages: languages);
    } else if (Platform.isAndroid) {
      return recognizeWithMlKit(imagePath, languages: languages);
    } else {
      throw UnsupportedError(
        'Native OCR is not available on ${Platform.operatingSystem}',
      );
    }
  }

  /// Recognize text from a cropped region using platform-native OCR
  ///
  /// Automatically uses Vision (iOS) or ML Kit (Android).
  ///
  /// [imagePath] - Path to image file
  /// [x1], [y1], [x2], [y2] - Crop region coordinates in original image space
  /// [languages] - List of language codes
  ///
  /// Returns [OcrResult] with coordinates mapped back to original image space.
  static Future<OcrResult> recognizeRegionNative(
    String imagePath, {
    required double x1,
    required double y1,
    required double x2,
    required double y2,
    List<String> languages = const [],
  }) async {
    if (Platform.isIOS || Platform.isMacOS) {
      return recognizeRegionWithVision(
        imagePath,
        x1: x1, y1: y1, x2: x2, y2: y2,
        languages: languages,
      );
    } else if (Platform.isAndroid) {
      return recognizeRegionWithMlKit(
        imagePath,
        x1: x1, y1: y1, x2: x2, y2: y2,
        languages: languages,
      );
    } else {
      throw UnsupportedError(
        'Native OCR is not available on ${Platform.operatingSystem}',
      );
    }
  }

  /// Get supported languages for native OCR
  ///
  /// Returns list of supported language codes for text recognition.
  static Future<List<String>> getNativeSupportedLanguages() async {
    if (Platform.isIOS || Platform.isMacOS) {
      return getVisionSupportedLanguages();
    } else if (Platform.isAndroid) {
      return getMlKitSupportedLanguages();
    } else {
      throw UnsupportedError(
        'Native OCR is not available on ${Platform.operatingSystem}',
      );
    }
  }
}

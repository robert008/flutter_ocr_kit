import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';

import '../flutter_ocr_kit_bindings_generated.dart';
import 'models.dart';

/// High-level OCR/Layout detection service with isolate support
///
/// This service automatically runs detection in a background isolate
/// to prevent blocking the UI thread.
///
/// Usage:
/// ```dart
/// // Initialize OCR models
/// await OcrService.initOcr(
///   detModelPath: '/path/to/det.onnx',
///   recModelPath: '/path/to/rec.onnx',
///   dictPath: '/path/to/ppocr_keys_v1.txt',
/// );
///
/// // Recognize text from image
/// final result = await OcrService.recognizeText(
///   imageBytes: imageBytes,
///   detThreshold: 0.3,
///   recThreshold: 0.5,
/// );
///
/// // Find specific text
/// final matches = result.findText('Robert');
/// for (final match in matches) {
///   print('Found at: ${match.rect}');
/// }
/// ```
class OcrService {
  /// Private constructor
  OcrService._();

  /// Cached paths for OCR models
  static String? _detModelPath;
  static String? _recModelPath;
  static String? _dictPath;

  /// Check if OCR is initialized
  static bool get isOcrInitialized =>
      _detModelPath != null && _recModelPath != null && _dictPath != null;

  /// Set OCR model paths (call before using OCR functions)
  static void setOcrModels({
    required String detModelPath,
    required String recModelPath,
    required String dictPath,
  }) {
    _detModelPath = detModelPath;
    _recModelPath = recModelPath;
    _dictPath = dictPath;
  }

  // ========================
  // Layout Detection API
  // ========================

  /// Detect document layout from image bytes in a background isolate
  ///
  /// [imageBytes] - Image data in any format supported by OpenCV (PNG, JPEG, etc.)
  /// [modelPath] - Path to the ONNX model file
  /// [confThreshold] - Confidence threshold (0.0 - 1.0), default 0.3
  /// [tempDirectory] - Optional temporary directory for saving image file
  ///
  /// Returns [LayoutResult] containing detected layout elements.
  /// Automatically runs in a background isolate to avoid blocking UI.
  static Future<LayoutResult> detectLayout({
    required Uint8List imageBytes,
    required String modelPath,
    double confThreshold = 0.3,
    String? tempDirectory,
  }) async {
    // Use compute() to automatically create and manage isolate
    return compute(_isolateDetect, {
      'imageBytes': imageBytes,
      'modelPath': modelPath,
      'confThreshold': confThreshold,
      'tempDirectory': tempDirectory,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
  }

  /// Isolate entry point for layout detection
  static LayoutResult _isolateDetect(Map<String, dynamic> params) {
    // Extract parameters
    final Uint8List imageBytes = params['imageBytes'];
    final String modelPath = params['modelPath'];
    final double confThreshold = params['confThreshold'];
    final String? tempDir = params['tempDirectory'];
    final int timestamp = params['timestamp'];

    // Determine temp directory
    String tempDirPath;
    if (tempDir != null) {
      tempDirPath = tempDir;
    } else {
      final dir = Directory.systemTemp;
      tempDirPath = dir.path;
    }

    // Generate temporary file path
    final fileName = 'ocr_kit_$timestamp.png';
    final filePath = '$tempDirPath/$fileName';

    try {
      // Step 1: Initialize FFI in isolate
      late final DynamicLibrary nativeLib;
      late final OcrKitBindings bindings;

      try {
        if (Platform.isIOS || Platform.isMacOS) {
          nativeLib = DynamicLibrary.process();
        } else if (Platform.isAndroid || Platform.isLinux) {
          nativeLib = DynamicLibrary.open('libocr_kit.so');
        } else if (Platform.isWindows) {
          nativeLib = DynamicLibrary.open('ocr_kit.dll');
        } else {
          return LayoutResult(
            detections: [],
            count: 0,
            inferenceTimeMs: 0,
            imageWidth: 0,
            imageHeight: 0,
            error: 'Unsupported platform: ${Platform.operatingSystem}',
          );
        }

        bindings = OcrKitBindings(nativeLib);
      } catch (e) {
        return LayoutResult(
          detections: [],
          count: 0,
          inferenceTimeMs: 0,
          imageWidth: 0,
          imageHeight: 0,
          error: 'FFI initialization failed: $e',
        );
      }

      // Step 2: Initialize model
      final modelPathPtr = modelPath.toNativeUtf8().cast<Char>();
      try {
        bindings.initModel(modelPathPtr);
      } catch (e) {
        calloc.free(modelPathPtr);
        return LayoutResult(
          detections: [],
          count: 0,
          inferenceTimeMs: 0,
          imageWidth: 0,
          imageHeight: 0,
          error: 'Model initialization failed: $e',
        );
      } finally {
        calloc.free(modelPathPtr);
      }

      // Step 3: Save image to temporary file
      try {
        File(filePath).writeAsBytesSync(imageBytes, flush: false);
      } catch (e) {
        return LayoutResult(
          detections: [],
          count: 0,
          inferenceTimeMs: 0,
          imageWidth: 0,
          imageHeight: 0,
          error: 'Failed to save image: $e',
        );
      }

      final savedFile = File(filePath);
      if (!savedFile.existsSync()) {
        return LayoutResult(
          detections: [],
          count: 0,
          inferenceTimeMs: 0,
          imageWidth: 0,
          imageHeight: 0,
          error: 'Image file not found after saving',
        );
      }

      // Step 4: Call native detection function
      final imagePathPtr = filePath.toNativeUtf8().cast<Char>();
      Pointer<Char>? resultPtr;

      try {
        resultPtr = bindings.detectLayout(imagePathPtr, confThreshold);
        final jsonStr = resultPtr.cast<Utf8>().toDartString();

        // Step 5: Parse result
        final result = LayoutResult.fromJson(jsonDecode(jsonStr));

        // Step 6: Clean up temporary file
        try {
          savedFile.deleteSync();
        } catch (e) {
          debugPrint('[Isolate] Warning: Failed to delete temp file: $e');
        }

        return result;
      } catch (e) {
        try {
          savedFile.deleteSync();
        } catch (_) {}
        return LayoutResult(
          detections: [],
          count: 0,
          inferenceTimeMs: 0,
          imageWidth: 0,
          imageHeight: 0,
          error: 'Detection failed: $e',
        );
      } finally {
        calloc.free(imagePathPtr);
        if (resultPtr != null) {
          bindings.freeString(resultPtr);
        }
      }
    } catch (e) {
      try {
        File(filePath).deleteSync();
      } catch (_) {}
      return LayoutResult(
        detections: [],
        count: 0,
        inferenceTimeMs: 0,
        imageWidth: 0,
        imageHeight: 0,
        error: 'Unexpected error: $e',
      );
    }
  }

  // ========================
  // OCR API
  // ========================

  /// Recognize text from image bytes in a background isolate
  ///
  /// [imageBytes] - Image data (PNG, JPEG, etc.)
  /// [detThreshold] - Detection confidence threshold (0.0 - 1.0), default 0.3
  /// [recThreshold] - Recognition confidence threshold (0.0 - 1.0), default 0.5
  /// [tempDirectory] - Optional temporary directory
  ///
  /// Returns [OcrResult] containing recognized text lines with bounding boxes.
  static Future<OcrResult> recognizeText({
    required Uint8List imageBytes,
    double detThreshold = 0.3,
    double recThreshold = 0.5,
    String? tempDirectory,
  }) async {
    if (!isOcrInitialized) {
      return OcrResult(
        results: [],
        count: 0,
        inferenceTimeMs: 0,
        imageWidth: 0,
        imageHeight: 0,
        error: 'OCR not initialized. Call setOcrModels() first.',
      );
    }

    return compute(_isolateOcrRecognize, {
      'imageBytes': imageBytes,
      'detModelPath': _detModelPath!,
      'recModelPath': _recModelPath!,
      'dictPath': _dictPath!,
      'detThreshold': detThreshold,
      'recThreshold': recThreshold,
      'tempDirectory': tempDirectory,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
  }

  /// Isolate entry point for OCR recognition
  static OcrResult _isolateOcrRecognize(Map<String, dynamic> params) {
    final Uint8List imageBytes = params['imageBytes'];
    final String detModelPath = params['detModelPath'];
    final String recModelPath = params['recModelPath'];
    final String dictPath = params['dictPath'];
    final double detThreshold = params['detThreshold'];
    final double recThreshold = params['recThreshold'];
    final String? tempDir = params['tempDirectory'];
    final int timestamp = params['timestamp'];

    String tempDirPath;
    if (tempDir != null) {
      tempDirPath = tempDir;
    } else {
      tempDirPath = Directory.systemTemp.path;
    }

    final fileName = 'ocr_$timestamp.png';
    final filePath = '$tempDirPath/$fileName';

    try {
      // Initialize FFI
      late final DynamicLibrary nativeLib;
      late final OcrKitBindings bindings;

      try {
        if (Platform.isIOS || Platform.isMacOS) {
          nativeLib = DynamicLibrary.process();
        } else if (Platform.isAndroid || Platform.isLinux) {
          nativeLib = DynamicLibrary.open('libocr_kit.so');
        } else if (Platform.isWindows) {
          nativeLib = DynamicLibrary.open('ocr_kit.dll');
        } else {
          return OcrResult(
            results: [],
            count: 0,
            inferenceTimeMs: 0,
            imageWidth: 0,
            imageHeight: 0,
            error: 'Unsupported platform',
          );
        }
        bindings = OcrKitBindings(nativeLib);
      } catch (e) {
        return OcrResult(
          results: [],
          count: 0,
          inferenceTimeMs: 0,
          imageWidth: 0,
          imageHeight: 0,
          error: 'FFI initialization failed: $e',
        );
      }

      // Initialize OCR models
      final detPtr = detModelPath.toNativeUtf8().cast<Char>();
      final recPtr = recModelPath.toNativeUtf8().cast<Char>();
      final dictPtr = dictPath.toNativeUtf8().cast<Char>();

      try {
        bindings.initOcrModels(detPtr, recPtr, dictPtr);
      } catch (e) {
        calloc.free(detPtr);
        calloc.free(recPtr);
        calloc.free(dictPtr);
        return OcrResult(
          results: [],
          count: 0,
          inferenceTimeMs: 0,
          imageWidth: 0,
          imageHeight: 0,
          error: 'OCR model initialization failed: $e',
        );
      } finally {
        calloc.free(detPtr);
        calloc.free(recPtr);
        calloc.free(dictPtr);
      }

      // Save image to temporary file
      try {
        File(filePath).writeAsBytesSync(imageBytes, flush: false);
      } catch (e) {
        return OcrResult(
          results: [],
          count: 0,
          inferenceTimeMs: 0,
          imageWidth: 0,
          imageHeight: 0,
          error: 'Failed to save image: $e',
        );
      }

      final savedFile = File(filePath);

      // Call native OCR function
      final imagePathPtr = filePath.toNativeUtf8().cast<Char>();
      Pointer<Char>? resultPtr;

      try {
        resultPtr = bindings.recognizeTextFromPath(
            imagePathPtr, detThreshold, recThreshold);
        final jsonStr = resultPtr.cast<Utf8>().toDartString();

        final result = OcrResult.fromJson(jsonDecode(jsonStr));

        try {
          savedFile.deleteSync();
        } catch (_) {}

        return result;
      } catch (e) {
        try {
          savedFile.deleteSync();
        } catch (_) {}
        return OcrResult(
          results: [],
          count: 0,
          inferenceTimeMs: 0,
          imageWidth: 0,
          imageHeight: 0,
          error: 'OCR failed: $e',
        );
      } finally {
        calloc.free(imagePathPtr);
        if (resultPtr != null) {
          bindings.freeString(resultPtr);
        }
      }
    } catch (e) {
      try {
        File(filePath).deleteSync();
      } catch (_) {}
      return OcrResult(
        results: [],
        count: 0,
        inferenceTimeMs: 0,
        imageWidth: 0,
        imageHeight: 0,
        error: 'Unexpected error: $e',
      );
    }
  }

  /// Detect text regions only (without recognition) in a background isolate
  ///
  /// Faster than full OCR when you only need text locations.
  static Future<TextDetectionResult> detectText({
    required Uint8List imageBytes,
    double threshold = 0.3,
    String? tempDirectory,
  }) async {
    if (!isOcrInitialized) {
      return TextDetectionResult(
        boxes: [],
        count: 0,
        inferenceTimeMs: 0,
        imageWidth: 0,
        imageHeight: 0,
        error: 'OCR not initialized. Call setOcrModels() first.',
      );
    }

    return compute(_isolateDetectText, {
      'imageBytes': imageBytes,
      'detModelPath': _detModelPath!,
      'recModelPath': _recModelPath!,
      'dictPath': _dictPath!,
      'threshold': threshold,
      'tempDirectory': tempDirectory,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
  }

  /// Isolate entry point for text detection
  static TextDetectionResult _isolateDetectText(Map<String, dynamic> params) {
    final Uint8List imageBytes = params['imageBytes'];
    final String detModelPath = params['detModelPath'];
    final String recModelPath = params['recModelPath'];
    final String dictPath = params['dictPath'];
    final double threshold = params['threshold'];
    final String? tempDir = params['tempDirectory'];
    final int timestamp = params['timestamp'];

    String tempDirPath;
    if (tempDir != null) {
      tempDirPath = tempDir;
    } else {
      tempDirPath = Directory.systemTemp.path;
    }

    final fileName = 'text_det_$timestamp.png';
    final filePath = '$tempDirPath/$fileName';

    try {
      // Initialize FFI
      late final DynamicLibrary nativeLib;
      late final OcrKitBindings bindings;

      try {
        if (Platform.isIOS || Platform.isMacOS) {
          nativeLib = DynamicLibrary.process();
        } else if (Platform.isAndroid || Platform.isLinux) {
          nativeLib = DynamicLibrary.open('libocr_kit.so');
        } else if (Platform.isWindows) {
          nativeLib = DynamicLibrary.open('ocr_kit.dll');
        } else {
          return TextDetectionResult(
            boxes: [],
            count: 0,
            inferenceTimeMs: 0,
            imageWidth: 0,
            imageHeight: 0,
            error: 'Unsupported platform',
          );
        }
        bindings = OcrKitBindings(nativeLib);
      } catch (e) {
        return TextDetectionResult(
          boxes: [],
          count: 0,
          inferenceTimeMs: 0,
          imageWidth: 0,
          imageHeight: 0,
          error: 'FFI initialization failed: $e',
        );
      }

      // Initialize OCR models
      final detPtr = detModelPath.toNativeUtf8().cast<Char>();
      final recPtr = recModelPath.toNativeUtf8().cast<Char>();
      final dictPtr = dictPath.toNativeUtf8().cast<Char>();

      try {
        bindings.initOcrModels(detPtr, recPtr, dictPtr);
      } finally {
        calloc.free(detPtr);
        calloc.free(recPtr);
        calloc.free(dictPtr);
      }

      // Save image
      try {
        File(filePath).writeAsBytesSync(imageBytes, flush: false);
      } catch (e) {
        return TextDetectionResult(
          boxes: [],
          count: 0,
          inferenceTimeMs: 0,
          imageWidth: 0,
          imageHeight: 0,
          error: 'Failed to save image: $e',
        );
      }

      final savedFile = File(filePath);

      // Call native function
      final imagePathPtr = filePath.toNativeUtf8().cast<Char>();
      Pointer<Char>? resultPtr;

      try {
        resultPtr = bindings.detectTextFromPath(imagePathPtr, threshold);
        final jsonStr = resultPtr.cast<Utf8>().toDartString();

        final result = TextDetectionResult.fromJson(jsonDecode(jsonStr));

        try {
          savedFile.deleteSync();
        } catch (_) {}

        return result;
      } catch (e) {
        try {
          savedFile.deleteSync();
        } catch (_) {}
        return TextDetectionResult(
          boxes: [],
          count: 0,
          inferenceTimeMs: 0,
          imageWidth: 0,
          imageHeight: 0,
          error: 'Detection failed: $e',
        );
      } finally {
        calloc.free(imagePathPtr);
        if (resultPtr != null) {
          bindings.freeString(resultPtr);
        }
      }
    } catch (e) {
      try {
        File(filePath).deleteSync();
      } catch (_) {}
      return TextDetectionResult(
        boxes: [],
        count: 0,
        inferenceTimeMs: 0,
        imageWidth: 0,
        imageHeight: 0,
        error: 'Unexpected error: $e',
      );
    }
  }

  /// Release OCR engine resources
  static void releaseOcr() {
    try {
      late final DynamicLibrary nativeLib;
      if (Platform.isIOS || Platform.isMacOS) {
        nativeLib = DynamicLibrary.process();
      } else if (Platform.isAndroid || Platform.isLinux) {
        nativeLib = DynamicLibrary.open('libocr_kit.so');
      } else if (Platform.isWindows) {
        nativeLib = DynamicLibrary.open('ocr_kit.dll');
      } else {
        return;
      }
      final bindings = OcrKitBindings(nativeLib);
      bindings.releaseOcrEngine();
    } catch (e) {
      debugPrint('Warning: Failed to release OCR engine: $e');
    }
  }
}

// ignore_for_file: always_specify_types
// ignore_for_file: camel_case_types
// ignore_for_file: non_constant_identifier_names

import 'dart:ffi' as ffi;

/// FFI bindings for flutter_ocr_kit native library
class OcrKitBindings {
  final ffi.Pointer<T> Function<T extends ffi.NativeType>(String symbolName)
      _lookup;

  OcrKitBindings(ffi.DynamicLibrary dynamicLibrary)
      : _lookup = dynamicLibrary.lookup;

  // ========================
  // Layout Detection API
  // ========================

  /// Initialize layout model with path
  void initModel(ffi.Pointer<ffi.Char> modelPath) {
    return _initModel(modelPath);
  }

  late final _initModelPtr = _lookup<
      ffi.NativeFunction<ffi.Void Function(ffi.Pointer<ffi.Char>)>>('initModel');
  late final _initModel =
      _initModelPtr.asFunction<void Function(ffi.Pointer<ffi.Char>)>();

  /// Detect layout from image file path
  ffi.Pointer<ffi.Char> detectLayout(
      ffi.Pointer<ffi.Char> imgPath, double confThreshold) {
    return _detectLayout(imgPath, confThreshold);
  }

  late final _detectLayoutPtr = _lookup<
      ffi.NativeFunction<
          ffi.Pointer<ffi.Char> Function(
              ffi.Pointer<ffi.Char>, ffi.Float)>>('detectLayout');
  late final _detectLayout = _detectLayoutPtr
      .asFunction<ffi.Pointer<ffi.Char> Function(ffi.Pointer<ffi.Char>, double)>();

  /// Free allocated string memory
  void freeString(ffi.Pointer<ffi.Char> str) {
    return _freeString(str);
  }

  late final _freeStringPtr =
      _lookup<ffi.NativeFunction<ffi.Void Function(ffi.Pointer<ffi.Char>)>>(
          'freeString');
  late final _freeString =
      _freeStringPtr.asFunction<void Function(ffi.Pointer<ffi.Char>)>();

  /// Get library version
  ffi.Pointer<ffi.Char> getVersion() {
    return _getVersion();
  }

  late final _getVersionPtr =
      _lookup<ffi.NativeFunction<ffi.Pointer<ffi.Char> Function()>>(
          'getVersion');
  late final _getVersion =
      _getVersionPtr.asFunction<ffi.Pointer<ffi.Char> Function()>();

  // ========================
  // OCR API
  // ========================

  /// Initialize OCR models (detection + recognition + dictionary)
  void initOcrModels(
      ffi.Pointer<ffi.Char> detModelPath,
      ffi.Pointer<ffi.Char> recModelPath,
      ffi.Pointer<ffi.Char> dictPath) {
    return _initOcrModels(detModelPath, recModelPath, dictPath);
  }

  late final _initOcrModelsPtr = _lookup<
      ffi.NativeFunction<
          ffi.Void Function(ffi.Pointer<ffi.Char>, ffi.Pointer<ffi.Char>,
              ffi.Pointer<ffi.Char>)>>('initOcrModels');
  late final _initOcrModels = _initOcrModelsPtr.asFunction<
      void Function(
          ffi.Pointer<ffi.Char>, ffi.Pointer<ffi.Char>, ffi.Pointer<ffi.Char>)>();

  /// Release OCR engine resources
  void releaseOcrEngine() {
    return _releaseOcrEngine();
  }

  late final _releaseOcrEnginePtr =
      _lookup<ffi.NativeFunction<ffi.Void Function()>>('releaseOcrEngine');
  late final _releaseOcrEngine =
      _releaseOcrEnginePtr.asFunction<void Function()>();

  /// Recognize text from image file path (full OCR: detect + recognize)
  ffi.Pointer<ffi.Char> recognizeTextFromPath(
      ffi.Pointer<ffi.Char> imgPath, double detThreshold, double recThreshold) {
    return _recognizeTextFromPath(imgPath, detThreshold, recThreshold);
  }

  late final _recognizeTextFromPathPtr = _lookup<
      ffi.NativeFunction<
          ffi.Pointer<ffi.Char> Function(
              ffi.Pointer<ffi.Char>, ffi.Float, ffi.Float)>>('recognizeTextFromPath');
  late final _recognizeTextFromPath = _recognizeTextFromPathPtr.asFunction<
      ffi.Pointer<ffi.Char> Function(ffi.Pointer<ffi.Char>, double, double)>();

  /// Recognize text from image buffer (for camera frames)
  /// Buffer format: BGRA (iOS camera format)
  ffi.Pointer<ffi.Char> recognizeTextFromBuffer(
      ffi.Pointer<ffi.Uint8> buffer,
      int width,
      int height,
      int stride,
      double detThreshold,
      double recThreshold) {
    return _recognizeTextFromBuffer(
        buffer, width, height, stride, detThreshold, recThreshold);
  }

  late final _recognizeTextFromBufferPtr = _lookup<
      ffi.NativeFunction<
          ffi.Pointer<ffi.Char> Function(ffi.Pointer<ffi.Uint8>, ffi.Int32,
              ffi.Int32, ffi.Int32, ffi.Float, ffi.Float)>>('recognizeTextFromBuffer');
  late final _recognizeTextFromBuffer = _recognizeTextFromBufferPtr.asFunction<
      ffi.Pointer<ffi.Char> Function(
          ffi.Pointer<ffi.Uint8>, int, int, int, double, double)>();

  /// Detect text regions only (without recognition)
  ffi.Pointer<ffi.Char> detectTextFromPath(
      ffi.Pointer<ffi.Char> imgPath, double threshold) {
    return _detectTextFromPath(imgPath, threshold);
  }

  late final _detectTextFromPathPtr = _lookup<
      ffi.NativeFunction<
          ffi.Pointer<ffi.Char> Function(
              ffi.Pointer<ffi.Char>, ffi.Float)>>('detectTextFromPath');
  late final _detectTextFromPath = _detectTextFromPathPtr
      .asFunction<ffi.Pointer<ffi.Char> Function(ffi.Pointer<ffi.Char>, double)>();

  // ========================
  // Apple Vision OCR API
  // ========================

  /// Recognize text from image using Apple Vision Framework
  /// [imagePath] - Path to image file
  /// [languages] - Comma-separated language codes (e.g., "zh-Hant,zh-Hans,en-US")
  ffi.Pointer<ffi.Char> recognizeTextWithVision(
      ffi.Pointer<ffi.Char> imagePath, ffi.Pointer<ffi.Char> languages) {
    return _recognizeTextWithVision(imagePath, languages);
  }

  late final _recognizeTextWithVisionPtr = _lookup<
      ffi.NativeFunction<
          ffi.Pointer<ffi.Char> Function(
              ffi.Pointer<ffi.Char>, ffi.Pointer<ffi.Char>)>>('recognizeTextWithVision');
  late final _recognizeTextWithVision = _recognizeTextWithVisionPtr
      .asFunction<ffi.Pointer<ffi.Char> Function(ffi.Pointer<ffi.Char>, ffi.Pointer<ffi.Char>)>();

  /// Recognize text from a cropped region using Apple Vision
  /// Coordinates are in original image space
  ffi.Pointer<ffi.Char> recognizeRegionWithVision(
      ffi.Pointer<ffi.Char> imagePath,
      double cropX1, double cropY1,
      double cropX2, double cropY2,
      ffi.Pointer<ffi.Char> languages) {
    return _recognizeRegionWithVision(imagePath, cropX1, cropY1, cropX2, cropY2, languages);
  }

  late final _recognizeRegionWithVisionPtr = _lookup<
      ffi.NativeFunction<
          ffi.Pointer<ffi.Char> Function(
              ffi.Pointer<ffi.Char>,
              ffi.Float, ffi.Float, ffi.Float, ffi.Float,
              ffi.Pointer<ffi.Char>)>>('recognizeRegionWithVision');
  late final _recognizeRegionWithVision = _recognizeRegionWithVisionPtr
      .asFunction<ffi.Pointer<ffi.Char> Function(
          ffi.Pointer<ffi.Char>, double, double, double, double, ffi.Pointer<ffi.Char>)>();

  /// Get supported languages for Vision OCR
  ffi.Pointer<ffi.Char> getVisionSupportedLanguages() {
    return _getVisionSupportedLanguages();
  }

  late final _getVisionSupportedLanguagesPtr =
      _lookup<ffi.NativeFunction<ffi.Pointer<ffi.Char> Function()>>(
          'getVisionSupportedLanguages');
  late final _getVisionSupportedLanguages =
      _getVisionSupportedLanguagesPtr.asFunction<ffi.Pointer<ffi.Char> Function()>();
}

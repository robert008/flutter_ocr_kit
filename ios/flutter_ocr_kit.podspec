Pod::Spec.new do |s|
  s.name             = 'flutter_ocr_kit'
  s.version          = '0.0.1'
  s.summary          = 'OCR plugin for Flutter using ONNX model with Core ML acceleration'
  s.homepage         = 'https://github.com/example/flutter_ocr_kit'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Your Company' => 'email@example.com' }
  s.source           = { :path => '.' }

  s.source_files = 'Classes/**/*.{h,m}'

  # Static libraries: user code + ONNX Runtime (separate from OpenCV to avoid protobuf conflict)
  s.vendored_libraries = 'libflutter_ocr_kit.a', 'static_libs/libonnxruntime_complete.a'

  # Keep OpenCV as framework (has its own protobuf, must be separate)
  s.vendored_frameworks = 'Frameworks/opencv2.framework'

  s.ios.deployment_target = '12.0'
  s.static_framework = true

  # Header search paths for ONNX Runtime headers
  s.pod_target_xcconfig = {
    'OTHER_LDFLAGS' => '-force_load $(PODS_TARGET_SRCROOT)/libflutter_ocr_kit.a -force_load $(PODS_TARGET_SRCROOT)/static_libs/libonnxruntime_complete.a -lc++',
    'CLANG_CXX_LANGUAGE_STANDARD' => 'c++17',
    'DEFINES_MODULE' => 'YES',
    'GCC_SYMBOLS_PRIVATE_EXTERN' => 'NO',
    'HEADER_SEARCH_PATHS' => '$(PODS_TARGET_SRCROOT)/include'
  }

  # Core ML and Accelerate frameworks for hardware acceleration
  # CoreVideo and CoreMedia needed by OpenCV
  # Vision framework for Apple Vision OCR
  s.frameworks = 'CoreML', 'Accelerate', 'Foundation', 'CoreVideo', 'CoreMedia', 'AVFoundation', 'Vision'

  # Additional system libraries required
  s.libraries = 'z', 'c++'

  s.dependency 'Flutter'
end

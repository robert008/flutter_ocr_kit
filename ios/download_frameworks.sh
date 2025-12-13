#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERSION="v1.0.0"
BASE_URL="https://github.com/robert008/flutter_ocr_kit/releases/download/${VERSION}"

# Check if frameworks already exist
OPENCV_DIR="$SCRIPT_DIR/Frameworks/opencv2.framework"
ONNX_DIR="$SCRIPT_DIR/Frameworks/onnxruntime.xcframework"
STATIC_LIBS_DIR="$SCRIPT_DIR/static_libs"

download_file() {
    local url=$1
    local output=$2

    echo "Downloading: $url"
    if command -v curl &> /dev/null; then
        curl -L -o "$output" "$url"
    elif command -v wget &> /dev/null; then
        wget -O "$output" "$url"
    else
        echo "Error: curl or wget is required"
        exit 1
    fi
}

# Download and extract opencv2.framework
if [ ! -d "$OPENCV_DIR" ]; then
    echo "Downloading opencv2.framework..."
    OPENCV_ZIP="$SCRIPT_DIR/opencv2.framework.zip"
    download_file "${BASE_URL}/opencv2.framework.zip" "$OPENCV_ZIP"

    if [ -f "$OPENCV_ZIP" ]; then
        mkdir -p "$SCRIPT_DIR/Frameworks"
        unzip -q -o "$OPENCV_ZIP" -d "$SCRIPT_DIR/Frameworks/"
        rm -f "$OPENCV_ZIP"
        echo "opencv2.framework extracted successfully"
    fi
else
    echo "opencv2.framework already exists"
fi

# Download and extract onnxruntime.xcframework
if [ ! -d "$ONNX_DIR" ]; then
    echo "Downloading onnxruntime.xcframework..."
    ONNX_ZIP="$SCRIPT_DIR/onnxruntime.xcframework.zip"
    download_file "${BASE_URL}/onnxruntime.xcframework.zip" "$ONNX_ZIP"

    if [ -f "$ONNX_ZIP" ]; then
        mkdir -p "$SCRIPT_DIR/Frameworks"
        unzip -q -o "$ONNX_ZIP" -d "$SCRIPT_DIR/Frameworks/"
        rm -f "$ONNX_ZIP"
        echo "onnxruntime.xcframework extracted successfully"
    fi
else
    echo "onnxruntime.xcframework already exists"
fi

# Download and extract static_libs
STATIC_LIBS_MARKER="$STATIC_LIBS_DIR/libonnxruntime_complete.a"
if [ ! -f "$STATIC_LIBS_MARKER" ]; then
    echo "Downloading static_libs..."
    STATIC_ZIP="$SCRIPT_DIR/static_libs.zip"
    download_file "${BASE_URL}/static_libs.zip" "$STATIC_ZIP"

    if [ -f "$STATIC_ZIP" ]; then
        unzip -q -o "$STATIC_ZIP" -d "$SCRIPT_DIR/"
        rm -f "$STATIC_ZIP"
        echo "static_libs extracted successfully"
    fi
else
    echo "static_libs already exists"
fi

echo "All iOS dependencies ready!"

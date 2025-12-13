#!/bin/bash

# Download ONNX Runtime iOS xcframework with Core ML support

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FRAMEWORKS_DIR="$SCRIPT_DIR/Frameworks"
ORT_VERSION="1.16.3"

# ONNX Runtime iOS release with Core ML support
DOWNLOAD_URL="https://github.com/microsoft/onnxruntime/releases/download/v${ORT_VERSION}/onnxruntime-objc-${ORT_VERSION}.zip"

mkdir -p "$FRAMEWORKS_DIR"
cd "$FRAMEWORKS_DIR"

if [ -d "onnxruntime.xcframework" ]; then
    echo "ONNX Runtime xcframework already exists"
    exit 0
fi

echo "Downloading ONNX Runtime ${ORT_VERSION} for iOS..."
echo "URL: $DOWNLOAD_URL"

curl -L -o onnxruntime.zip "$DOWNLOAD_URL"

echo "Extracting..."
unzip -q onnxruntime.zip

# Find and move xcframework
XCFRAMEWORK=$(find . -name "onnxruntime.xcframework" -type d | head -1)
if [ -n "$XCFRAMEWORK" ] && [ "$XCFRAMEWORK" != "./onnxruntime.xcframework" ]; then
    mv "$XCFRAMEWORK" ./
fi

# Cleanup
rm -f onnxruntime.zip
find . -maxdepth 1 -type d -name "onnxruntime-objc-*" -exec rm -rf {} \; 2>/dev/null || true

echo ""
echo "Done! ONNX Runtime xcframework installed at:"
ls -la "$FRAMEWORKS_DIR/onnxruntime.xcframework"

## 1.0.0

* Initial release
* Native OCR using Apple Vision (iOS) and Google ML Kit (Android)
* Layout Detection using ONNX Runtime with PP-DocLayout model
* Real-time camera OCR support
* Key Information Extraction (KIE) for dates, phone numbers, amounts
* Invoice scanner demo (Taiwan e-invoice format)
* Quotation scanner demo with Layout Detection + OCR
* iOS: Core ML Execution Provider for faster inference
* Memory management: `OcrKit.releaseLayout()` to free resources

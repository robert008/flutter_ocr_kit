#ifndef OCR_ENGINE_H
#define OCR_ENGINE_H

#include "utils.h"
#include "config_manager.h"
#include <string>
#include <vector>

// OCR text line result structure
struct TextLineResult {
    float x1, y1, x2, y2;  // Bounding box coordinates (in original image space)
    float score;           // Confidence score
    std::string text;      // Recognized text content
};

// Text box from detection (4 corner points)
struct TextBox {
    std::vector<cv::Point2f> points;  // 4 corner points (clockwise from top-left)
    float score;
};

// OCR Engine class - manages detection and recognition models
class OcrEngine {
public:
    static OcrEngine& GetInstance();

    // Initialize with model paths and dictionary path
    void Init(const std::string& det_model_path,
              const std::string& rec_model_path,
              const std::string& dict_path);

    // Release resources
    void Release();

    // Full OCR pipeline: detect + recognize
    std::vector<TextLineResult> RecognizeText(const cv::Mat& image, float det_threshold = 0.3f, float rec_threshold = 0.5f);

    // Detection only - returns text boxes
    std::vector<TextBox> DetectText(const cv::Mat& image, float threshold = 0.3f);

    // Recognition only - for a single cropped text region
    std::pair<std::string, float> RecognizeRegion(const cv::Mat& region);

    bool IsInitialized() const { return initialized_; }

private:
    OcrEngine() = default;
    ~OcrEngine();
    OcrEngine(const OcrEngine&) = delete;
    OcrEngine& operator=(const OcrEngine&) = delete;

    // Session management
    Ort::Env* env_ = nullptr;
    Ort::SessionOptions* det_session_options_ = nullptr;
    Ort::SessionOptions* rec_session_options_ = nullptr;
    Ort::Session* det_session_ = nullptr;
    Ort::Session* rec_session_ = nullptr;

    // Character dictionary for CTC decoding
    std::vector<std::string> dictionary_;

    bool initialized_ = false;

    // Preprocessing
    cv::Mat PreprocessForDetection(const cv::Mat& image, float& scale_x, float& scale_y);
    cv::Mat PreprocessForRecognition(const cv::Mat& region);

    // Post-processing
    std::vector<TextBox> DBPostProcess(const float* output_data, int height, int width,
                                        float scale_x, float scale_y,
                                        int orig_width, int orig_height,
                                        float threshold = 0.3f, float box_threshold = 0.5f);
    std::pair<std::string, float> CTCDecode(const float* output_data, int seq_len, int vocab_size);

    // Utility
    cv::Mat CropTextRegion(const cv::Mat& image, const TextBox& box);
    void LoadDictionary(const std::string& dict_path);
};

// Legacy function for backward compatibility
std::vector<TextLineResult> recognizeText(const cv::Mat& image, float conf_threshold = 0.5);

// Get full text from all text lines
std::string getFullText(const std::vector<TextLineResult>& results);

// Convert results to JSON
std::string ocrResultsToJson(const std::vector<TextLineResult>& results);

#endif // OCR_ENGINE_H

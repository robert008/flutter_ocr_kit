#include "include/ocr_engine.h"
#include <sstream>
#include <iomanip>
#include <fstream>
#include <chrono>
#include <algorithm>
#include <cmath>
#include <numeric>

#ifdef __ANDROID__
#include <android/log.h>
#include "nnapi_provider_factory.h"
#define LOGD(...) __android_log_print(ANDROID_LOG_DEBUG, "OcrKit", __VA_ARGS__)
#elif defined(__APPLE__)
#include <os/log.h>
#include "coreml_provider_factory.h"
#define LOGD(...) os_log(OS_LOG_DEFAULT, __VA_ARGS__)
#else
#define LOGD(...) do {} while(0)
#endif

// Constants for PP-OCRv4
static const int DET_MAX_SIDE = 960;       // Max side length for detection
static const int DET_LIMIT_SIDE = 32;      // Must be divisible by 32
static const int REC_IMG_HEIGHT = 48;      // Fixed height for recognition
static const int REC_IMG_MAX_WIDTH = 2048; // Max width for recognition (to prevent memory issues)
static const float DET_MEAN[3] = {0.485f, 0.456f, 0.406f};
static const float DET_STD[3] = {0.229f, 0.224f, 0.225f};
static const float REC_MEAN[3] = {0.5f, 0.5f, 0.5f};
static const float REC_STD[3] = {0.5f, 0.5f, 0.5f};

OcrEngine& OcrEngine::GetInstance() {
    static OcrEngine instance;
    return instance;
}

OcrEngine::~OcrEngine() {
    Release();
}

void OcrEngine::Release() {
    if (det_session_) {
        delete det_session_;
        det_session_ = nullptr;
    }
    if (rec_session_) {
        delete rec_session_;
        rec_session_ = nullptr;
    }
    if (det_session_options_) {
        delete det_session_options_;
        det_session_options_ = nullptr;
    }
    if (rec_session_options_) {
        delete rec_session_options_;
        rec_session_options_ = nullptr;
    }
    if (env_) {
        delete env_;
        env_ = nullptr;
    }
    dictionary_.clear();
    initialized_ = false;
    LOGD("OCR Engine released");
}

void OcrEngine::LoadDictionary(const std::string& dict_path) {
    std::ifstream file(dict_path);
    if (!file.is_open()) {
        LOGD("Failed to open dictionary: %s", dict_path.c_str());
        return;
    }

    dictionary_.clear();
    // First entry is blank token for CTC
    dictionary_.push_back("");

    std::string line;
    int line_count = 0;
    while (std::getline(file, line)) {
        line_count++;
        // Remove trailing whitespace/newlines
        while (!line.empty() && (line.back() == '\r' || line.back() == '\n')) {
            line.pop_back();
        }
        // Keep even empty lines as valid entries (space character)
        if (line.empty()) {
            dictionary_.push_back(" ");
        } else {
            dictionary_.push_back(line);
        }
    }

    // Add space token at end if not already there
    if (dictionary_.empty() || dictionary_.back() != " ") {
        dictionary_.push_back(" ");
    }

    // Add end token to match model vocabulary size (6625)
    dictionary_.push_back("");  // End/padding token

    LOGD("Loaded dictionary: %d lines from file, %zu total entries", line_count, dictionary_.size());

    // Debug: print first 20 entries
    for (size_t i = 0; i < std::min(dictionary_.size(), size_t(20)); i++) {
        LOGD("Dict[%zu] = '%s'", i, dictionary_[i].c_str());
    }
}

void OcrEngine::Init(const std::string& det_model_path,
                     const std::string& rec_model_path,
                     const std::string& dict_path) {
    if (initialized_) {
        LOGD("OCR Engine already initialized");
        return;
    }

    LOGD("Initializing OCR Engine...");

    // Load dictionary
    LoadDictionary(dict_path);

    // Create environment
    env_ = new Ort::Env(ORT_LOGGING_LEVEL_WARNING, "OcrEngine");

    // Create session options for detection model
    det_session_options_ = new Ort::SessionOptions();
    det_session_options_->SetGraphOptimizationLevel(GraphOptimizationLevel::ORT_ENABLE_ALL);
    det_session_options_->SetIntraOpNumThreads(4);
    det_session_options_->SetInterOpNumThreads(2);

    // Create session options for recognition model
    rec_session_options_ = new Ort::SessionOptions();
    rec_session_options_->SetGraphOptimizationLevel(GraphOptimizationLevel::ORT_ENABLE_ALL);
    rec_session_options_->SetIntraOpNumThreads(4);
    rec_session_options_->SetInterOpNumThreads(2);

    // Enable hardware acceleration
#ifdef __ANDROID__
    LOGD("Enabling NNAPI for OCR models...");
    uint32_t nnapi_flags = NNAPI_FLAG_USE_NONE;

    OrtStatus* det_status = OrtSessionOptionsAppendExecutionProvider_Nnapi(*det_session_options_, nnapi_flags);
    if (det_status != nullptr) {
        LOGD("NNAPI failed for det: %s", Ort::GetApi().GetErrorMessage(det_status));
        Ort::GetApi().ReleaseStatus(det_status);
    }

    OrtStatus* rec_status = OrtSessionOptionsAppendExecutionProvider_Nnapi(*rec_session_options_, nnapi_flags);
    if (rec_status != nullptr) {
        LOGD("NNAPI failed for rec: %s", Ort::GetApi().GetErrorMessage(rec_status));
        Ort::GetApi().ReleaseStatus(rec_status);
    }
#elif defined(__APPLE__)
    LOGD("Enabling Core ML for OCR models...");
    uint32_t coreml_flags = 0;  // Use Neural Engine when available

    OrtStatus* det_status = OrtSessionOptionsAppendExecutionProvider_CoreML(*det_session_options_, coreml_flags);
    if (det_status != nullptr) {
        LOGD("Core ML failed for det: %s", Ort::GetApi().GetErrorMessage(det_status));
        Ort::GetApi().ReleaseStatus(det_status);
    } else {
        LOGD("Core ML enabled for detection model");
    }

    OrtStatus* rec_status = OrtSessionOptionsAppendExecutionProvider_CoreML(*rec_session_options_, coreml_flags);
    if (rec_status != nullptr) {
        LOGD("Core ML failed for rec: %s", Ort::GetApi().GetErrorMessage(rec_status));
        Ort::GetApi().ReleaseStatus(rec_status);
    } else {
        LOGD("Core ML enabled for recognition model");
    }
#endif

    // Load detection model
    LOGD("Loading detection model: %s", det_model_path.c_str());
    det_session_ = new Ort::Session(*env_, det_model_path.c_str(), *det_session_options_);

    // Load recognition model
    LOGD("Loading recognition model: %s", rec_model_path.c_str());
    rec_session_ = new Ort::Session(*env_, rec_model_path.c_str(), *rec_session_options_);

    initialized_ = true;
    LOGD("OCR Engine initialized successfully");
}

cv::Mat OcrEngine::PreprocessForDetection(const cv::Mat& image, float& scale_x, float& scale_y) {
    int orig_h = image.rows;
    int orig_w = image.cols;

    // Calculate resize ratio (keep aspect ratio, max side = DET_MAX_SIDE)
    float ratio = 1.0f;
    int max_side = std::max(orig_h, orig_w);
    if (max_side > DET_MAX_SIDE) {
        ratio = static_cast<float>(DET_MAX_SIDE) / max_side;
    }

    int new_h = static_cast<int>(orig_h * ratio);
    int new_w = static_cast<int>(orig_w * ratio);

    // Round to multiple of 32
    new_h = ((new_h + DET_LIMIT_SIDE - 1) / DET_LIMIT_SIDE) * DET_LIMIT_SIDE;
    new_w = ((new_w + DET_LIMIT_SIDE - 1) / DET_LIMIT_SIDE) * DET_LIMIT_SIDE;

    scale_x = static_cast<float>(new_w) / orig_w;
    scale_y = static_cast<float>(new_h) / orig_h;

    // Resize image
    cv::Mat resized;
    cv::resize(image, resized, cv::Size(new_w, new_h), 0, 0, cv::INTER_LINEAR);

    // Convert to RGB
    cv::Mat rgb;
    cv::cvtColor(resized, rgb, cv::COLOR_BGR2RGB);

    // Normalize: (x / 255 - mean) / std
    cv::Mat normalized;
    rgb.convertTo(normalized, CV_32F, 1.0 / 255.0);

    std::vector<cv::Mat> channels(3);
    cv::split(normalized, channels);

    for (int c = 0; c < 3; c++) {
        channels[c] = (channels[c] - DET_MEAN[c]) / DET_STD[c];
    }

    cv::merge(channels, normalized);

    // Convert to NCHW format
    cv::Mat blob;
    cv::dnn::blobFromImage(normalized, blob, 1.0, cv::Size(), cv::Scalar(), false, false, CV_32F);

    return blob;
}

cv::Mat OcrEngine::PreprocessForRecognition(const cv::Mat& region) {
    int src_h = region.rows;
    int src_w = region.cols;

    // Calculate resize ratio (fixed height = 48)
    float ratio = static_cast<float>(REC_IMG_HEIGHT) / src_h;
    int new_w = static_cast<int>(src_w * ratio);

    // Only limit width if it exceeds max (to prevent memory issues)
    if (new_w > REC_IMG_MAX_WIDTH) {
        LOGD("Recognition: width clamped from %d to %d (%.1f%% compression)",
             new_w, REC_IMG_MAX_WIDTH, (1.0f - (float)REC_IMG_MAX_WIDTH / new_w) * 100.0f);
        new_w = REC_IMG_MAX_WIDTH;
    }
    if (new_w < 1) {
        new_w = 1;
    }

    LOGD("Recognition preprocess: %dx%d -> %dx%d (dynamic width)", src_w, src_h, new_w, REC_IMG_HEIGHT);

    // Resize
    cv::Mat resized;
    cv::resize(region, resized, cv::Size(new_w, REC_IMG_HEIGHT), 0, 0, cv::INTER_LINEAR);

    // PP-OCR recognition expects BGR format (no RGB conversion needed)
    // Normalize: (x / 255 - 0.5) / 0.5 = x / 127.5 - 1
    cv::Mat normalized;
    resized.convertTo(normalized, CV_32F, 1.0 / 127.5, -1.0);

    // No padding needed - model accepts dynamic width
    // Convert to NCHW format
    cv::Mat blob;
    cv::dnn::blobFromImage(normalized, blob, 1.0, cv::Size(), cv::Scalar(), false, false, CV_32F);

    return blob;
}

std::vector<TextBox> OcrEngine::DBPostProcess(const float* output_data, int height, int width,
                                               float scale_x, float scale_y,
                                               int orig_width, int orig_height,
                                               float threshold, float box_threshold) {
    std::vector<TextBox> boxes;

    // Create probability map
    cv::Mat prob_map(height, width, CV_32F, const_cast<float*>(output_data));

    // Debug: check value range
    double min_val, max_val;
    cv::minMaxLoc(prob_map, &min_val, &max_val);
    LOGD("Detection output range: min=%.4f, max=%.4f", min_val, max_val);

    // Apply sigmoid if output looks like logits (values outside 0-1 range)
    if (min_val < -0.1 || max_val > 1.1) {
        LOGD("Applying sigmoid activation (detected logits output)");
        cv::exp(-prob_map, prob_map);
        prob_map = 1.0 / (1.0 + prob_map);

        cv::minMaxLoc(prob_map, &min_val, &max_val);
        LOGD("After sigmoid: min=%.4f, max=%.4f", min_val, max_val);
    }

    // Threshold to binary
    cv::Mat binary;
    cv::threshold(prob_map, binary, threshold, 1.0, cv::THRESH_BINARY);
    binary.convertTo(binary, CV_8UC1, 255);

    // Debug: count non-zero pixels
    int non_zero = cv::countNonZero(binary);
    LOGD("Binary map: %d non-zero pixels (threshold=%.3f)", non_zero, threshold);

    // Find contours
    std::vector<std::vector<cv::Point>> contours;
    std::vector<cv::Vec4i> hierarchy;
    cv::findContours(binary, contours, hierarchy, cv::RETR_LIST, cv::CHAIN_APPROX_SIMPLE);

    LOGD("Found %zu contours", contours.size());

    int skipped_small = 0, skipped_score = 0, skipped_size = 0;

    for (const auto& contour : contours) {
        if (contour.size() < 4) {
            skipped_small++;
            continue;
        }

        // Get minimum area rectangle
        cv::RotatedRect rect = cv::minAreaRect(contour);
        cv::Point2f vertices[4];
        rect.points(vertices);

        // Calculate average score within the contour
        cv::Mat mask = cv::Mat::zeros(height, width, CV_8UC1);
        std::vector<std::vector<cv::Point>> temp_contours = {contour};
        cv::drawContours(mask, temp_contours, 0, cv::Scalar(255), cv::FILLED);

        float mean_score = cv::mean(prob_map, mask)[0];

        if (mean_score < box_threshold) {
            skipped_score++;
            continue;
        }

        // Filter small boxes
        float box_width = rect.size.width;
        float box_height = rect.size.height;
        if (std::min(box_width, box_height) < 3) {
            skipped_size++;
            continue;
        }

        // Expand the box slightly
        float expand_ratio = 1.5f;
        float expand_w = (expand_ratio - 1.0f) * box_width / 2.0f;
        float expand_h = (expand_ratio - 1.0f) * box_height / 2.0f;

        // Get the 4 corners and expand
        TextBox box;
        box.score = mean_score;

        for (int i = 0; i < 4; i++) {
            // Scale back to original image coordinates
            float x = vertices[i].x / scale_x;
            float y = vertices[i].y / scale_y;

            // Clamp to image bounds
            x = std::max(0.0f, std::min(x, static_cast<float>(orig_width)));
            y = std::max(0.0f, std::min(y, static_cast<float>(orig_height)));

            box.points.push_back(cv::Point2f(x, y));
        }

        // Sort points: top-left, top-right, bottom-right, bottom-left
        std::sort(box.points.begin(), box.points.end(), [](const cv::Point2f& a, const cv::Point2f& b) {
            return a.y < b.y;
        });

        // Top two points
        if (box.points[0].x > box.points[1].x) {
            std::swap(box.points[0], box.points[1]);
        }
        // Bottom two points
        if (box.points[2].x < box.points[3].x) {
            std::swap(box.points[2], box.points[3]);
        }

        boxes.push_back(box);
    }

    // Sort boxes by y coordinate (top to bottom, left to right)
    std::sort(boxes.begin(), boxes.end(), [](const TextBox& a, const TextBox& b) {
        float a_y = (a.points[0].y + a.points[1].y) / 2;
        float b_y = (b.points[0].y + b.points[1].y) / 2;
        if (std::abs(a_y - b_y) > 10) {
            return a_y < b_y;
        }
        return a.points[0].x < b.points[0].x;
    });

    LOGD("DBPostProcess: %zu boxes (skipped: %d small contour, %d low score, %d small size)",
         boxes.size(), skipped_small, skipped_score, skipped_size);

    return boxes;
}

std::pair<std::string, float> OcrEngine::CTCDecode(const float* output_data, int seq_len, int vocab_size) {
    std::string result;
    float total_score = 0.0f;
    int char_count = 0;
    int prev_idx = -1;
    int blank_count = 0;
    std::string indices_str;  // For debug: track which indices were decoded

    // Debug: check first few values to understand data format
    float first_min = output_data[0], first_max = output_data[0];
    float first_sum = 0.0f;
    for (int i = 0; i < vocab_size; i++) {
        first_min = std::min(first_min, output_data[i]);
        first_max = std::max(first_max, output_data[i]);
        first_sum += output_data[i];
    }
    LOGD("CTCDecode: seq_len=%d, vocab_size=%d, first timestep range=[%.4f, %.4f], sum=%.4f",
         seq_len, vocab_size, first_min, first_max, first_sum);

    // Check if we need to apply softmax (output looks like logits, not probabilities)
    // If values are negative or sum is not ~1.0, it's likely logits
    bool need_softmax = (first_min < -0.001f || std::abs(first_sum - 1.0f) > 0.1f);
    if (need_softmax) {
        LOGD("Applying softmax to recognition output (detected logits: min=%.4f, sum=%.4f)", first_min, first_sum);
    } else {
        LOGD("Output appears to be probabilities (sum=%.4f), skipping softmax", first_sum);
    }

    for (int t = 0; t < seq_len; t++) {
        const float* timestep_data = output_data + t * vocab_size;

        // Apply softmax if needed
        std::vector<float> probs(vocab_size);
        if (need_softmax) {
            // Find max for numerical stability
            float max_logit = timestep_data[0];
            for (int v = 1; v < vocab_size; v++) {
                max_logit = std::max(max_logit, timestep_data[v]);
            }

            // Compute exp and sum
            float sum_exp = 0.0f;
            for (int v = 0; v < vocab_size; v++) {
                probs[v] = std::exp(timestep_data[v] - max_logit);
                sum_exp += probs[v];
            }

            // Normalize
            for (int v = 0; v < vocab_size; v++) {
                probs[v] /= sum_exp;
            }
        } else {
            for (int v = 0; v < vocab_size; v++) {
                probs[v] = timestep_data[v];
            }
        }

        // Find argmax
        int max_idx = 0;
        float max_val = probs[0];
        for (int v = 1; v < vocab_size; v++) {
            if (probs[v] > max_val) {
                max_val = probs[v];
                max_idx = v;
            }
        }

        // Skip blank (index 0) and repeated characters
        if (max_idx == 0) {
            blank_count++;
        } else if (max_idx != prev_idx) {
            if (max_idx < static_cast<int>(dictionary_.size())) {
                result += dictionary_[max_idx];
                total_score += max_val;
                char_count++;
                // Track decoded indices for first few characters
                if (char_count <= 10) {
                    indices_str += std::to_string(max_idx) + "(" + dictionary_[max_idx] + ") ";
                }
            } else {
                LOGD("WARNING: max_idx %d out of range (dict size=%zu)", max_idx, dictionary_.size());
            }
        }
        prev_idx = max_idx;
    }

    float avg_score = (char_count > 0) ? (total_score / char_count) : 0.0f;

    LOGD("CTCDecode result: '%s', %d chars, %d blanks, avg_score=%.4f",
         result.c_str(), char_count, blank_count, avg_score);
    LOGD("Decoded indices (first 10): %s", indices_str.c_str());
    LOGD("Dictionary size: %zu", dictionary_.size());

    return {result, avg_score};
}

cv::Mat OcrEngine::CropTextRegion(const cv::Mat& image, const TextBox& box) {
    if (box.points.size() != 4) {
        return cv::Mat();
    }

    // Get bounding rectangle
    float min_x = box.points[0].x, max_x = box.points[0].x;
    float min_y = box.points[0].y, max_y = box.points[0].y;

    for (const auto& pt : box.points) {
        min_x = std::min(min_x, pt.x);
        max_x = std::max(max_x, pt.x);
        min_y = std::min(min_y, pt.y);
        max_y = std::max(max_y, pt.y);
    }

    int x1 = static_cast<int>(std::max(0.0f, min_x));
    int y1 = static_cast<int>(std::max(0.0f, min_y));
    int x2 = static_cast<int>(std::min(static_cast<float>(image.cols), max_x));
    int y2 = static_cast<int>(std::min(static_cast<float>(image.rows), max_y));

    if (x2 <= x1 || y2 <= y1) {
        return cv::Mat();
    }

    // Calculate width and height of rotated rect
    float width = std::sqrt(std::pow(box.points[1].x - box.points[0].x, 2) +
                           std::pow(box.points[1].y - box.points[0].y, 2));
    float height = std::sqrt(std::pow(box.points[3].x - box.points[0].x, 2) +
                            std::pow(box.points[3].y - box.points[0].y, 2));

    // Ensure minimum dimensions
    if (width < 1) width = 1;
    if (height < 1) height = 1;

    // Source points (box corners)
    cv::Point2f src_pts[4] = {
        box.points[0], box.points[1], box.points[2], box.points[3]
    };

    // Destination points (upright rectangle)
    cv::Point2f dst_pts[4] = {
        cv::Point2f(0, 0),
        cv::Point2f(width, 0),
        cv::Point2f(width, height),
        cv::Point2f(0, height)
    };

    // Perspective transform
    cv::Mat transform = cv::getPerspectiveTransform(src_pts, dst_pts);
    cv::Mat cropped;
    cv::warpPerspective(image, cropped, transform, cv::Size(static_cast<int>(width), static_cast<int>(height)));

    // If height > width (text is vertically oriented), rotate 90 degrees clockwise
    // This is important because PP-OCR recognition expects horizontal text
    if (cropped.rows > cropped.cols * 1.5) {
        LOGD("Rotating vertical text region: %dx%d -> rotating 90 degrees", cropped.cols, cropped.rows);
        cv::rotate(cropped, cropped, cv::ROTATE_90_CLOCKWISE);
    }

    return cropped;
}

std::vector<TextBox> OcrEngine::DetectText(const cv::Mat& image, float threshold) {
    std::vector<TextBox> boxes;

    if (!initialized_ || !det_session_) {
        LOGD("Detection model not initialized");
        return boxes;
    }

    if (image.empty()) {
        LOGD("Empty image for detection");
        return boxes;
    }

    try {
        auto start = std::chrono::high_resolution_clock::now();

        // Preprocess
        float scale_x, scale_y;
        cv::Mat blob = PreprocessForDetection(image, scale_x, scale_y);

        int batch = blob.size[0];
        int channels = blob.size[1];
        int height = blob.size[2];
        int width = blob.size[3];

        LOGD("Detection input: %dx%d (scale: %.3f, %.3f)", width, height, scale_x, scale_y);

        // Prepare input tensor
        std::vector<int64_t> input_shape = {batch, channels, height, width};
        Ort::MemoryInfo memory_info = Ort::MemoryInfo::CreateCpu(OrtArenaAllocator, OrtMemTypeDefault);

        Ort::Value input_tensor = Ort::Value::CreateTensor<float>(
            memory_info, blob.ptr<float>(), blob.total(),
            input_shape.data(), input_shape.size());

        // Run inference
        Ort::AllocatorWithDefaultOptions allocator;
        auto input_name = det_session_->GetInputNameAllocated(0, allocator);
        auto output_name = det_session_->GetOutputNameAllocated(0, allocator);

        const char* input_names[] = {input_name.get()};
        const char* output_names[] = {output_name.get()};

        auto outputs = det_session_->Run(
            Ort::RunOptions{nullptr},
            input_names, &input_tensor, 1,
            output_names, 1);

        auto end = std::chrono::high_resolution_clock::now();
        auto duration = std::chrono::duration_cast<std::chrono::milliseconds>(end - start).count();
        LOGD("Detection inference: %lld ms", duration);

        // Get output
        auto output_shape = outputs[0].GetTensorTypeAndShapeInfo().GetShape();
        int out_h = static_cast<int>(output_shape[2]);
        int out_w = static_cast<int>(output_shape[3]);

        float* output_data = outputs[0].GetTensorMutableData<float>();

        // Post-process (lower box_threshold to 0.3 for better detection)
        boxes = DBPostProcess(output_data, out_h, out_w,
                             scale_x, scale_y,
                             image.cols, image.rows,
                             threshold, 0.3f);

        LOGD("Detected %zu text boxes", boxes.size());

    } catch (const Ort::Exception& e) {
        LOGD("Detection ONNX error: %s", e.what());
    } catch (const std::exception& e) {
        LOGD("Detection error: %s", e.what());
    }

    return boxes;
}

std::pair<std::string, float> OcrEngine::RecognizeRegion(const cv::Mat& region) {
    if (!initialized_ || !rec_session_) {
        LOGD("Recognition model not initialized");
        return {"", 0.0f};
    }

    if (region.empty()) {
        return {"", 0.0f};
    }

    try {
        // Preprocess with dynamic width (no chunking needed)
        cv::Mat blob = PreprocessForRecognition(region);

        int batch = blob.size[0];
        int channels = blob.size[1];
        int height = blob.size[2];
        int width = blob.size[3];

        LOGD("Recognition input tensor: [%d, %d, %d, %d]", batch, channels, height, width);

        // Prepare input tensor
        std::vector<int64_t> input_shape = {batch, channels, height, width};
        Ort::MemoryInfo memory_info = Ort::MemoryInfo::CreateCpu(OrtArenaAllocator, OrtMemTypeDefault);

        Ort::Value input_tensor = Ort::Value::CreateTensor<float>(
            memory_info, blob.ptr<float>(), blob.total(),
            input_shape.data(), input_shape.size());

        // Run inference
        Ort::AllocatorWithDefaultOptions allocator;
        auto input_name = rec_session_->GetInputNameAllocated(0, allocator);
        auto output_name = rec_session_->GetOutputNameAllocated(0, allocator);

        const char* input_names[] = {input_name.get()};
        const char* output_names[] = {output_name.get()};

        auto outputs = rec_session_->Run(
            Ort::RunOptions{nullptr},
            input_names, &input_tensor, 1,
            output_names, 1);

        // Get output
        auto output_shape = outputs[0].GetTensorTypeAndShapeInfo().GetShape();

        // PP-OCRv4 output is [batch, seq_len, vocab_size]
        int seq_len = static_cast<int>(output_shape[1]);
        int vocab_size = static_cast<int>(output_shape[2]);

        LOGD("Recognition output shape: [1, %d, %d]", seq_len, vocab_size);

        float* output_data = outputs[0].GetTensorMutableData<float>();

        // CTC decode
        return CTCDecode(output_data, seq_len, vocab_size);

    } catch (const Ort::Exception& e) {
        LOGD("Recognition ONNX error: %s", e.what());
    } catch (const std::exception& e) {
        LOGD("Recognition error: %s", e.what());
    }

    return {"", 0.0f};
}

std::vector<TextLineResult> OcrEngine::RecognizeText(const cv::Mat& image, float det_threshold, float rec_threshold) {
    std::vector<TextLineResult> results;

    if (!initialized_) {
        LOGD("OCR Engine not initialized");
        return results;
    }

    if (image.empty()) {
        LOGD("Empty image for OCR");
        return results;
    }

    auto total_start = std::chrono::high_resolution_clock::now();

    // Step 1: Detect text boxes
    std::vector<TextBox> boxes = DetectText(image, det_threshold);

    if (boxes.empty()) {
        LOGD("No text detected");
        return results;
    }

    auto rec_start = std::chrono::high_resolution_clock::now();

    // Step 2: Recognize each text box
    int box_idx = 0;
    int skipped_empty_region = 0, skipped_low_score = 0, skipped_empty_text = 0;

    for (const auto& box : boxes) {
        // Crop text region
        cv::Mat region = CropTextRegion(image, box);
        if (region.empty()) {
            skipped_empty_region++;
            box_idx++;
            continue;
        }

        // Recognize
        auto [text, score] = RecognizeRegion(region);

        LOGD("Box %d: region %dx%d, text='%s', score=%.4f",
             box_idx, region.cols, region.rows,
             text.substr(0, 20).c_str(), score);

        if (text.empty()) {
            skipped_empty_text++;
            box_idx++;
            continue;
        }

        if (score < rec_threshold) {
            skipped_low_score++;
            box_idx++;
            continue;
        }

        if (true) {  // Accepted
            TextLineResult result;

            // Get bounding box (axis-aligned)
            float min_x = box.points[0].x, max_x = box.points[0].x;
            float min_y = box.points[0].y, max_y = box.points[0].y;
            for (const auto& pt : box.points) {
                min_x = std::min(min_x, pt.x);
                max_x = std::max(max_x, pt.x);
                min_y = std::min(min_y, pt.y);
                max_y = std::max(max_y, pt.y);
            }

            result.x1 = min_x;
            result.y1 = min_y;
            result.x2 = max_x;
            result.y2 = max_y;
            result.score = score;
            result.text = text;

            results.push_back(result);
        }
        box_idx++;
    }

    auto total_end = std::chrono::high_resolution_clock::now();
    auto rec_duration = std::chrono::duration_cast<std::chrono::milliseconds>(total_end - rec_start).count();
    auto total_duration = std::chrono::duration_cast<std::chrono::milliseconds>(total_end - total_start).count();

    LOGD("Recognition summary: %d boxes, skipped: %d empty region, %d empty text, %d low score (threshold=%.2f)",
         box_idx, skipped_empty_region, skipped_empty_text, skipped_low_score, rec_threshold);
    LOGD("Recognition: %lld ms, Total OCR: %lld ms, Results: %zu", rec_duration, total_duration, results.size());

    return results;
}

// Legacy function for backward compatibility
std::vector<TextLineResult> recognizeText(const cv::Mat& image, float conf_threshold) {
    return OcrEngine::GetInstance().RecognizeText(image, 0.3f, conf_threshold);
}

std::string getFullText(const std::vector<TextLineResult>& results) {
    std::ostringstream text;
    for (size_t i = 0; i < results.size(); i++) {
        text << results[i].text;
        if (i < results.size() - 1) {
            text << "\n";
        }
    }
    return text.str();
}

std::string ocrResultsToJson(const std::vector<TextLineResult>& results) {
    std::ostringstream json;
    json << "{\"results\":[";

    for (size_t i = 0; i < results.size(); i++) {
        const auto& r = results[i];
        json << "{";
        json << "\"x1\":" << std::fixed << std::setprecision(2) << r.x1 << ",";
        json << "\"y1\":" << r.y1 << ",";
        json << "\"x2\":" << r.x2 << ",";
        json << "\"y2\":" << r.y2 << ",";
        json << "\"score\":" << std::setprecision(4) << r.score << ",";
        json << "\"text\":\"";

        // Escape special characters in text
        for (char c : r.text) {
            switch (c) {
                case '"': json << "\\\""; break;
                case '\\': json << "\\\\"; break;
                case '\n': json << "\\n"; break;
                case '\r': json << "\\r"; break;
                case '\t': json << "\\t"; break;
                default: json << c;
            }
        }
        json << "\"}";

        if (i < results.size() - 1) {
            json << ",";
        }
    }

    json << "],\"count\":" << results.size() << "}";
    return json.str();
}

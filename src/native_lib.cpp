#include <opencv2/opencv.hpp>
#include <onnxruntime_cxx_api.h>
#include <cstring>
#include <vector>
#include <iostream>
#include <string>
#include <future>
#include <chrono>

#include "detect/include/config_manager.h"
#include "detect/include/doc_detector.h"
#include "ocr/include/ocr_engine.h"

#ifdef __ANDROID__
#include <android/log.h>
#endif

#define LOGI(...) do {} while(0)
#define LOGE(...) do {} while(0)

using namespace std::chrono;

// Initialize model path
extern "C" __attribute__((visibility("default")))
void initModel(const char* model_path) {
    ConfigManager::GetInstance().Init(std::string(model_path));
    LOGI("Model initialized: %s\n", model_path);
}

// Release layout model resources
extern "C" __attribute__((visibility("default")))
void releaseLayoutModel() {
    releaseLayoutSession();
    LOGI("Layout model released\n");
}

// Detect layout from image path
extern "C" __attribute__((visibility("default")))
char* detectLayout(const char* img_path, float conf_threshold) {
    return strdup(std::async(std::launch::async, [img_path, conf_threshold]() -> std::string {
        auto start = high_resolution_clock::now();

        cv::Mat image = cv::imread(img_path);
        if (image.empty()) {
            return "{\"error\":\"Could not load image\",\"code\":\"IMAGE_LOAD_FAILED\"}";
        }

        std::vector<DetectionBox> results = detectDocLayout(image, conf_threshold);

        auto end = high_resolution_clock::now();
        long long inference_time = duration_cast<milliseconds>(end - start).count();

        std::ostringstream json;
        json << "{\"detections\":[";

        for (size_t i = 0; i < results.size(); i++) {
            const auto& box = results[i];
            json << "{";
            json << "\"x1\":" << std::fixed << std::setprecision(2) << box.x1 << ",";
            json << "\"y1\":" << box.y1 << ",";
            json << "\"x2\":" << box.x2 << ",";
            json << "\"y2\":" << box.y2 << ",";
            json << "\"score\":" << std::setprecision(4) << box.score << ",";
            json << "\"class_id\":" << box.class_id << ",";
            json << "\"class_name\":\"" << box.class_name << "\"";
            json << "}";
            if (i < results.size() - 1) {
                json << ",";
            }
        }

        json << "],";
        json << "\"count\":" << results.size() << ",";
        json << "\"inference_time_ms\":" << inference_time << ",";
        json << "\"image_width\":" << image.cols << ",";
        json << "\"image_height\":" << image.rows;
        json << "}";

        return json.str();
    }).get().c_str());
}

// Free allocated string memory
extern "C" __attribute__((visibility("default")))
void freeString(char* str) {
    if (str) {
        free(str);
    }
}

// Get version info
extern "C" __attribute__((visibility("default")))
const char* getVersion() {
    return "1.0.0-xnnpack";
}

// ========================
// OCR Functions
// ========================

// Initialize OCR models
extern "C" __attribute__((visibility("default")))
void initOcrModels(const char* det_model_path, const char* rec_model_path, const char* dict_path) {
    OcrEngine::GetInstance().Init(
        std::string(det_model_path),
        std::string(rec_model_path),
        std::string(dict_path)
    );
    LOGI("OCR models initialized\n");
}

// Release OCR engine resources
extern "C" __attribute__((visibility("default")))
void releaseOcrEngine() {
    OcrEngine::GetInstance().Release();
    LOGI("OCR engine released\n");
}

// Recognize text from image path (full OCR: detect + recognize)
extern "C" __attribute__((visibility("default")))
char* recognizeTextFromPath(const char* img_path, float det_threshold, float rec_threshold) {
    return strdup(std::async(std::launch::async, [img_path, det_threshold, rec_threshold]() -> std::string {
        auto start = high_resolution_clock::now();

        cv::Mat image = cv::imread(img_path);
        if (image.empty()) {
            return "{\"error\":\"Could not load image\",\"code\":\"IMAGE_LOAD_FAILED\"}";
        }

        if (!OcrEngine::GetInstance().IsInitialized()) {
            return "{\"error\":\"OCR engine not initialized\",\"code\":\"ENGINE_NOT_INITIALIZED\"}";
        }

        std::vector<TextLineResult> results = OcrEngine::GetInstance().RecognizeText(
            image, det_threshold, rec_threshold);

        auto end = high_resolution_clock::now();
        long long inference_time = duration_cast<milliseconds>(end - start).count();

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

        json << "],";
        json << "\"count\":" << results.size() << ",";
        json << "\"inference_time_ms\":" << inference_time << ",";
        json << "\"image_width\":" << image.cols << ",";
        json << "\"image_height\":" << image.rows;
        json << "}";

        return json.str();
    }).get().c_str());
}

// Recognize text from image buffer (for camera frames)
extern "C" __attribute__((visibility("default")))
char* recognizeTextFromBuffer(const uint8_t* buffer, int width, int height, int stride,
                               float det_threshold, float rec_threshold) {
    return strdup(std::async(std::launch::async, [buffer, width, height, stride, det_threshold, rec_threshold]() -> std::string {
        auto start = high_resolution_clock::now();

        // Create cv::Mat from buffer (assuming BGRA format from iOS camera)
        cv::Mat bgra(height, width, CV_8UC4, const_cast<uint8_t*>(buffer), stride);
        cv::Mat image;
        cv::cvtColor(bgra, image, cv::COLOR_BGRA2BGR);

        if (image.empty()) {
            return "{\"error\":\"Invalid image buffer\",\"code\":\"BUFFER_INVALID\"}";
        }

        if (!OcrEngine::GetInstance().IsInitialized()) {
            return "{\"error\":\"OCR engine not initialized\",\"code\":\"ENGINE_NOT_INITIALIZED\"}";
        }

        std::vector<TextLineResult> results = OcrEngine::GetInstance().RecognizeText(
            image, det_threshold, rec_threshold);

        auto end = high_resolution_clock::now();
        long long inference_time = duration_cast<milliseconds>(end - start).count();

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

        json << "],";
        json << "\"count\":" << results.size() << ",";
        json << "\"inference_time_ms\":" << inference_time << ",";
        json << "\"image_width\":" << width << ",";
        json << "\"image_height\":" << height;
        json << "}";

        return json.str();
    }).get().c_str());
}

// Detect text regions only (without recognition)
extern "C" __attribute__((visibility("default")))
char* detectTextFromPath(const char* img_path, float threshold) {
    return strdup(std::async(std::launch::async, [img_path, threshold]() -> std::string {
        auto start = high_resolution_clock::now();

        cv::Mat image = cv::imread(img_path);
        if (image.empty()) {
            return "{\"error\":\"Could not load image\",\"code\":\"IMAGE_LOAD_FAILED\"}";
        }

        if (!OcrEngine::GetInstance().IsInitialized()) {
            return "{\"error\":\"OCR engine not initialized\",\"code\":\"ENGINE_NOT_INITIALIZED\"}";
        }

        std::vector<TextBox> boxes = OcrEngine::GetInstance().DetectText(image, threshold);

        auto end = high_resolution_clock::now();
        long long inference_time = duration_cast<milliseconds>(end - start).count();

        std::ostringstream json;
        json << "{\"boxes\":[";

        for (size_t i = 0; i < boxes.size(); i++) {
            const auto& box = boxes[i];
            json << "{\"points\":[";
            for (size_t j = 0; j < box.points.size(); j++) {
                json << "[" << std::fixed << std::setprecision(2) << box.points[j].x << ","
                     << box.points[j].y << "]";
                if (j < box.points.size() - 1) json << ",";
            }
            json << "],\"score\":" << std::setprecision(4) << box.score << "}";
            if (i < boxes.size() - 1) json << ",";
        }

        json << "],";
        json << "\"count\":" << boxes.size() << ",";
        json << "\"inference_time_ms\":" << inference_time << ",";
        json << "\"image_width\":" << image.cols << ",";
        json << "\"image_height\":" << image.rows;
        json << "}";

        return json.str();
    }).get().c_str());
}

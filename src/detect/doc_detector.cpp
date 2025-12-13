#include "include/doc_detector.h"
#include <sstream>
#include <iomanip>
#include <chrono>

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

// Global session management
static Ort::Env* g_env = nullptr;
static Ort::SessionOptions* g_session_options = nullptr;
static Ort::Session* g_session = nullptr;
static bool g_initialized = false;

void initOnnxSession() {
    if (g_initialized) {
        LOGD("Session already initialized, skipping");
        return;
    }

    LOGD("Creating ONNX session...");

    // Create environment
    g_env = new Ort::Env(ORT_LOGGING_LEVEL_WARNING, "OcrKit");

    // Create session options with optimizations
    g_session_options = new Ort::SessionOptions();

    // Enable graph optimizations
    g_session_options->SetGraphOptimizationLevel(GraphOptimizationLevel::ORT_ENABLE_ALL);

    // Set thread count for CPU fallback
    g_session_options->SetIntraOpNumThreads(4);
    g_session_options->SetInterOpNumThreads(2);

    // Enable hardware acceleration
#ifdef __ANDROID__
    LOGD("Attempting to enable NNAPI...");
    // Use NNAPI_FLAG_USE_NONE to allow CPU fallback for unsupported ops
    uint32_t nnapi_flags = NNAPI_FLAG_USE_NONE;
    OrtStatus* status = OrtSessionOptionsAppendExecutionProvider_Nnapi(*g_session_options, nnapi_flags);
    if (status != nullptr) {
        const char* error_msg = Ort::GetApi().GetErrorMessage(status);
        LOGD("NNAPI failed: %s", error_msg);
        Ort::GetApi().ReleaseStatus(status);
    } else {
        LOGD("NNAPI execution provider enabled (with CPU fallback)");
    }
#elif defined(__APPLE__)
    LOGD("Attempting to enable Core ML...");
    // Core ML flags: 0 = default, use Neural Engine when available
    uint32_t coreml_flags = 0;
    OrtStatus* status = OrtSessionOptionsAppendExecutionProvider_CoreML(*g_session_options, coreml_flags);
    if (status != nullptr) {
        const char* error_msg = Ort::GetApi().GetErrorMessage(status);
        LOGD("Core ML failed: %s", error_msg);
        Ort::GetApi().ReleaseStatus(status);
    } else {
        LOGD("Core ML execution provider enabled");
    }
#endif

    // Create session
    LOGD("Loading model: %s", ConfigManager::GetInstance().MODEL_PATH.c_str());
    g_session = new Ort::Session(*g_env, ConfigManager::GetInstance().MODEL_PATH.c_str(), *g_session_options);

    g_initialized = true;
    LOGD("ONNX session initialized successfully");
}

std::vector<DetectionBox> detectDocLayout(const cv::Mat& image, float conf_threshold) {
    std::vector<DetectionBox> results;

    LOGD("detectDocLayout called, image size: %dx%d, threshold: %.2f", image.cols, image.rows, conf_threshold);

    if (image.empty()) {
        LOGD("Error: Empty image");
        return results;
    }

    try {
        // Initialize session (only once)
        initOnnxSession();

        if (!g_session) {
            LOGD("Error: Session not initialized");
            return results;
        }

        // Get input/output info
        static Ort::AllocatorWithDefaultOptions allocator;
        static auto input_name = g_session->GetInputNameAllocated(0, allocator);

        // Get number of inputs and outputs
        size_t num_inputs = g_session->GetInputCount();
        size_t num_outputs = g_session->GetOutputCount();
        LOGD("Model has %zu inputs and %zu outputs", num_inputs, num_outputs);

        static auto output_name_0 = g_session->GetOutputNameAllocated(0, allocator);
        static auto output_name_1 = (num_outputs > 1) ? g_session->GetOutputNameAllocated(1, allocator) : g_session->GetOutputNameAllocated(0, allocator);

        // Preprocess image
        int target_width = 640;
        int target_height = 640;
        LOGD("Preprocessing image to %dx%d", target_width, target_height);
        auto [resized_img, scale_factor] = preprocessImage(image, target_width, target_height);
        LOGD("Scale factors: x=%.4f, y=%.4f", scale_factor[0], scale_factor[1]);

        // Convert to blob
        cv::Mat blob = imageToBlob(resized_img);
        LOGD("Blob created, total elements: %zu", blob.total());

        // Prepare input tensors
        std::vector<int64_t> image_shape = {1, 3, target_height, target_width};
        std::vector<int64_t> scale_shape = {1, 2};

        Ort::MemoryInfo memory_info = Ort::MemoryInfo::CreateCpu(OrtArenaAllocator, OrtMemTypeDefault);

        Ort::Value image_tensor = Ort::Value::CreateTensor<float>(
            memory_info, blob.ptr<float>(), blob.total(),
            image_shape.data(), image_shape.size());

        Ort::Value scale_tensor = Ort::Value::CreateTensor<float>(
            memory_info, scale_factor.data(), scale_factor.size(),
            scale_shape.data(), scale_shape.size());

        // Run inference - auto detect model type (M: 2 inputs, L: 3 inputs)
        LOGD("Running inference with %zu inputs...", num_inputs);
        std::vector<Ort::Value> outputs;
        std::vector<const char*> input_names;
        std::vector<Ort::Value> input_tensors;
        std::vector<const char*> output_names = {output_name_0.get()};

        // Track if we're using L model
        bool is_l_model = (num_inputs == 3);

        // Prepare im_shape for L model (original image size)
        std::vector<float> im_shape_data = {static_cast<float>(image.rows), static_cast<float>(image.cols)};
        std::vector<int64_t> im_shape_shape = {1, 2};

        // L model scale_factor = [1.0, 1.0]
        std::vector<float> l_scale_factor = {1.0f, 1.0f};

        if (is_l_model) {
            // L model: im_shape, image, scale_factor
            Ort::Value im_shape_tensor = Ort::Value::CreateTensor<float>(
                memory_info, im_shape_data.data(), im_shape_data.size(),
                im_shape_shape.data(), im_shape_shape.size());

            Ort::Value l_scale_tensor = Ort::Value::CreateTensor<float>(
                memory_info, l_scale_factor.data(), l_scale_factor.size(),
                scale_shape.data(), scale_shape.size());

            input_names = {"im_shape", "image", "scale_factor"};
            input_tensors.push_back(std::move(im_shape_tensor));
            input_tensors.push_back(std::move(image_tensor));
            input_tensors.push_back(std::move(l_scale_tensor));
            LOGD("Using L model format (3 inputs)");
        } else {
            // M model: image, scale_factor
            input_names = {"image", "scale_factor"};
            input_tensors.push_back(std::move(image_tensor));
            input_tensors.push_back(std::move(scale_tensor));
            LOGD("Using M model format (2 inputs)");
        }

        auto start = std::chrono::high_resolution_clock::now();

        outputs = g_session->Run(
            Ort::RunOptions{nullptr},
            input_names.data(), input_tensors.data(), input_tensors.size(),
            output_names.data(), output_names.size());

        auto end = std::chrono::high_resolution_clock::now();
        auto duration = std::chrono::duration_cast<std::chrono::milliseconds>(end - start).count();
        LOGD("Inference complete in %lld ms", duration);

        // Parse output: [N, 6] = [class_id, score, x1, y1, x2, y2]
        auto output_shape = outputs[0].GetTensorTypeAndShapeInfo().GetShape();
        int num_detections = static_cast<int>(output_shape[0]);
        LOGD("Number of raw detections: %d", num_detections);

        float* output_data = outputs[0].GetTensorMutableData<float>();

        // Convert to DetectionBox and restore to original image coordinates
        float inv_scale_x = is_l_model ? 1.0f : (1.0f / scale_factor[0]);
        float inv_scale_y = is_l_model ? 1.0f : (1.0f / scale_factor[1]);

        for (int i = 0; i < num_detections; i++) {
            int class_id = static_cast<int>(output_data[i * 6 + 0]);
            float score = output_data[i * 6 + 1];
            float x1 = output_data[i * 6 + 2];
            float y1 = output_data[i * 6 + 3];
            float x2 = output_data[i * 6 + 4];
            float y2 = output_data[i * 6 + 5];

            if (score >= conf_threshold && class_id >= 0 && class_id < static_cast<int>(DOC_CLASSES.size())) {
                DetectionBox box;
                box.x1 = x1 * inv_scale_x;
                box.y1 = y1 * inv_scale_y;
                box.x2 = x2 * inv_scale_x;
                box.y2 = y2 * inv_scale_y;

                // Clamp coordinates to image bounds
                box.x1 = std::max(0.0f, std::min(box.x1, static_cast<float>(image.cols)));
                box.y1 = std::max(0.0f, std::min(box.y1, static_cast<float>(image.rows)));
                box.x2 = std::max(0.0f, std::min(box.x2, static_cast<float>(image.cols)));
                box.y2 = std::max(0.0f, std::min(box.y2, static_cast<float>(image.rows)));

                box.score = score;
                box.class_id = class_id;
                box.class_name = DOC_CLASSES[class_id];
                results.push_back(box);
            }
        }

    } catch (const Ort::Exception& e) {
        LOGD("ONNX Runtime error: %s", e.what());
    } catch (const cv::Exception& e) {
        LOGD("OpenCV error: %s", e.what());
    } catch (const std::exception& e) {
        LOGD("Error: %s", e.what());
    }

    return results;
}

std::string detectionsToJson(const std::vector<DetectionBox>& detections) {
    std::ostringstream json;
    json << "{\"detections\":[";

    for (size_t i = 0; i < detections.size(); i++) {
        const auto& box = detections[i];
        json << "{";
        json << "\"x1\":" << std::fixed << std::setprecision(2) << box.x1 << ",";
        json << "\"y1\":" << box.y1 << ",";
        json << "\"x2\":" << box.x2 << ",";
        json << "\"y2\":" << box.y2 << ",";
        json << "\"score\":" << std::setprecision(4) << box.score << ",";
        json << "\"class_id\":" << box.class_id << ",";
        json << "\"class_name\":\"" << box.class_name << "\"";
        json << "}";
        if (i < detections.size() - 1) {
            json << ",";
        }
    }

    json << "],\"count\":" << detections.size() << "}";
    return json.str();
}

#include "include/utils.h"

std::pair<cv::Mat, std::vector<float>> preprocessImage(const cv::Mat& img, int target_width, int target_height) {
    int orig_height = img.rows;
    int orig_width = img.cols;

    float scale_x = static_cast<float>(target_width) / orig_width;
    float scale_y = static_cast<float>(target_height) / orig_height;
    std::vector<float> scale_factor = {scale_x, scale_y};

    cv::Mat img_rgb;
    cv::cvtColor(img, img_rgb, cv::COLOR_BGR2RGB);

    cv::Mat resized;
    cv::resize(img_rgb, resized, cv::Size(target_width, target_height), 0, 0, cv::INTER_LINEAR);

    return {resized, scale_factor};
}

cv::Mat imageToBlob(const cv::Mat& img) {
    cv::Mat blob = cv::dnn::blobFromImage(
        img,
        1.0 / 255.0,
        cv::Size(),
        cv::Scalar(0, 0, 0),
        false,
        false,
        CV_32F
    );
    return blob;
}

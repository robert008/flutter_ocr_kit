#import "OcrKitPlugin.h"

// Layout detection functions
extern void initModel(const char* model_path);
extern char* detectLayout(const char* img_path, float conf_threshold);
extern void freeString(char* str);
extern const char* getVersion(void);

// OCR functions (PP-OCR)
extern void initOcrModels(const char* det_model_path, const char* rec_model_path, const char* dict_path);
extern void releaseOcrEngine(void);
extern char* recognizeTextFromPath(const char* img_path, float det_threshold, float rec_threshold);
extern char* recognizeTextFromBuffer(const uint8_t* buffer, int width, int height, int stride,
                                      float det_threshold, float rec_threshold);
extern char* detectTextFromPath(const char* img_path, float threshold);

// Apple Vision OCR functions
extern char* recognizeTextWithVision(const char* imagePath, const char* languages);
extern char* recognizeRegionWithVision(const char* imagePath,
                                        float cropX1, float cropY1,
                                        float cropX2, float cropY2,
                                        const char* languages);
extern char* getVisionSupportedLanguages(void);

@implementation OcrKitPlugin
+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar>*)registrar {
    NSLog(@"OcrKit registered with Flutter");
}

+ (void)load {
    NSLog(@"OcrKit: +load method called");

    volatile const char* version = getVersion();
    NSLog(@"OcrKit: Version check completed: %s", version);

    if (version == NULL) {
        // Force link layout detection symbols
        initModel("/nonexistent");
        detectLayout("/nonexistent", 0.0f);
        freeString(NULL);

        // Force link OCR symbols (PP-OCR)
        initOcrModels("/nonexistent", "/nonexistent", "/nonexistent");
        releaseOcrEngine();
        recognizeTextFromPath("/nonexistent", 0.0f, 0.0f);
        recognizeTextFromBuffer(NULL, 0, 0, 0, 0.0f, 0.0f);
        detectTextFromPath("/nonexistent", 0.0f);

        // Force link Vision OCR symbols
        recognizeTextWithVision("/nonexistent", "");
        recognizeRegionWithVision("/nonexistent", 0.0f, 0.0f, 0.0f, 0.0f, "");
        getVisionSupportedLanguages();
    }
    NSLog(@"OcrKit: All symbols retained");
}
@end

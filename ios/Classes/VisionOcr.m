#import <Foundation/Foundation.h>
#import <Vision/Vision.h>
#import <UIKit/UIKit.h>

// JSON helper for building response
static NSString* buildJsonResponse(NSArray<NSDictionary*>* textLines,
                                    NSArray<NSDictionary*>* words,
                                    int imageWidth,
                                    int imageHeight,
                                    int64_t inferenceTimeMs,
                                    NSString* error) {
    NSMutableDictionary* response = [NSMutableDictionary dictionary];

    if (error) {
        response[@"error"] = error;
        response[@"results"] = @[];
        response[@"words"] = @[];
    } else {
        response[@"results"] = textLines ?: @[];
        response[@"words"] = words ?: @[];
    }

    response[@"image_width"] = @(imageWidth);
    response[@"image_height"] = @(imageHeight);
    response[@"inference_time_ms"] = @(inferenceTimeMs);
    response[@"count"] = @(textLines.count);

    NSError* jsonError = nil;
    NSData* jsonData = [NSJSONSerialization dataWithJSONObject:response
                                                      options:0
                                                        error:&jsonError];
    if (jsonError) {
        return [NSString stringWithFormat:@"{\"error\":\"%@\",\"results\":[],\"words\":[],\"count\":0}",
                jsonError.localizedDescription];
    }

    return [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
}

// Helper function to normalize image orientation
static UIImage* normalizeImageOrientation(UIImage* image) {
    if (image.imageOrientation == UIImageOrientationUp) {
        return image;
    }

    UIGraphicsBeginImageContextWithOptions(image.size, NO, image.scale);
    [image drawInRect:CGRectMake(0, 0, image.size.width, image.size.height)];
    UIImage* normalizedImage = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();

    return normalizedImage;
}

// Recognize text from image path using Apple Vision
char* recognizeTextWithVision(const char* imagePath, const char* languages) {
    @autoreleasepool {
        NSString* path = [NSString stringWithUTF8String:imagePath];

        // Load image
        UIImage* image = [UIImage imageWithContentsOfFile:path];
        if (!image) {
            NSString* json = buildJsonResponse(nil, nil, 0, 0, 0,
                [NSString stringWithFormat:@"Failed to load image: %@", path]);
            return strdup([json UTF8String]);
        }

        // Normalize image orientation (apply EXIF rotation)
        image = normalizeImageOrientation(image);

        CGImageRef cgImage = image.CGImage;
        if (!cgImage) {
            NSString* json = buildJsonResponse(nil, nil, 0, 0, 0, @"Failed to get CGImage");
            return strdup([json UTF8String]);
        }

        int imageWidth = (int)CGImageGetWidth(cgImage);
        int imageHeight = (int)CGImageGetHeight(cgImage);

        // Start timing
        NSDate* startTime = [NSDate date];

        // Create text recognition request
        __block NSMutableArray<NSDictionary*>* textLines = [NSMutableArray array];
        __block NSMutableArray<NSDictionary*>* words = [NSMutableArray array];
        __block NSString* requestError = nil;

        VNRecognizeTextRequest* request = [[VNRecognizeTextRequest alloc]
            initWithCompletionHandler:^(VNRequest* request, NSError* error) {
                if (error) {
                    requestError = error.localizedDescription;
                    return;
                }

                NSArray<VNRecognizedTextObservation*>* observations = request.results;

                for (VNRecognizedTextObservation* observation in observations) {
                    // Get top candidate
                    VNRecognizedText* topCandidate = [[observation topCandidates:1] firstObject];
                    if (!topCandidate) continue;

                    NSString* text = topCandidate.string;
                    float confidence = topCandidate.confidence;

                    // Convert normalized coordinates to image coordinates
                    // Vision uses bottom-left origin, we need top-left
                    CGRect boundingBox = observation.boundingBox;

                    float x1 = boundingBox.origin.x * imageWidth;
                    float y1 = (1.0 - boundingBox.origin.y - boundingBox.size.height) * imageHeight;
                    float x2 = (boundingBox.origin.x + boundingBox.size.width) * imageWidth;
                    float y2 = (1.0 - boundingBox.origin.y) * imageHeight;

                    NSDictionary* lineDict = @{
                        @"text": text,
                        @"score": @(confidence),
                        @"x1": @(x1),
                        @"y1": @(y1),
                        @"x2": @(x2),
                        @"y2": @(y2)
                    };

                    [textLines addObject:lineDict];

                    // Extract word-level bounding boxes
                    // For CJK: each character is a word
                    // For Latin: split by spaces
                    NSUInteger textLen = text.length;
                    NSUInteger currentIndex = 0;

                    while (currentIndex < textLen) {
                        unichar currentChar = [text characterAtIndex:currentIndex];
                        NSUInteger wordStart = currentIndex;
                        NSUInteger wordEnd = currentIndex;

                        // Check if CJK character (Chinese, Japanese, Korean)
                        BOOL isCJK = (currentChar >= 0x4E00 && currentChar <= 0x9FFF) ||   // CJK Unified
                                     (currentChar >= 0x3400 && currentChar <= 0x4DBF) ||   // CJK Extension A
                                     (currentChar >= 0x3000 && currentChar <= 0x303F) ||   // CJK Punctuation
                                     (currentChar >= 0xFF00 && currentChar <= 0xFFEF) ||   // Fullwidth
                                     (currentChar >= 0x3040 && currentChar <= 0x309F) ||   // Hiragana
                                     (currentChar >= 0x30A0 && currentChar <= 0x30FF);     // Katakana

                        if (isCJK) {
                            // Each CJK character is its own word
                            wordEnd = currentIndex + 1;
                        } else if ([[NSCharacterSet whitespaceAndNewlineCharacterSet] characterIsMember:currentChar]) {
                            // Skip whitespace
                            currentIndex++;
                            continue;
                        } else {
                            // Latin word: continue until whitespace or CJK
                            while (wordEnd < textLen) {
                                unichar nextChar = [text characterAtIndex:wordEnd];
                                BOOL nextIsCJK = (nextChar >= 0x4E00 && nextChar <= 0x9FFF) ||
                                                 (nextChar >= 0x3400 && nextChar <= 0x4DBF) ||
                                                 (nextChar >= 0x3000 && nextChar <= 0x303F) ||
                                                 (nextChar >= 0xFF00 && nextChar <= 0xFFEF) ||
                                                 (nextChar >= 0x3040 && nextChar <= 0x309F) ||
                                                 (nextChar >= 0x30A0 && nextChar <= 0x30FF);
                                if ([[NSCharacterSet whitespaceAndNewlineCharacterSet] characterIsMember:nextChar] || nextIsCJK) {
                                    break;
                                }
                                wordEnd++;
                            }
                        }

                        // Get bounding box for this word/character range
                        NSRange wordRange = NSMakeRange(wordStart, wordEnd - wordStart);
                        NSString* wordText = [text substringWithRange:wordRange];

                        if (wordText.length > 0) {
                            NSError* boxError = nil;
                            VNRectangleObservation* wordBox = [topCandidate boundingBoxForRange:wordRange error:&boxError];

                            if (wordBox && !boxError) {
                                // Get the quad points and compute bounding rect
                                CGPoint topLeft = wordBox.topLeft;
                                CGPoint topRight = wordBox.topRight;
                                CGPoint bottomLeft = wordBox.bottomLeft;
                                CGPoint bottomRight = wordBox.bottomRight;

                                // Find min/max for bounding rect (Vision coords are normalized, bottom-left origin)
                                float minX = MIN(MIN(topLeft.x, topRight.x), MIN(bottomLeft.x, bottomRight.x));
                                float maxX = MAX(MAX(topLeft.x, topRight.x), MAX(bottomLeft.x, bottomRight.x));
                                float minY = MIN(MIN(topLeft.y, topRight.y), MIN(bottomLeft.y, bottomRight.y));
                                float maxY = MAX(MAX(topLeft.y, topRight.y), MAX(bottomLeft.y, bottomRight.y));

                                // Convert to image coordinates
                                float wx1 = minX * imageWidth;
                                float wy1 = (1.0 - maxY) * imageHeight;
                                float wx2 = maxX * imageWidth;
                                float wy2 = (1.0 - minY) * imageHeight;

                                NSDictionary* wordDict = @{
                                    @"text": wordText,
                                    @"score": @(confidence),
                                    @"x1": @(wx1),
                                    @"y1": @(wy1),
                                    @"x2": @(wx2),
                                    @"y2": @(wy2)
                                };
                                [words addObject:wordDict];
                            }
                        }

                        currentIndex = wordEnd;
                    }
                }
            }];

        // Configure request - Accurate for good recognition
        request.recognitionLevel = VNRequestTextRecognitionLevelAccurate;
        request.usesLanguageCorrection = NO;  // Disable for speed

        // Set recognition languages if specified
        if (languages && strlen(languages) > 0) {
            NSString* langStr = [NSString stringWithUTF8String:languages];
            NSArray<NSString*>* langArray = [langStr componentsSeparatedByString:@","];
            request.recognitionLanguages = langArray;
        } else {
            // Default: Chinese (Traditional & Simplified) + English
            if (@available(iOS 16.0, *)) {
                // iOS 16+ supports automatic language detection
                request.automaticallyDetectsLanguage = YES;
            }
            request.recognitionLanguages = @[@"zh-Hant", @"zh-Hans", @"en-US"];
        }

        // Create image request handler
        VNImageRequestHandler* handler = [[VNImageRequestHandler alloc]
            initWithCGImage:cgImage
            options:@{}];

        // Perform request
        NSError* performError = nil;
        [handler performRequests:@[request] error:&performError];

        // Calculate inference time
        NSTimeInterval elapsed = [[NSDate date] timeIntervalSinceDate:startTime];
        int64_t inferenceTimeMs = (int64_t)(elapsed * 1000);

        if (performError) {
            NSString* json = buildJsonResponse(nil, nil, imageWidth, imageHeight, inferenceTimeMs,
                performError.localizedDescription);
            return strdup([json UTF8String]);
        }

        if (requestError) {
            NSString* json = buildJsonResponse(nil, nil, imageWidth, imageHeight, inferenceTimeMs,
                requestError);
            return strdup([json UTF8String]);
        }

        // Build success response
        NSString* json = buildJsonResponse(textLines, words, imageWidth, imageHeight, inferenceTimeMs, nil);
        return strdup([json UTF8String]);
    }
}

// Recognize text from cropped region (for use with layout detection)
char* recognizeRegionWithVision(const char* imagePath,
                                 float cropX1, float cropY1,
                                 float cropX2, float cropY2,
                                 const char* languages) {
    @autoreleasepool {
        NSString* path = [NSString stringWithUTF8String:imagePath];

        // Load image
        UIImage* image = [UIImage imageWithContentsOfFile:path];
        if (!image) {
            NSString* json = buildJsonResponse(nil, nil, 0, 0, 0,
                [NSString stringWithFormat:@"Failed to load image: %@", path]);
            return strdup([json UTF8String]);
        }

        // Normalize image orientation (apply EXIF rotation)
        image = normalizeImageOrientation(image);

        CGImageRef cgImage = image.CGImage;
        if (!cgImage) {
            NSString* json = buildJsonResponse(nil, nil, 0, 0, 0, @"Failed to get CGImage");
            return strdup([json UTF8String]);
        }

        int fullWidth = (int)CGImageGetWidth(cgImage);
        int fullHeight = (int)CGImageGetHeight(cgImage);

        // Crop region
        CGRect cropRect = CGRectMake(cropX1, cropY1, cropX2 - cropX1, cropY2 - cropY1);

        // Clamp to image bounds
        cropRect.origin.x = MAX(0, cropRect.origin.x);
        cropRect.origin.y = MAX(0, cropRect.origin.y);
        cropRect.size.width = MIN(cropRect.size.width, fullWidth - cropRect.origin.x);
        cropRect.size.height = MIN(cropRect.size.height, fullHeight - cropRect.origin.y);

        if (cropRect.size.width <= 0 || cropRect.size.height <= 0) {
            NSString* json = buildJsonResponse(nil, nil, 0, 0, 0, @"Invalid crop region");
            return strdup([json UTF8String]);
        }

        CGImageRef croppedImage = CGImageCreateWithImageInRect(cgImage, cropRect);
        if (!croppedImage) {
            NSString* json = buildJsonResponse(nil, nil, 0, 0, 0, @"Failed to crop image");
            return strdup([json UTF8String]);
        }

        int cropWidth = (int)CGImageGetWidth(croppedImage);
        int cropHeight = (int)CGImageGetHeight(croppedImage);

        // Start timing
        NSDate* startTime = [NSDate date];

        // Create text recognition request
        __block NSMutableArray<NSDictionary*>* textLines = [NSMutableArray array];
        __block NSString* requestError = nil;

        VNRecognizeTextRequest* request = [[VNRecognizeTextRequest alloc]
            initWithCompletionHandler:^(VNRequest* request, NSError* error) {
                if (error) {
                    requestError = error.localizedDescription;
                    return;
                }

                NSArray<VNRecognizedTextObservation*>* observations = request.results;

                for (VNRecognizedTextObservation* observation in observations) {
                    VNRecognizedText* topCandidate = [[observation topCandidates:1] firstObject];
                    if (!topCandidate) continue;

                    NSString* text = topCandidate.string;
                    float confidence = topCandidate.confidence;

                    // Convert to crop-space coordinates, then to full-image coordinates
                    CGRect boundingBox = observation.boundingBox;

                    // In crop space
                    float localX1 = boundingBox.origin.x * cropWidth;
                    float localY1 = (1.0 - boundingBox.origin.y - boundingBox.size.height) * cropHeight;
                    float localX2 = (boundingBox.origin.x + boundingBox.size.width) * cropWidth;
                    float localY2 = (1.0 - boundingBox.origin.y) * cropHeight;

                    // Convert to full image coordinates
                    float globalX1 = cropX1 + localX1;
                    float globalY1 = cropY1 + localY1;
                    float globalX2 = cropX1 + localX2;
                    float globalY2 = cropY1 + localY2;

                    NSDictionary* lineDict = @{
                        @"text": text,
                        @"score": @(confidence),
                        @"x1": @(globalX1),
                        @"y1": @(globalY1),
                        @"x2": @(globalX2),
                        @"y2": @(globalY2)
                    };

                    [textLines addObject:lineDict];
                }
            }];

        // Configure request - Accurate for good recognition
        request.recognitionLevel = VNRequestTextRecognitionLevelAccurate;
        request.usesLanguageCorrection = NO;  // Disable for speed

        if (languages && strlen(languages) > 0) {
            NSString* langStr = [NSString stringWithUTF8String:languages];
            NSArray<NSString*>* langArray = [langStr componentsSeparatedByString:@","];
            request.recognitionLanguages = langArray;
        } else {
            if (@available(iOS 16.0, *)) {
                request.automaticallyDetectsLanguage = YES;
            }
            request.recognitionLanguages = @[@"zh-Hant", @"zh-Hans", @"en-US"];
        }

        // Create handler for cropped image
        VNImageRequestHandler* handler = [[VNImageRequestHandler alloc]
            initWithCGImage:croppedImage
            options:@{}];

        // Perform request
        NSError* performError = nil;
        [handler performRequests:@[request] error:&performError];

        CGImageRelease(croppedImage);

        // Calculate inference time
        NSTimeInterval elapsed = [[NSDate date] timeIntervalSinceDate:startTime];
        int64_t inferenceTimeMs = (int64_t)(elapsed * 1000);

        if (performError) {
            NSString* json = buildJsonResponse(nil, nil, fullWidth, fullHeight, inferenceTimeMs,
                performError.localizedDescription);
            return strdup([json UTF8String]);
        }

        if (requestError) {
            NSString* json = buildJsonResponse(nil, nil, fullWidth, fullHeight, inferenceTimeMs,
                requestError);
            return strdup([json UTF8String]);
        }

        // Build success response (report full image dimensions for consistency)
        // Note: Region function doesn't include word-level boxes for simplicity
        NSString* json = buildJsonResponse(textLines, @[], fullWidth, fullHeight, inferenceTimeMs, nil);
        return strdup([json UTF8String]);
    }
}

// Get supported languages for Vision OCR
char* getVisionSupportedLanguages(void) {
    @autoreleasepool {
        NSError* error = nil;
        NSArray<NSString*>* languages = [VNRecognizeTextRequest supportedRecognitionLanguagesForTextRecognitionLevel:VNRequestTextRecognitionLevelAccurate revision:VNRecognizeTextRequestRevision3 error:&error];

        if (error || !languages) {
            return strdup("[]");
        }

        NSData* jsonData = [NSJSONSerialization dataWithJSONObject:languages options:0 error:&error];
        if (error) {
            return strdup("[]");
        }

        NSString* jsonStr = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
        return strdup([jsonStr UTF8String]);
    }
}

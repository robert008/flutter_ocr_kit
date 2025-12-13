package com.example.flutter_ocr_kit

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import android.graphics.Rect
import androidx.exifinterface.media.ExifInterface
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.TextRecognizer
import com.google.mlkit.vision.text.chinese.ChineseTextRecognizerOptions
import com.google.mlkit.vision.text.latin.TextRecognizerOptions
import com.google.gson.Gson
import kotlinx.coroutines.tasks.await
import java.io.File

class MlKitOcr(private val context: Context) {
    private val gson = Gson()

    // Load bitmap and apply EXIF orientation correction
    private fun loadBitmapWithCorrectOrientation(imagePath: String): Bitmap? {
        val bitmap = BitmapFactory.decodeFile(imagePath) ?: return null

        return try {
            val exif = ExifInterface(imagePath)
            val orientation = exif.getAttributeInt(
                ExifInterface.TAG_ORIENTATION,
                ExifInterface.ORIENTATION_NORMAL
            )

            val matrix = Matrix()
            when (orientation) {
                ExifInterface.ORIENTATION_ROTATE_90 -> matrix.postRotate(90f)
                ExifInterface.ORIENTATION_ROTATE_180 -> matrix.postRotate(180f)
                ExifInterface.ORIENTATION_ROTATE_270 -> matrix.postRotate(270f)
                ExifInterface.ORIENTATION_FLIP_HORIZONTAL -> matrix.preScale(-1f, 1f)
                ExifInterface.ORIENTATION_FLIP_VERTICAL -> matrix.preScale(1f, -1f)
                ExifInterface.ORIENTATION_TRANSPOSE -> {
                    matrix.postRotate(90f)
                    matrix.preScale(-1f, 1f)
                }
                ExifInterface.ORIENTATION_TRANSVERSE -> {
                    matrix.postRotate(270f)
                    matrix.preScale(-1f, 1f)
                }
                else -> return bitmap // No rotation needed
            }

            val rotatedBitmap = Bitmap.createBitmap(
                bitmap, 0, 0, bitmap.width, bitmap.height, matrix, true
            )

            if (rotatedBitmap != bitmap) {
                bitmap.recycle()
            }

            rotatedBitmap
        } catch (e: Exception) {
            // If EXIF reading fails, return original bitmap
            bitmap
        }
    }

    // Lazy initialization of recognizers
    private val chineseRecognizer: TextRecognizer by lazy {
        TextRecognition.getClient(ChineseTextRecognizerOptions.Builder().build())
    }

    private val latinRecognizer: TextRecognizer by lazy {
        TextRecognition.getClient(TextRecognizerOptions.Builder().build())
    }

    suspend fun recognizeText(imagePath: String, languages: List<String>): String {
        val startTime = System.currentTimeMillis()

        // Load image with correct orientation
        val bitmap = loadBitmapWithCorrectOrientation(imagePath)
            ?: return buildErrorResponse("Failed to load image: $imagePath", 0, 0, 0)

        val imageWidth = bitmap.width
        val imageHeight = bitmap.height

        return try {
            val inputImage = InputImage.fromBitmap(bitmap, 0)

            // Choose recognizer based on languages
            val recognizer = selectRecognizer(languages)

            // Run recognition
            val result = recognizer.process(inputImage).await()

            val textLines = mutableListOf<Map<String, Any>>()
            val words = mutableListOf<Map<String, Any>>()

            for (block in result.textBlocks) {
                for (line in block.lines) {
                    val boundingBox = line.boundingBox ?: continue
                    val confidence = line.confidence ?: 0.9f // ML Kit doesn't always provide confidence

                    textLines.add(
                        mapOf(
                            "text" to line.text,
                            "score" to confidence,
                            "x1" to boundingBox.left.toFloat(),
                            "y1" to boundingBox.top.toFloat(),
                            "x2" to boundingBox.right.toFloat(),
                            "y2" to boundingBox.bottom.toFloat()
                        )
                    )

                    // Extract word-level (Element) bounding boxes
                    for (element in line.elements) {
                        val elementBox = element.boundingBox ?: continue
                        val elementConfidence = element.confidence ?: confidence

                        words.add(
                            mapOf(
                                "text" to element.text,
                                "score" to elementConfidence,
                                "x1" to elementBox.left.toFloat(),
                                "y1" to elementBox.top.toFloat(),
                                "x2" to elementBox.right.toFloat(),
                                "y2" to elementBox.bottom.toFloat()
                            )
                        )
                    }
                }
            }

            val inferenceTime = System.currentTimeMillis() - startTime

            buildSuccessResponse(textLines, words, imageWidth, imageHeight, inferenceTime)
        } catch (e: Exception) {
            val inferenceTime = System.currentTimeMillis() - startTime
            buildErrorResponse(e.message ?: "Unknown error", imageWidth, imageHeight, inferenceTime)
        } finally {
            bitmap.recycle()
        }
    }

    suspend fun recognizeRegion(
        imagePath: String,
        cropX1: Float, cropY1: Float,
        cropX2: Float, cropY2: Float,
        languages: List<String>
    ): String {
        val startTime = System.currentTimeMillis()

        // Load full image with correct orientation
        val fullBitmap = loadBitmapWithCorrectOrientation(imagePath)
            ?: return buildErrorResponse("Failed to load image: $imagePath", 0, 0, 0)

        val fullWidth = fullBitmap.width
        val fullHeight = fullBitmap.height

        return try {
            // Calculate crop region (clamp to image bounds)
            val left = cropX1.toInt().coerceIn(0, fullWidth - 1)
            val top = cropY1.toInt().coerceIn(0, fullHeight - 1)
            val right = cropX2.toInt().coerceIn(left + 1, fullWidth)
            val bottom = cropY2.toInt().coerceIn(top + 1, fullHeight)

            val cropWidth = right - left
            val cropHeight = bottom - top

            if (cropWidth <= 0 || cropHeight <= 0) {
                return buildErrorResponse("Invalid crop region", fullWidth, fullHeight, 0)
            }

            // Crop the bitmap
            val croppedBitmap = Bitmap.createBitmap(fullBitmap, left, top, cropWidth, cropHeight)
            fullBitmap.recycle()

            val inputImage = InputImage.fromBitmap(croppedBitmap, 0)

            // Choose recognizer
            val recognizer = selectRecognizer(languages)

            // Run recognition
            val result = recognizer.process(inputImage).await()

            val textLines = mutableListOf<Map<String, Any>>()

            for (block in result.textBlocks) {
                for (line in block.lines) {
                    val boundingBox = line.boundingBox ?: continue
                    val confidence = line.confidence ?: 0.9f

                    // Convert coordinates back to full image space
                    textLines.add(
                        mapOf(
                            "text" to line.text,
                            "score" to confidence,
                            "x1" to (boundingBox.left + left).toFloat(),
                            "y1" to (boundingBox.top + top).toFloat(),
                            "x2" to (boundingBox.right + left).toFloat(),
                            "y2" to (boundingBox.bottom + top).toFloat()
                        )
                    )
                }
            }

            croppedBitmap.recycle()

            val inferenceTime = System.currentTimeMillis() - startTime

            // Note: Region function doesn't include word-level boxes for simplicity
            buildSuccessResponse(textLines, emptyList(), fullWidth, fullHeight, inferenceTime)
        } catch (e: Exception) {
            val inferenceTime = System.currentTimeMillis() - startTime
            buildErrorResponse(e.message ?: "Unknown error", fullWidth, fullHeight, inferenceTime)
        }
    }

    fun getSupportedLanguages(): List<String> {
        // ML Kit supported language codes
        return listOf(
            "zh-Hant",  // Traditional Chinese
            "zh-Hans",  // Simplified Chinese
            "en",       // English
            "ja",       // Japanese (via Chinese recognizer)
            "ko"        // Korean (via Chinese recognizer)
        )
    }

    fun close() {
        try {
            chineseRecognizer.close()
            latinRecognizer.close()
        } catch (_: Exception) {
            // Ignore close errors
        }
    }

    private fun selectRecognizer(languages: List<String>): TextRecognizer {
        // If languages contain Chinese, Japanese, or Korean, use Chinese recognizer
        val needsCjk = languages.isEmpty() || languages.any { lang ->
            lang.startsWith("zh") || lang.startsWith("ja") || lang.startsWith("ko")
        }

        return if (needsCjk) chineseRecognizer else latinRecognizer
    }

    private fun buildSuccessResponse(
        textLines: List<Map<String, Any>>,
        words: List<Map<String, Any>>,
        imageWidth: Int,
        imageHeight: Int,
        inferenceTimeMs: Long
    ): String {
        val response = mapOf(
            "results" to textLines,
            "words" to words,
            "image_width" to imageWidth,
            "image_height" to imageHeight,
            "inference_time_ms" to inferenceTimeMs,
            "count" to textLines.size
        )
        return gson.toJson(response)
    }

    private fun buildErrorResponse(
        error: String,
        imageWidth: Int,
        imageHeight: Int,
        inferenceTimeMs: Long
    ): String {
        val response = mapOf(
            "error" to error,
            "results" to emptyList<Map<String, Any>>(),
            "words" to emptyList<Map<String, Any>>(),
            "image_width" to imageWidth,
            "image_height" to imageHeight,
            "inference_time_ms" to inferenceTimeMs,
            "count" to 0
        )
        return gson.toJson(response)
    }
}

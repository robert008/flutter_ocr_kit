package com.example.flutter_ocr_kit

import android.content.Context
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

class FlutterOcrKitPlugin : FlutterPlugin, MethodCallHandler {
    private lateinit var channel: MethodChannel
    private lateinit var context: Context
    private lateinit var mlKitOcr: MlKitOcr
    private val scope = CoroutineScope(Dispatchers.Main)

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(flutterPluginBinding.binaryMessenger, "flutter_ocr_kit")
        channel.setMethodCallHandler(this)
        context = flutterPluginBinding.applicationContext
        mlKitOcr = MlKitOcr(context)
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "recognizeWithMlKit" -> {
                val imagePath = call.argument<String>("imagePath")
                val languages = call.argument<List<String>>("languages") ?: emptyList()

                if (imagePath == null) {
                    result.error("INVALID_ARGUMENT", "imagePath is required", null)
                    return
                }

                scope.launch {
                    try {
                        val ocrResult = withContext(Dispatchers.IO) {
                            mlKitOcr.recognizeText(imagePath, languages)
                        }
                        result.success(ocrResult)
                    } catch (e: Exception) {
                        result.error("OCR_ERROR", e.message, e.stackTraceToString())
                    }
                }
            }

            "recognizeRegionWithMlKit" -> {
                val imagePath = call.argument<String>("imagePath")
                val x1 = call.argument<Double>("x1")
                val y1 = call.argument<Double>("y1")
                val x2 = call.argument<Double>("x2")
                val y2 = call.argument<Double>("y2")
                val languages = call.argument<List<String>>("languages") ?: emptyList()

                if (imagePath == null || x1 == null || y1 == null || x2 == null || y2 == null) {
                    result.error("INVALID_ARGUMENT", "imagePath and crop coordinates are required", null)
                    return
                }

                scope.launch {
                    try {
                        val ocrResult = withContext(Dispatchers.IO) {
                            mlKitOcr.recognizeRegion(
                                imagePath,
                                x1.toFloat(), y1.toFloat(),
                                x2.toFloat(), y2.toFloat(),
                                languages
                            )
                        }
                        result.success(ocrResult)
                    } catch (e: Exception) {
                        result.error("OCR_ERROR", e.message, e.stackTraceToString())
                    }
                }
            }

            "getMlKitSupportedLanguages" -> {
                result.success(mlKitOcr.getSupportedLanguages())
            }

            else -> {
                result.notImplemented()
            }
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        mlKitOcr.close()
    }
}

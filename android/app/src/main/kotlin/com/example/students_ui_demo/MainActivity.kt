package com.example.students_ui_demo

import ai.onnxruntime.OnnxTensor
import ai.onnxruntime.OnnxValue
import ai.onnxruntime.OrtEnvironment
import ai.onnxruntime.OrtSession
import ai.onnxruntime.TensorInfo
import android.content.res.AssetManager
import android.app.ActivityManager
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.media.AudioManager
import android.view.View
import android.view.WindowManager
import io.flutter.FlutterInjector
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.nio.FloatBuffer
import kotlin.math.abs
import kotlin.math.floor
import kotlin.math.max
import kotlin.math.min
import kotlin.system.measureNanoTime

class MainActivity : FlutterActivity() {
    private val optimizedVisionEngine = AndroidOptimizedVisionRuntimeEngine()
    private val faceLandmarkerChannel by lazy { AndroidFaceLandmarkerChannel(this) }
    private val faceEmbeddingChannel = AndroidFaceEmbeddingChannel()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        registerOptimizedVisionRuntime(flutterEngine)
        registerFaceLandmarkerRuntime(flutterEngine)
        registerFaceEmbeddingRuntime(flutterEngine)
        registerExamLockdown(flutterEngine)
    }

    private fun registerExamLockdown(flutterEngine: FlutterEngine) {
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "kslas.exam_lockdown",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "prepare" -> result.success(prepareExamDevice(startPinned = false))
                "enter" -> result.success(prepareExamDevice(startPinned = true))
                "exit" -> {
                    exitExamDeviceMode()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun prepareExamDevice(startPinned: Boolean): Map<String, Any> {
        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        val clipboard = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
        clipboard.setPrimaryClip(ClipData.newPlainText("", ""))
        if (startPinned) {
            window.decorView.systemUiVisibility =
                View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY or
                View.SYSTEM_UI_FLAG_FULLSCREEN or
                View.SYSTEM_UI_FLAG_HIDE_NAVIGATION
            try {
                startLockTask()
            } catch (_: Throwable) {
                // The returned state remains false when Android/device policy
                // does not permit pinning or the user declines confirmation.
            }
        }
        val audio = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        val activity = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        val lockActive = activity.lockTaskModeState != ActivityManager.LOCK_TASK_MODE_NONE
        return mapOf(
            "supported" to true,
            "screen_capture_blocked" to true,
            "clipboard_cleared" to (
                !clipboard.hasPrimaryClip() ||
                    clipboard.primaryClip?.getItemAt(0)?.text.isNullOrEmpty()
                ),
            "output_muted" to (audio.getStreamVolume(AudioManager.STREAM_MUSIC) <= 0),
            "microphone_muted" to audio.isMicrophoneMute,
            "lock_task_active" to lockActive,
        )
    }

    private fun exitExamDeviceMode() {
        try {
            val activity = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
            if (activity.lockTaskModeState != ActivityManager.LOCK_TASK_MODE_NONE) stopLockTask()
        } catch (_: Throwable) {
        }
        window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
        window.decorView.systemUiVisibility = View.SYSTEM_UI_FLAG_VISIBLE
    }

    private fun registerFaceEmbeddingRuntime(flutterEngine: FlutterEngine) {
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "kslas.face_embedding",
        ).setMethodCallHandler { call, result ->
            val request = call.arguments as? Map<*, *>
            when (call.method) {
                "initialize" -> result.success(faceEmbeddingChannel.initialize(request))
                "health" -> result.success(faceEmbeddingChannel.health())
                "embedAlignedRgb" -> result.success(faceEmbeddingChannel.embedAlignedRgb(request))
                "storeProtectedTemplate" ->
                    result.success(faceEmbeddingChannel.storeProtectedTemplate(request))
                "loadProtectedTemplate" ->
                    result.success(faceEmbeddingChannel.loadProtectedTemplate(request))
                else -> result.notImplemented()
            }
        }
    }

    private fun registerOptimizedVisionRuntime(flutterEngine: FlutterEngine) {
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "kslas.optimized_vision_runtime",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "initialize" -> {
                    val policy = call.arguments as? Map<*, *>
                    result.success(
                        optimizedVisionEngine.initialize(
                            policy,
                            assets,
                        ),
                    )
                }

                "runFrame" -> {
                    val request = call.arguments as? Map<*, *>
                    result.success(optimizedVisionEngine.runFrame(request))
                }

                else -> result.notImplemented()
            }
        }
    }

    private fun registerFaceLandmarkerRuntime(flutterEngine: FlutterEngine) {
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "kslas.face_landmarker",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "initialize" -> {
                    val request = call.arguments as? Map<*, *>
                    result.success(faceLandmarkerChannel.initialize(request))
                }

                "analyseFrame" -> {
                    val request = call.arguments as? Map<*, *>
                    result.success(faceLandmarkerChannel.analyseFrame(request))
                }

                "analyseRgb" -> {
                    val request = call.arguments as? Map<*, *>
                    result.success(faceLandmarkerChannel.analyseRgb(request))
                }

                "status" -> result.success(faceLandmarkerChannel.status())

                else -> result.notImplemented()
            }
        }
    }
}

private class AndroidOptimizedVisionRuntimeEngine {
    private var env: OrtEnvironment? = null
    private var session: OrtSession? = null
    private var inputName: String = ""
    private var inputShape: LongArray = longArrayOf(1, 3, 416, 416)
    private var modelPath: String = ""
    private var backend: String = "not_available"
    private var precision: String = "not_available"
    private var outputLayout: String = "channels_first_yolov8"
    private var inputPreprocessing: String = "letterbox_rgb01"
    private var confidenceThreshold: Double = 0.45
    private var iouThreshold: Double = 0.45
    private var classNames: List<String> = defaultCocoClassNames()
    private var lastInferenceMs: Double = 0.0
    private var lastError: String =
        "Android ONNX Runtime has not been initialized."

    /** How a camera frame was placed in the model input (input pixels). */
    data class InputGeometry(
        val inputWidth: Int,
        val inputHeight: Int,
        val sourceWidth: Int,
        val sourceHeight: Int,
        val contentWidth: Int,
        val contentHeight: Int,
        val scaleX: Double,
        val scaleY: Double,
        val padX: Int,
        val padY: Int,
    )

    companion object {
        const val MAX_DETECTIONS = 50

        /**
         * Letterbox (aspect-preserving, centered, same placement as Ultralytics
         * LetterBox) or stretch placement. Mirrors the Windows C++ engine and
         * ai_runtime prepare-tensors letterbox_nn_rgb01.
         */
        fun computeInputGeometry(
            preprocessing: String,
            sourceWidth: Int,
            sourceHeight: Int,
            inputWidth: Int,
            inputHeight: Int,
        ): InputGeometry {
            val contentWidth: Int
            val contentHeight: Int
            if (preprocessing == "letterbox_rgb01") {
                val ratio = min(
                    inputWidth.toDouble() / sourceWidth,
                    inputHeight.toDouble() / sourceHeight,
                )
                contentWidth = floor(sourceWidth * ratio + 0.5).toInt().coerceIn(1, inputWidth)
                contentHeight = floor(sourceHeight * ratio + 0.5).toInt().coerceIn(1, inputHeight)
            } else {
                contentWidth = inputWidth
                contentHeight = inputHeight
            }
            return InputGeometry(
                inputWidth = inputWidth,
                inputHeight = inputHeight,
                sourceWidth = sourceWidth,
                sourceHeight = sourceHeight,
                contentWidth = contentWidth,
                contentHeight = contentHeight,
                scaleX = contentWidth.toDouble() / sourceWidth,
                scaleY = contentHeight.toDouble() / sourceHeight,
                padX = (inputWidth - contentWidth) / 2,
                padY = (inputHeight - contentHeight) / 2,
            )
        }
    }

    fun initialize(
        policy: Map<*, *>?,
        assets: AssetManager,
    ): Boolean {
        backend = policy.stringValue("backend", "onnxRuntimeCpu")
        precision = policy.stringValue("precision", "int8")
        outputLayout = policy.stringValue("output_layout", "channels_first_yolov8")
        inputPreprocessing = policy.stringValue("input_preprocessing", "letterbox_rgb01")
        confidenceThreshold = policy.doubleValue("confidence_threshold", 0.45)
        iouThreshold = policy.doubleValue("iou_threshold", 0.45)
        classNames = policy.stringListValue("class_names", defaultCocoClassNames())
        // The validated manifest defines the model contract; refuse unknown
        // preprocessing or layouts instead of guessing them.
        if (inputPreprocessing != "letterbox_rgb01" && inputPreprocessing != "stretch_rgb01") {
            session = null
            lastError = "Unsupported input_preprocessing in the model manifest: $inputPreprocessing"
            return false
        }
        if (outputLayout != "channels_first_yolov8" && outputLayout != "rows_yolov8") {
            session = null
            lastError = "Unsupported output_layout in the model manifest: $outputLayout"
            return false
        }
        return try {
            val assetPath = resolveAssetPath(policy)
            val assetKey = FlutterInjector.instance()
                .flutterLoader()
                .getLookupKeyForAsset(assetPath)
            val modelBytes = assets
                .open(assetKey)
                .use { it.readBytes() }
            val environment = OrtEnvironment.getEnvironment()
            val options = OrtSession.SessionOptions()
            options.setOptimizationLevel(OrtSession.SessionOptions.OptLevel.ALL_OPT)
            val createdSession = environment.createSession(modelBytes, options)
            val firstInput = createdSession.inputInfo.entries.first()
            val tensorInfo = firstInput.value.info as? TensorInfo
            inputName = firstInput.key
            inputShape = normalizeShape(
                tensorInfo?.shape ?: longArrayOf(1, 3, 416, 416),
                policy.intValue("max_input_height", policy.intValue("input_height", 416)),
                policy.intValue("max_input_width", policy.intValue("input_width", 416)),
            )
            env = environment
            session = createdSession
            modelPath = assetPath
            lastError = ""
            true
        } catch (error: Throwable) {
            session = null
            lastError = error.message ?: error.toString()
            false
        }
    }

    fun runFrame(request: Map<*, *>?): Map<String, Any?> {
        val activeEnv = env
        val activeSession = session
        if (activeEnv == null || activeSession == null || request == null) {
            return notAvailable(lastError)
        }
        return try {
            var response: Map<String, Any?>
            val elapsed = measureNanoTime {
                val (input, geometry) = buildInputTensor(request)
                OnnxTensor.createTensor(
                    activeEnv,
                    FloatBuffer.wrap(input),
                    inputShape,
                ).use { tensor ->
                    activeSession.run(mapOf(inputName to tensor)).use { outputs ->
                        response = availableResponse(outputs, request, geometry)
                    }
                }
            }
            lastInferenceMs = elapsed / 1_000_000.0
            response + ("inference_ms" to lastInferenceMs)
        } catch (error: Throwable) {
            lastError = error.message ?: error.toString()
            session = null
            notAvailable(lastError)
        }
    }

    private fun resolveAssetPath(policy: Map<*, *>?): String {
        val explicit = policy.stringValue("model_path", "")
        if (explicit.isNotBlank()) return explicit
        val explicitOnnx = policy.stringValue("onnx_path", "")
        if (explicitOnnx.isNotBlank()) return explicitOnnx
        val fileName = when (precision) {
            "fp16" -> "yolo_exam_review.fp16.onnx"
            "fp32Fallback" -> "yolo_exam_review.fp32.onnx"
            else -> "yolo_exam_review.int8.onnx"
        }
        return "assets/models/yolo_exam_review/$fileName"
    }

    private fun normalizeShape(
        rawShape: LongArray,
        targetHeight: Int,
        targetWidth: Int,
    ): LongArray {
        if (rawShape.size != 4) return longArrayOf(1, 3, targetHeight.toLong(), targetWidth.toLong())
        val shape = rawShape.copyOf()
        val nhwc = shape[3] == 3L || shape[3] == 1L
        shape[0] = 1
        if (nhwc) {
            if (shape[1] <= 0) shape[1] = targetHeight.toLong()
            if (shape[2] <= 0) shape[2] = targetWidth.toLong()
            if (shape[3] <= 0) shape[3] = 3
        } else {
            if (shape[1] <= 0) shape[1] = 3
            if (shape[2] <= 0) shape[2] = targetHeight.toLong()
            if (shape[3] <= 0) shape[3] = targetWidth.toLong()
        }
        return shape
    }

    private data class PlaneData(
        val bytes: ByteArray,
        val rowStride: Int,
        val pixelStride: Int,
    )

    private data class RgbPixel(
        val r: Int,
        val g: Int,
        val b: Int,
    )

    private fun buildInputTensor(request: Map<*, *>): Pair<FloatArray, InputGeometry> {
        val rawWidth = request.intValue("width", 0)
        val rawHeight = request.intValue("height", 0)
        if (rawWidth <= 0 || rawHeight <= 0) {
            throw IllegalArgumentException("Camera frame dimensions are invalid")
        }
        // Camera frames arrive in sensor orientation; rotation_degrees is the
        // clockwise turn that makes the scene upright. The model samples the
        // upright scene (on sideways frames it missed most phones and second
        // people), and geometry and boxes are reported in the upright frame.
        val rotation = ((request.intValue("rotation_degrees", 0) % 360) + 360) % 360
        val quarterTurn = rotation == 90 || rotation == 270
        val sourceWidth = if (quarterTurn) rawHeight else rawWidth
        val sourceHeight = if (quarterTurn) rawWidth else rawHeight
        val planes = request["planes"] as? List<*> ?: throw IllegalArgumentException("Missing planes")
        val planeData = planes.mapNotNull { item ->
            val plane = item as? Map<*, *> ?: return@mapNotNull null
            val bytes = plane["bytes"] as? ByteArray ?: return@mapNotNull null
            PlaneData(
                bytes = bytes,
                rowStride = plane.intValue("bytes_per_row", rawWidth).coerceAtLeast(1),
                pixelStride = plane.intValue("bytes_per_pixel", 1).coerceAtLeast(1),
            )
        }
        if (planeData.isEmpty()) throw IllegalArgumentException("Missing plane bytes")

        val format = request.stringValue("format", "").lowercase()
        val nchw = inputShape.size == 4 && inputShape[1] <= 4
        val targetHeight = (if (nchw) inputShape[2] else inputShape[1]).toInt()
        val targetWidth = (if (nchw) inputShape[3] else inputShape[2]).toInt()
        val channels = (if (nchw) inputShape[1] else inputShape[3]).toInt().coerceAtLeast(1)
        // Ultralytics YOLO is trained on letterboxed RGB scaled to [0, 1] with
        // grey (114) padding; nearest-neighbour sampling inside the content.
        val geometry = computeInputGeometry(
            inputPreprocessing,
            sourceWidth,
            sourceHeight,
            targetWidth,
            targetHeight,
        )
        val tensor = FloatArray(targetWidth * targetHeight * channels) { 114.0f / 255.0f }

        for (y in 0 until targetHeight) {
            val contentY = y - geometry.padY
            if (contentY < 0 || contentY >= geometry.contentHeight) continue
            val srcY = min(sourceHeight - 1, contentY * sourceHeight / geometry.contentHeight)
            for (x in 0 until targetWidth) {
                val contentX = x - geometry.padX
                if (contentX < 0 || contentX >= geometry.contentWidth) continue
                val srcX = min(sourceWidth - 1, contentX * sourceWidth / geometry.contentWidth)
                // (srcX, srcY) is in the upright scene; read the raw pixel.
                val rawX = when (rotation) {
                    90 -> srcY
                    180 -> rawWidth - 1 - srcX
                    270 -> rawWidth - 1 - srcY
                    else -> srcX
                }
                val rawY = when (rotation) {
                    90 -> rawHeight - 1 - srcX
                    180 -> rawHeight - 1 - srcY
                    270 -> srcX
                    else -> srcY
                }
                val pixel = readRgbPixel(
                    planes = planeData,
                    format = format,
                    sourceX = rawX,
                    sourceY = rawY,
                    sourceWidth = rawWidth,
                )
                for (channel in 0 until channels) {
                    val channelValue = when (channel) {
                        0 -> pixel.r
                        1 -> pixel.g
                        2 -> pixel.b
                        else -> pixel.r
                    }
                    val value = channelValue / 255.0f
                    val index = if (nchw) {
                        channel * targetHeight * targetWidth + y * targetWidth + x
                    } else {
                        (y * targetWidth + x) * channels + channel
                    }
                    if (index in tensor.indices) tensor[index] = value
                }
            }
        }
        return tensor to geometry
    }

    private fun readRgbPixel(
        planes: List<PlaneData>,
        format: String,
        sourceX: Int,
        sourceY: Int,
        sourceWidth: Int,
    ): RgbPixel {
        if (format == "rgb888" || format == "rgb") {
            return readPackedRgb(planes.first(), sourceX, sourceY, 3, redOffset = 0, greenOffset = 1, blueOffset = 2)
        }
        if (format == "bgra8888" || format == "bgra") {
            return readPackedRgb(planes.first(), sourceX, sourceY, 4, redOffset = 2, greenOffset = 1, blueOffset = 0)
        }
        if (format.contains("yuv") && planes.size >= 3) {
            return readYuv420(planes, sourceX, sourceY)
        }

        val yPlane = planes.first()
        val yIndex = sourceY * yPlane.rowStride + sourceX * yPlane.pixelStride
        val y = yPlane.bytes.safeByte(yIndex)
        return RgbPixel(y, y, y)
    }

    private fun readPackedRgb(
        plane: PlaneData,
        x: Int,
        y: Int,
        fallbackPixelWidth: Int,
        redOffset: Int,
        greenOffset: Int,
        blueOffset: Int,
    ): RgbPixel {
        val pixelWidth = max(plane.pixelStride, fallbackPixelWidth)
        val index = y * plane.rowStride + x * pixelWidth
        return RgbPixel(
            plane.bytes.safeByte(index + redOffset),
            plane.bytes.safeByte(index + greenOffset),
            plane.bytes.safeByte(index + blueOffset),
        )
    }

    private fun readYuv420(
        planes: List<PlaneData>,
        x: Int,
        y: Int,
    ): RgbPixel {
        val yPlane = planes[0]
        val uPlane = planes[1]
        val vPlane = planes[2]
        val yValue = yPlane.bytes.safeByte(y * yPlane.rowStride + x * yPlane.pixelStride)
        val chromaX = x / 2
        val chromaY = y / 2
        val uValue = uPlane.bytes.safeByte(chromaY * uPlane.rowStride + chromaX * uPlane.pixelStride)
        val vValue = vPlane.bytes.safeByte(chromaY * vPlane.rowStride + chromaX * vPlane.pixelStride)
        return yuvToRgb(yValue, uValue, vValue)
    }

    private fun yuvToRgb(yValue: Int, uValue: Int, vValue: Int): RgbPixel {
        val c = (yValue - 16).coerceAtLeast(0)
        val d = uValue - 128
        val e = vValue - 128
        val r = ((298 * c + 409 * e + 128) shr 8).coerceIn(0, 255)
        val g = ((298 * c - 100 * d - 208 * e + 128) shr 8).coerceIn(0, 255)
        val b = ((298 * c + 516 * d + 128) shr 8).coerceIn(0, 255)
        return RgbPixel(r, g, b)
    }

    private fun availableResponse(
        outputs: OrtSession.Result,
        request: Map<*, *>,
        geometry: InputGeometry,
    ): Map<String, Any?> {
        val summaries = mutableListOf<Map<String, Any?>>()
        var detections: List<Detection>? = null
        var rawYoloOutput: Map<String, Any?>? = null
        var index = 0
        for (entry in outputs) {
            val value = entry.value
            summaries.add(summarizeOutput(index, value))
            if (detections == null) {
                detections = decodeYoloV8(value, geometry)
                if (detections != null) rawYoloOutput = extractRawYoloOutput(value)
            }
            index++
        }
        // Fail closed: a model whose output does not match its manifest must
        // not produce detections.
        val decoded = detections ?: emptyList()
        val objects = decoded.map { it.toMap() }
        val personCount = decoded.count { it.label.contains("person") && it.confidence >= 0.40 }
        val screenGlow = decoded.any { it.label.isPhoneLike() }
        val mirrorReflection = decoded.any { it.label.isMirrorLike() }
        val offscreenInteraction = decoded.any { it.label.isOffscreenLike() }
        val outputMap = mutableMapOf<String, Any?>(
            "objects" to objects,
            "person_count" to personCount,
            "multiple_people_likely" to (personCount >= 2),
            "screen_glow" to screenGlow,
            "mirror_reflection" to mirrorReflection,
            "offscreen_interaction" to offscreenInteraction,
            "runtime" to backend,
            "precision" to precision,
            "inference_ms" to lastInferenceMs,
            "model_path" to modelPath,
            "model_family" to "yolo",
            "raw_outputs" to summaries,
            "class_names" to classNames,
            "num_classes" to classNames.size,
            "layout" to outputLayout,
            "output_layout" to outputLayout,
            "confidence_threshold" to confidenceThreshold,
            "iou_threshold" to iouThreshold,
            "image_width" to geometry.sourceWidth,
            "image_height" to geometry.sourceHeight,
            "input_width" to geometry.inputWidth,
            "input_height" to geometry.inputHeight,
            "input_preprocessing" to inputPreprocessing,
            "letterbox_scale_x" to geometry.scaleX,
            "letterbox_scale_y" to geometry.scaleY,
            "letterbox_pad_x" to geometry.padX.toDouble(),
            "letterbox_pad_y" to geometry.padY.toDouble(),
            "input_format" to request.stringValue("format", ""),
            "input_conversion" to inputPreprocessing,
            "requires_rust_decode" to true,
        )
        rawYoloOutput?.let { outputMap.putAll(it) }
        if (detections == null) {
            outputMap["message"] =
                "YOLO output does not match the model manifest (expected [1, ${4 + classNames.size}, N] for $outputLayout)."
        }
        return mapOf(
            "available" to (detections != null && rawYoloOutput != null),
            "backend" to backend,
            "precision" to precision,
            "inference_ms" to lastInferenceMs,
            "outputs" to outputMap,
        )
    }

    private fun extractRawYoloOutput(value: OnnxValue): Map<String, Any?>? {
        val tensor = value as? OnnxTensor ?: return null
        val info = tensor.info as? TensorInfo ?: return null
        if (info.type != ai.onnxruntime.OnnxJavaType.FLOAT) return null
        val shape = info.shape
        val data = tensor.floatBuffer
        val elementCount = shape.fold(1L) { acc, dim -> acc * max(1L, dim) }
        if (elementCount <= 0 || elementCount > Int.MAX_VALUE) return null
        val output = List(elementCount.toInt()) { index -> data.get(index).toDouble() }
        val predictionCount = inferPredictionCount(shape, output.size)
        if (predictionCount <= 0) return null
        return mapOf(
            "yolo_output" to output,
            "num_predictions" to predictionCount,
            "num_classes" to classNames.size,
            "class_names" to classNames,
            "layout" to outputLayout,
            "output_layout" to outputLayout,
            "confidence_threshold" to confidenceThreshold,
            "iou_threshold" to iouThreshold,
        )
    }

    private fun inferPredictionCount(shape: LongArray, outputLength: Int): Int {
        val classCount = classNames.size
        val attributesV8 = 4 + classCount
        val attributesV5 = 5 + classCount
        if (shape.size == 3) {
            val dim1 = shape[1].toInt()
            val dim2 = shape[2].toInt()
            if (outputLayout == "channels_first_yolov8" && dim1 == attributesV8) return dim2
            if (dim2 == attributesV8 || dim2 == attributesV5) return dim1
            if (dim1 == attributesV8 || dim1 == attributesV5) return dim2
        }
        if (outputLayout == "rows_yolov5" && outputLength % attributesV5 == 0) {
            return outputLength / attributesV5
        }
        if (outputLength % attributesV8 == 0) return outputLength / attributesV8
        return 0
    }

    /**
     * Strict YOLOv8 decode against the manifest contract: shape [1, 4 + C, N]
     * (channels_first_yolov8) or [1, N, 4 + C] (rows_yolov8), class
     * probabilities, pixel cx/cy/w/h in model-input space. Boxes are mapped to
     * normalized source-frame coordinates, clipped, and class-aware greedy NMS
     * is applied. Returns null when the tensor does not match the manifest.
     */
    private fun decodeYoloV8(value: OnnxValue, geometry: InputGeometry): List<Detection>? {
        val tensor = value as? OnnxTensor ?: return null
        val info = tensor.info as? TensorInfo ?: return null
        if (info.type != ai.onnxruntime.OnnxJavaType.FLOAT) return null
        val shape = info.shape
        val numClasses = classNames.size
        val attributes = 4 + numClasses
        if (numClasses <= 0 || shape.size != 3 || shape[0] != 1L) return null
        if (geometry.contentWidth <= 0 || geometry.contentHeight <= 0) return null
        val channelsFirst = outputLayout == "channels_first_yolov8"
        if (!channelsFirst && outputLayout != "rows_yolov8") return null
        val predictions = (if (channelsFirst) shape[2] else shape[1]).toInt()
        val reportedAttributes = (if (channelsFirst) shape[1] else shape[2]).toInt()
        if (reportedAttributes != attributes || predictions <= 0) return null
        val data = tensor.floatBuffer
        if (data.remaining() != attributes * predictions) return null
        fun at(prediction: Int, attribute: Int): Double = data.get(
            if (channelsFirst) attribute * predictions + prediction else prediction * attributes + attribute,
        ).toDouble()

        val candidates = mutableListOf<Detection>()
        for (prediction in 0 until predictions) {
            var bestClass = -1
            var bestScore = 0.0
            for (classIndex in 0 until numClasses) {
                val score = at(prediction, 4 + classIndex)
                if (score > bestScore) {
                    bestScore = score
                    bestClass = classIndex
                }
            }
            if (bestClass < 0 || bestScore < confidenceThreshold) continue
            val cx = at(prediction, 0)
            val cy = at(prediction, 1)
            val w = abs(at(prediction, 2))
            val h = abs(at(prediction, 3))
            val x1 = ((cx - w / 2.0 - geometry.padX) / geometry.contentWidth).coerceIn(0.0, 1.0)
            val y1 = ((cy - h / 2.0 - geometry.padY) / geometry.contentHeight).coerceIn(0.0, 1.0)
            val x2 = ((cx + w / 2.0 - geometry.padX) / geometry.contentWidth).coerceIn(0.0, 1.0)
            val y2 = ((cy + h / 2.0 - geometry.padY) / geometry.contentHeight).coerceIn(0.0, 1.0)
            if (!(x2 > x1) || !(y2 > y1)) continue
            candidates.add(
                Detection(
                    x1 = x1,
                    y1 = y1,
                    x2 = x2,
                    y2 = y2,
                    confidence = bestScore.coerceIn(0.0, 1.0),
                    classId = bestClass.toLong(),
                    label = classNames[bestClass],
                ),
            )
        }
        val kept = mutableListOf<Detection>()
        for (candidate in candidates.sortedByDescending { it.confidence }) {
            val suppressed = kept.any {
                it.classId == candidate.classId && it.iou(candidate) > iouThreshold
            }
            if (suppressed) continue
            kept.add(candidate)
            if (kept.size >= MAX_DETECTIONS) break
        }
        return kept
    }

    private fun summarizeOutput(index: Int, value: OnnxValue): Map<String, Any?> {
        val info = value.info as? TensorInfo
        val sample = if (value is OnnxTensor && info?.type == ai.onnxruntime.OnnxJavaType.FLOAT) {
            val data = value.floatBuffer
            val limit = min(data.remaining(), 16)
            List(limit) { data.get(it).toDouble() }
        } else {
            emptyList<Double>()
        }
        return mapOf(
            "name" to "output_$index",
            "shape" to (info?.shape?.map { it } ?: emptyList<Long>()),
            "element_count" to (info?.shape?.fold(1L) { acc, dim -> acc * max(1L, dim) } ?: 0L),
            "sample" to sample,
        )
    }

    private fun notAvailable(message: String): Map<String, Any?> = mapOf(
        "available" to false,
        "backend" to backend,
        "precision" to precision,
        "inference_ms" to lastInferenceMs,
        "outputs" to mapOf(
            "message" to message,
            "model_path" to modelPath,
            "model_family" to "yolo",
            "requires_real_model" to true,
            "class_names" to classNames,
            "num_classes" to classNames.size,
            "layout" to outputLayout,
        ),
    )
}

private data class Detection(
    val x1: Double,
    val y1: Double,
    val x2: Double,
    val y2: Double,
    val confidence: Double,
    val classId: Long,
    val label: String,
) {
    fun toMap(): Map<String, Any?> = mapOf(
        "label" to label,
        "class_id" to classId,
        "confidence" to confidence.coerceIn(0.0, 1.0),
        "box" to mapOf(
            "x1" to x1.coerceIn(0.0, 1.0),
            "y1" to y1.coerceIn(0.0, 1.0),
            "x2" to x2.coerceIn(0.0, 1.0),
            "y2" to y2.coerceIn(0.0, 1.0),
        ),
    )

    fun iou(other: Detection): Double {
        val overlapX = max(0.0, min(x2, other.x2) - max(x1, other.x1))
        val overlapY = max(0.0, min(y2, other.y2) - max(y1, other.y1))
        val overlap = overlapX * overlapY
        val area = (x2 - x1) * (y2 - y1) + (other.x2 - other.x1) * (other.y2 - other.y1) - overlap
        return if (area > 0.0) overlap / area else 0.0
    }
}

private fun ByteArray.safeByte(index: Int): Int {
    if (index < 0 || index >= size) return 0
    return this[index].toInt() and 0xff
}

private val phoneLikeLabels = setOf("cell phone", "phone", "mobile phone", "smartphone", "remote")
private val mirrorLikeLabels = setOf("mirror", "reflection")
private val offscreenLikeLabels = setOf("hand", "offscreen interaction", "offscreen_interaction")

private fun String.isPhoneLike(): Boolean = trim().lowercase() in phoneLikeLabels

private fun String.isMirrorLike(): Boolean = trim().lowercase() in mirrorLikeLabels

private fun String.isOffscreenLike(): Boolean = trim().lowercase() in offscreenLikeLabels

private fun Map<*, *>?.stringValue(key: String, fallback: String): String {
    return this?.get(key)?.toString() ?: fallback
}

private fun Map<*, *>?.intValue(key: String, fallback: Int): Int {
    val value = this?.get(key) ?: return fallback
    return when (value) {
        is Int -> value
        is Long -> value.toInt()
        is Double -> value.toInt()
        is Float -> value.toInt()
        is Number -> value.toInt()
        else -> value.toString().toIntOrNull() ?: fallback
    }
}

private fun Map<*, *>?.doubleValue(key: String, fallback: Double): Double {
    val value = this?.get(key) ?: return fallback
    return when (value) {
        is Double -> value
        is Float -> value.toDouble()
        is Int -> value.toDouble()
        is Long -> value.toDouble()
        is Number -> value.toDouble()
        else -> value.toString().toDoubleOrNull() ?: fallback
    }
}

private fun Map<*, *>?.stringListValue(key: String, fallback: List<String>): List<String> {
    val value = this?.get(key) ?: return fallback
    if (value !is Iterable<*>) return fallback
    val items = value.mapNotNull { item -> item?.toString()?.trim() }.filter { it.isNotEmpty() }
    return items.ifEmpty { fallback }
}

private fun defaultCocoClassNames(): List<String> = listOf(
    "person", "bicycle", "car", "motorcycle", "airplane", "bus", "train", "truck", "boat",
    "traffic light", "fire hydrant", "stop sign", "parking meter", "bench", "bird", "cat", "dog",
    "horse", "sheep", "cow", "elephant", "bear", "zebra", "giraffe", "backpack", "umbrella",
    "handbag", "tie", "suitcase", "frisbee", "skis", "snowboard", "sports ball", "kite",
    "baseball bat", "baseball glove", "skateboard", "surfboard", "tennis racket", "bottle",
    "wine glass", "cup", "fork", "knife", "spoon", "bowl", "banana", "apple", "sandwich",
    "orange", "broccoli", "carrot", "hot dog", "pizza", "donut", "cake", "chair", "couch",
    "potted plant", "bed", "dining table", "toilet", "tv", "laptop", "mouse", "remote",
    "keyboard", "cell phone", "microwave", "oven", "toaster", "sink", "refrigerator", "book",
    "clock", "vase", "scissors", "teddy bear", "hair drier", "toothbrush",
)

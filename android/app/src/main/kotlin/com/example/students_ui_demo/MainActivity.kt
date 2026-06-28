package com.example.students_ui_demo

import ai.onnxruntime.OnnxTensor
import ai.onnxruntime.OnnxValue
import ai.onnxruntime.OrtEnvironment
import ai.onnxruntime.OrtSession
import ai.onnxruntime.TensorInfo
import android.content.res.AssetManager
import io.flutter.FlutterInjector
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.nio.FloatBuffer
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToLong
import kotlin.system.measureNanoTime

class MainActivity : FlutterActivity() {
    private val optimizedVisionEngine = AndroidOptimizedVisionRuntimeEngine()
    private val faceLandmarkerChannel by lazy { AndroidFaceLandmarkerChannel(this) }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        registerOptimizedVisionRuntime(flutterEngine)
        registerFaceLandmarkerRuntime(flutterEngine)
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
    private var confidenceThreshold: Double = 0.45
    private var iouThreshold: Double = 0.45
    private var classNames: List<String> = defaultCocoClassNames()
    private var lastInferenceMs: Double = 0.0
    private var lastError: String =
        "Android ONNX Runtime has not been initialized."

    fun initialize(
        policy: Map<*, *>?,
        assets: AssetManager,
    ): Boolean {
        backend = policy.stringValue("backend", "onnxRuntimeCpu")
        precision = policy.stringValue("precision", "int8")
        outputLayout = policy.stringValue("output_layout", "channels_first_yolov8")
        confidenceThreshold = policy.doubleValue("confidence_threshold", 0.45)
        iouThreshold = policy.doubleValue("iou_threshold", 0.45)
        classNames = policy.stringListValue("class_names", defaultCocoClassNames())
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
                val input = buildInputTensor(request)
                OnnxTensor.createTensor(
                    activeEnv,
                    FloatBuffer.wrap(input),
                    inputShape,
                ).use { tensor ->
                    activeSession.run(mapOf(inputName to tensor)).use { outputs ->
                        response = availableResponse(outputs, request)
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

    private fun buildInputTensor(request: Map<*, *>): FloatArray {
        val sourceWidth = request.intValue("width", 0)
        val sourceHeight = request.intValue("height", 0)
        val planes = request["planes"] as? List<*> ?: throw IllegalArgumentException("Missing planes")
        val firstPlane = planes.firstOrNull() as? Map<*, *>
            ?: throw IllegalArgumentException("Malformed first plane")
        val bytes = firstPlane["bytes"] as? ByteArray
            ?: throw IllegalArgumentException("Missing plane bytes")
        val rowStride = firstPlane.intValue("bytes_per_row", sourceWidth)
        val bytesPerPixel = firstPlane.intValue("bytes_per_pixel", 1).coerceAtLeast(1)
        val format = request.stringValue("format", "")
        val rgb888 = format == "rgb888" || format == "rgb"
        val bgra8888 = format == "bgra8888" || format == "bgra"
        val nchw = inputShape.size == 4 && inputShape[1] <= 4
        val targetHeight = (if (nchw) inputShape[2] else inputShape[1]).toInt()
        val targetWidth = (if (nchw) inputShape[3] else inputShape[2]).toInt()
        val channels = (if (nchw) inputShape[1] else inputShape[3]).toInt().coerceAtLeast(1)
        val tensor = FloatArray(targetWidth * targetHeight * channels)

        for (y in 0 until targetHeight) {
            val srcY = min(sourceHeight - 1, y * sourceHeight / targetHeight)
            for (x in 0 until targetWidth) {
                val srcX = min(sourceWidth - 1, x * sourceWidth / targetWidth)
                val pixelWidth = if (rgb888) 3 else bytesPerPixel
                val sourceIndex = srcY * rowStride + srcX * pixelWidth
                if (sourceIndex < 0 || sourceIndex >= bytes.size) continue
                for (channel in 0 until channels) {
                    val channelIndex = if (rgb888) {
                        sourceIndex + min(channel, 2)
                    } else if (bgra8888) {
                        sourceIndex + (2 - min(channel, 2))
                    } else {
                        sourceIndex
                    }
                    if (channelIndex < 0 || channelIndex >= bytes.size) continue
                    val value = (((bytes[channelIndex].toInt() and 0xff) / 255.0f) - 0.5f) / 0.5f
                    val index = if (nchw) {
                        channel * targetHeight * targetWidth + y * targetWidth + x
                    } else {
                        (y * targetWidth + x) * channels + channel
                    }
                    if (index in tensor.indices) tensor[index] = value
                }
            }
        }
        return tensor
    }

    private fun availableResponse(
        outputs: OrtSession.Result,
        request: Map<*, *>,
    ): Map<String, Any?> {
        val summaries = mutableListOf<Map<String, Any?>>()
        val detections = mutableListOf<Detection>()
        var rawYoloOutput: Map<String, Any?>? = null
        var index = 0
        for (entry in outputs) {
            val value = entry.value
            summaries.add(summarizeOutput(index, value))
            detections.addAll(parseDetections(value))
            if (rawYoloOutput == null) {
                rawYoloOutput = extractRawYoloOutput(value)
            }
            index++
        }
        val sortedDetections = detections.sortedByDescending { it.confidence }.take(20)
        val objects = sortedDetections.map { it.toMap() }
        val screenGlow = sortedDetections.any { it.label.isPhoneLike() }
        val mirrorReflection = sortedDetections.any { it.label.isMirrorLike() }
        val offscreenInteraction = sortedDetections.any { it.label.isOffscreenLike() }
        val sourceWidth = request.intValue("width", 0)
        val sourceHeight = request.intValue("height", 0)
        val outputMap = mutableMapOf<String, Any?>(
            "objects" to objects,
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
            "image_width" to sourceWidth,
            "image_height" to sourceHeight,
            "requires_rust_decode" to true,
        )
        rawYoloOutput?.let { outputMap.putAll(it) }
        return mapOf(
            "available" to (rawYoloOutput != null),
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
            "raw_yolo_output" to output,
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

    private fun parseDetections(value: OnnxValue): List<Detection> {
        val tensor = value as? OnnxTensor ?: return emptyList()
        val info = tensor.info as? TensorInfo ?: return emptyList()
        if (info.type != ai.onnxruntime.OnnxJavaType.FLOAT) return emptyList()
        val shape = info.shape
        val data = tensor.floatBuffer
        val detections = mutableListOf<Detection>()
        if (shape.size == 2 && shape[1] >= 6) {
            val rows = shape[0].toInt()
            val columns = shape[1].toInt()
            for (row in 0 until rows) {
                detections.decodeCandidate(FloatArray(columns) { col ->
                    data.get(row * columns + col)
                }, classNames)
            }
        } else if (shape.size == 3) {
            val dim1 = shape[1].toInt()
            val dim2 = shape[2].toInt()
            if (dim2 >= 6) {
                for (row in 0 until dim1) {
                    detections.decodeCandidate(FloatArray(dim2) { col ->
                        data.get(row * dim2 + col)
                    }, classNames)
                }
            } else if (dim1 >= 6) {
                for (row in 0 until dim2) {
                    detections.decodeCandidate(FloatArray(dim1) { col ->
                        data.get(col * dim2 + row)
                    }, classNames)
                }
            }
        }
        return detections
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
}

private fun MutableList<Detection>.decodeCandidate(values: FloatArray, classNames: List<String>) {
    if (values.size < 6) return
    var confidence = 0.0
    var classId = -1L
    if (values.size == 6) {
        confidence = values[4].logistic()
        classId = values[5].roundToLong()
    } else {
        val yolov5Layout = values.size == 85 || values.size == 10
        val classStart = if (yolov5Layout) 5 else 4
        val objectness = if (yolov5Layout) values[4].logistic() else 1.0
        for (index in classStart until values.size) {
            val score = values[index].logistic() * objectness
            if (score > confidence) {
                confidence = score
                classId = (index - classStart).toLong()
            }
        }
    }
    if (confidence < 0.35 || classId < 0) return

    val a = values[0].toDouble()
    val b = values[1].toDouble()
    val c = values[2].toDouble()
    val d = values[3].toDouble()
    val box = if (a >= 0.0 && b >= 0.0 && c <= 1.5 && d <= 1.5) {
        if (c > a && d > b) {
            doubleArrayOf(a, b, c, d)
        } else {
            doubleArrayOf(a - c / 2.0, b - d / 2.0, a + c / 2.0, b + d / 2.0)
        }
    } else {
        val scale = maxOf(1.0, kotlin.math.abs(a), kotlin.math.abs(b), kotlin.math.abs(c), kotlin.math.abs(d))
        doubleArrayOf((a - c / 2.0) / scale, (b - d / 2.0) / scale, (a + c / 2.0) / scale, (b + d / 2.0) / scale)
    }
    add(
        Detection(
            x1 = box[0],
            y1 = box[1],
            x2 = box[2],
            y2 = box[3],
            confidence = confidence.coerceIn(0.0, 1.0),
            classId = classId,
            label = classNames.getOrNull(classId.toInt()) ?: classId.labelForClass(),
        ),
    )
}

private fun Float.logistic(): Double {
    val value = toDouble()
    if (value in 0.0..1.0) return value
    return 1.0 / (1.0 + kotlin.math.exp(-value))
}

private fun Long.labelForClass(): String = when (this) {
    0L -> "person"
    63L -> "laptop"
    67L -> "cell phone"
    73L -> "book"
    else -> "class_$this"
}

private fun String.isPhoneLike(): Boolean {
    return contains("phone") || contains("mobile") || contains("screen")
}

private fun String.isMirrorLike(): Boolean {
    return contains("mirror") || contains("glass") || contains("reflection")
}

private fun String.isOffscreenLike(): Boolean {
    return contains("offscreen") || contains("interaction") || contains("hand")
}

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

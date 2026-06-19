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
import kotlin.system.measureNanoTime

class MainActivity : FlutterActivity() {
    private val optimizedVisionEngine = AndroidOptimizedVisionRuntimeEngine()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
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
}

private class AndroidOptimizedVisionRuntimeEngine {
    private var env: OrtEnvironment? = null
    private var session: OrtSession? = null
    private var inputName: String = ""
    private var inputShape: LongArray = longArrayOf(1, 3, 416, 416)
    private var modelPath: String = ""
    private var backend: String = "not_available"
    private var precision: String = "not_available"
    private var lastInferenceMs: Double = 0.0
    private var lastError: String =
        "Android ONNX Runtime has not been initialized."

    fun initialize(
        policy: Map<*, *>?,
        assets: AssetManager,
    ): Boolean {
        backend = policy.stringValue("backend", "onnxRuntimeCpu")
        precision = policy.stringValue("precision", "int8")
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
                policy.intValue("max_input_height", 416),
                policy.intValue("max_input_width", 416),
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
                        response = availableResponse(outputs)
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
        val fileName = if (precision == "fp16") {
            "object_reflection_shadow_detector.fp16.onnx"
        } else {
            "object_reflection_shadow_detector.int8.onnx"
        }
        return "assets/models/optimized_vision_runtime/$fileName"
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
        val nchw = inputShape.size == 4 && inputShape[1] <= 4
        val targetHeight = (if (nchw) inputShape[2] else inputShape[1]).toInt()
        val targetWidth = (if (nchw) inputShape[3] else inputShape[2]).toInt()
        val channels = (if (nchw) inputShape[1] else inputShape[3]).toInt().coerceAtLeast(1)
        val tensor = FloatArray(targetWidth * targetHeight * channels)

        for (y in 0 until targetHeight) {
            val srcY = min(sourceHeight - 1, y * sourceHeight / targetHeight)
            for (x in 0 until targetWidth) {
                val srcX = min(sourceWidth - 1, x * sourceWidth / targetWidth)
                val sourceIndex = srcY * rowStride + srcX
                if (sourceIndex < 0 || sourceIndex >= bytes.size) continue
                val value = (((bytes[sourceIndex].toInt() and 0xff) / 255.0f) - 0.5f) / 0.5f
                for (channel in 0 until channels) {
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

    private fun availableResponse(outputs: OrtSession.Result): Map<String, Any?> {
        val summaries = mutableListOf<Map<String, Any?>>()
        var index = 0
        for (entry in outputs) {
            summaries.add(summarizeOutput(index, entry.value))
            index++
        }
        return mapOf(
            "available" to true,
            "backend" to backend,
            "precision" to precision,
            "inference_ms" to lastInferenceMs,
            "outputs" to mapOf(
                "model_path" to modelPath,
                "raw_outputs" to summaries,
            ),
        )
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
        ),
    )
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

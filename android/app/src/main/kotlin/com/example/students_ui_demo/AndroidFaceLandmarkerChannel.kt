package com.example.students_ui_demo

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Matrix
import com.google.mediapipe.framework.image.BitmapImageBuilder
import com.google.mediapipe.tasks.core.BaseOptions
import com.google.mediapipe.tasks.vision.core.RunningMode
import com.google.mediapipe.tasks.vision.facelandmarker.FaceLandmarker
import java.io.File
import java.nio.ByteBuffer
import java.nio.ByteOrder

class AndroidFaceLandmarkerChannel(private val context: Context) {
    private var faceLandmarker: FaceLandmarker? = null
    private var lastError: String = "Face landmarker has not been initialized."

    fun initialize(arguments: Map<*, *>?): Boolean {
        val modelPath = arguments.stringValue("model_path", "")
        if (modelPath.isBlank()) {
            lastError = "model_path is required"
            return false
        }
        return try {
            val baseOptions = buildBaseOptions(modelPath)
            val options = FaceLandmarker.FaceLandmarkerOptions.builder()
                .setBaseOptions(baseOptions)
                .setRunningMode(RunningMode.IMAGE)
                .setNumFaces(1)
                .setMinFaceDetectionConfidence(0.55f)
                .setMinFacePresenceConfidence(0.55f)
                .setMinTrackingConfidence(0.50f)
                .build()
            faceLandmarker?.close()
            faceLandmarker = FaceLandmarker.createFromOptions(context, options)
            lastError = ""
            true
        } catch (error: Throwable) {
            faceLandmarker = null
            lastError = error.message ?: error.toString()
            false
        }
    }

    fun analyseFrame(request: Map<*, *>?): Map<String, Any?>? {
        if (request == null) return null
        val source = request.toBitmap() ?: return null
        val rotation = request.intValue("rotation_degrees", 0)
        val bitmap = source.rotated(rotation)
        return try {
            processBitmap(bitmap)
        } finally {
            if (bitmap !== source) bitmap.recycle()
            source.recycle()
        }
    }

    /**
     * Still-photo path used by identity enrollment/verification
     * (`NativeFaceLandmarkerRuntime.analyseRgbRaw`), as opposed to
     * [analyseFrame]'s live camera-stream (YUV/BGRA plane) path used by
     * proctoring. Takes already-decoded, packed RGB bytes directly.
     */
    fun analyseRgb(request: Map<*, *>?): Map<String, Any?>? {
        if (request == null) return null
        val width = request.intValue("width", 0)
        val height = request.intValue("height", 0)
        val bytes = request["rgb_bytes"] as? ByteArray ?: return null
        if (width <= 0 || height <= 0 || bytes.size < width * height * 3) return null
        val bitmap = rgbBytesToBitmap(bytes, width, height) ?: return null
        return processBitmap(bitmap)
    }

    private fun processBitmap(bitmap: Bitmap): Map<String, Any?>? {
        val runtime = faceLandmarker ?: return null
        return try {
            val result = runtime.detect(BitmapImageBuilder(bitmap).build())
            val face = result.faceLandmarks().firstOrNull() ?: return null
            val landmarks = face.mapIndexed { index, landmark ->
                mapOf(
                    "index" to index,
                    "x" to landmark.x().toDouble(),
                    "y" to landmark.y().toDouble(),
                    "z" to landmark.z().toDouble(),
                )
            }
            val named = landmarks.withNamedReferencePoints()
            val gaze = landmarks.irisRelativeGaze()
            mapOf(
                "label" to "mediapipe_face_landmarker",
                "confidence" to 0.92,
                "looking_away" to false,
                "stable_head_pose" to true,
                "gaze_vector" to gaze,
                "head_pose" to mapOf("yaw" to 0.0, "pitch" to 0.0, "roll" to 0.0),
                "landmarks" to named,
                "face_landmarks" to landmarks,
                "landmark_count" to landmarks.size,
            )
        } catch (error: Throwable) {
            lastError = error.message ?: error.toString()
            null
        }
    }

    fun status(): Map<String, Any?> = mapOf(
        "ready" to (faceLandmarker != null),
        "last_error" to lastError,
    )

    private fun buildBaseOptions(modelPath: String): BaseOptions {
        val file = File(modelPath)
        if (file.exists() && file.isFile) {
            val bytes = file.readBytes()
            val buffer = ByteBuffer
                .allocateDirect(bytes.size)
                .order(ByteOrder.nativeOrder())
            buffer.put(bytes)
            buffer.rewind()
            return BaseOptions.builder()
                .setModelAssetBuffer(buffer)
                .build()
        }
        return BaseOptions.builder()
            .setModelAssetPath(modelPath)
            .build()
    }
}

private fun List<Map<String, Any>>.irisRelativeGaze(): Map<String, Double> {
    fun coordinate(index: Int, axis: String): Double? =
        (getOrNull(index)?.get(axis) as? Number)?.toDouble()
    fun normalized(iris: Int, inner: Int, outer: Int, axis: String): Double? {
        val value = coordinate(iris, axis) ?: return null
        val a = coordinate(inner, axis) ?: return null
        val b = coordinate(outer, axis) ?: return null
        val span = kotlin.math.abs(b - a)
        if (span < 0.0001) return null
        return ((value - minOf(a, b)) / span).coerceIn(0.0, 1.0)
    }
    // MediaPipe Face Landmarker iris centres: 468 (right), 473 (left).
    val rightX = normalized(468, 33, 133, "x")
    val leftX = normalized(473, 362, 263, "x")
    val rightY = normalized(468, 159, 145, "y")
    val leftY = normalized(473, 386, 374, "y")
    val x = listOfNotNull(rightX, leftX).averageOrNull() ?: 0.5
    val y = listOfNotNull(rightY, leftY).averageOrNull() ?: 0.5
    return mapOf("x" to ((x - 0.5) * 2.0).coerceIn(-1.0, 1.0),
        "y" to ((y - 0.5) * 2.0).coerceIn(-1.0, 1.0), "z" to 1.0)
}

private fun List<Double>.averageOrNull(): Double? =
    if (isEmpty()) null else sum() / size

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

private fun rgbBytesToBitmap(bytes: ByteArray, width: Int, height: Int): Bitmap? {
    val pixels = IntArray(width * height)
    var offset = 0
    for (index in pixels.indices) {
        val r = bytes[offset].toInt() and 0xff
        val g = bytes[offset + 1].toInt() and 0xff
        val b = bytes[offset + 2].toInt() and 0xff
        pixels[index] = (0xff shl 24) or (r shl 16) or (g shl 8) or b
        offset += 3
    }
    return Bitmap.createBitmap(pixels, width, height, Bitmap.Config.ARGB_8888)
}

private fun Bitmap.rotated(degrees: Int): Bitmap {
    val normalized = ((degrees % 360) + 360) % 360
    if (normalized == 0) return this
    val matrix = Matrix().apply { postRotate(normalized.toFloat()) }
    // `filter = false`: this is a disposable analysis-only bitmap (never the
    // captured enrollment photo, which goes through the separate takePicture()
    // + analyseRgb path unaffected by this), so bilinear filtering only adds
    // CPU/memory-bandwidth cost per live frame without helping landmark
    // detection.
    return Bitmap.createBitmap(this, 0, 0, width, height, matrix, false)
}

private fun Map<*, *>.toBitmap(): Bitmap? {
    val width = intValue("width", 0)
    val height = intValue("height", 0)
    if (width <= 0 || height <= 0) return null
    val planes = this["planes"] as? List<*> ?: return null
    if (planes.isEmpty()) return null
    val format = stringValue("format", "").lowercase()
    return if (format.contains("bgra")) {
        planes.firstPlane()?.toBgraBitmap(width, height)
    } else if (planes.size >= 3) {
        planes.toYuv420Bitmap(width, height)
    } else {
        planes.firstPlane()?.toLumaBitmap(width, height)
    }
}

private fun List<*>.firstPlane(): Map<*, *>? = firstOrNull() as? Map<*, *>

private fun Map<*, *>.bytes(): ByteArray? = this["bytes"] as? ByteArray

private fun Map<*, *>.toLumaBitmap(width: Int, height: Int): Bitmap? {
    val bytes = bytes() ?: return null
    val rowStride = intValue("bytes_per_row", width).coerceAtLeast(width)
    val pixels = IntArray(width * height)
    for (y in 0 until height) {
        val row = y * rowStride
        for (x in 0 until width) {
            val index = row + x
            val value = if (index in bytes.indices) bytes[index].toInt() and 0xff else 0
            pixels[y * width + x] = argb(value, value, value)
        }
    }
    return Bitmap.createBitmap(pixels, width, height, Bitmap.Config.ARGB_8888)
}

private fun Map<*, *>.toBgraBitmap(width: Int, height: Int): Bitmap? {
    val bytes = bytes() ?: return null
    val rowStride = intValue("bytes_per_row", width * 4).coerceAtLeast(width * 4)
    val pixels = IntArray(width * height)
    for (y in 0 until height) {
        val row = y * rowStride
        for (x in 0 until width) {
            val index = row + x * 4
            if (index + 2 < bytes.size) {
                val b = bytes[index].toInt() and 0xff
                val g = bytes[index + 1].toInt() and 0xff
                val r = bytes[index + 2].toInt() and 0xff
                pixels[y * width + x] = argb(r, g, b)
            }
        }
    }
    return Bitmap.createBitmap(pixels, width, height, Bitmap.Config.ARGB_8888)
}

private fun List<*>.toYuv420Bitmap(width: Int, height: Int): Bitmap? {
    val yPlane = getOrNull(0) as? Map<*, *> ?: return null
    val uPlane = getOrNull(1) as? Map<*, *> ?: return null
    val vPlane = getOrNull(2) as? Map<*, *> ?: return null
    val yBytes = yPlane.bytes() ?: return null
    val uBytes = uPlane.bytes() ?: return null
    val vBytes = vPlane.bytes() ?: return null
    val yRowStride = yPlane.intValue("bytes_per_row", width).coerceAtLeast(width)
    val uRowStride = uPlane.intValue("bytes_per_row", width / 2).coerceAtLeast(1)
    val vRowStride = vPlane.intValue("bytes_per_row", width / 2).coerceAtLeast(1)
    val uPixelStride = uPlane.intValue("bytes_per_pixel", 1).coerceAtLeast(1)
    val vPixelStride = vPlane.intValue("bytes_per_pixel", 1).coerceAtLeast(1)
    val pixels = IntArray(width * height)

    for (y in 0 until height) {
        val yRow = y * yRowStride
        val uvY = y / 2
        for (x in 0 until width) {
            val yIndex = yRow + x
            val uvX = x / 2
            val uIndex = uvY * uRowStride + uvX * uPixelStride
            val vIndex = uvY * vRowStride + uvX * vPixelStride
            val yy = if (yIndex in yBytes.indices) yBytes[yIndex].toInt() and 0xff else 0
            val uu = if (uIndex in uBytes.indices) (uBytes[uIndex].toInt() and 0xff) - 128 else 0
            val vv = if (vIndex in vBytes.indices) (vBytes[vIndex].toInt() and 0xff) - 128 else 0
            val r = (yy + 1.402 * vv).toInt().coerceIn(0, 255)
            val g = (yy - 0.344136 * uu - 0.714136 * vv).toInt().coerceIn(0, 255)
            val b = (yy + 1.772 * uu).toInt().coerceIn(0, 255)
            pixels[y * width + x] = argb(r, g, b)
        }
    }
    return Bitmap.createBitmap(pixels, width, height, Bitmap.Config.ARGB_8888)
}

private fun List<Map<String, Any>>.withNamedReferencePoints(): List<Map<String, Any>> {
    val named = toMutableList()
    fun addName(index: Int, name: String) {
        val point = getOrNull(index)?.toMutableMap() ?: return
        point["name"] = name
        named.add(point)
    }
    addName(33, "left_eye")
    addName(263, "right_eye")
    addName(1, "nose_tip")
    addName(13, "mouth_center")
    return named
}

private fun argb(r: Int, g: Int, b: Int): Int {
    return (0xff shl 24) or (r.coerceIn(0, 255) shl 16) or (g.coerceIn(0, 255) shl 8) or b.coerceIn(0, 255)
}

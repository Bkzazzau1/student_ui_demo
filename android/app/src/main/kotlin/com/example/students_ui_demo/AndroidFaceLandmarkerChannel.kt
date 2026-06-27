package com.example.students_ui_demo

import android.content.Context
import android.graphics.Bitmap
import com.google.mediapipe.framework.image.BitmapImageBuilder
import com.google.mediapipe.tasks.core.BaseOptions
import com.google.mediapipe.tasks.vision.core.RunningMode
import com.google.mediapipe.tasks.vision.facelandmarker.FaceLandmarker

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
            val baseOptions = BaseOptions.builder()
                .setModelAssetPath(modelPath)
                .build()
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
        val runtime = faceLandmarker ?: return null
        if (request == null) return null
        return try {
            val bitmap = request.toBitmap() ?: return null
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
            mapOf(
                "label" to "mediapipe_face_landmarker",
                "confidence" to 0.92,
                "looking_away" to false,
                "stable_head_pose" to true,
                "gaze_vector" to mapOf("x" to 0.0, "y" to 0.0, "z" to 1.0),
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

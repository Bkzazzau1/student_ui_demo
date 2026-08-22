package com.example.students_ui_demo

import ai.onnxruntime.OnnxTensor
import ai.onnxruntime.OrtEnvironment
import ai.onnxruntime.OrtSession
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import java.io.File
import java.nio.FloatBuffer
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec
import kotlin.math.sqrt

/**
 * Android counterpart to `windows/runner/face_embedding_runtime_channel.cpp`.
 *
 * Mirrors the same wire protocol (`initialize`, `health`, `embedAlignedRgb`,
 * `storeProtectedTemplate`, `loadProtectedTemplate`) and the same SFace
 * preprocessing (112x112 RGB -> BGR channel order, (value-127.5)/128.0,
 * NCHW, L2-normalized 128-D output) so `NativeFaceEmbeddingRuntime` on the
 * Dart side needs no per-platform special-casing beyond which platforms are
 * considered supported.
 *
 * The protected-template storage here is arguably stronger than the
 * Windows DPAPI path: the AES-256-GCM key lives in the Android Keystore
 * (hardware-backed where the device supports it) and never leaves it, so
 * confidentiality does not depend on the "entropy" string being secret —
 * unlike DPAPI's optional entropy, which is fully derivable from public
 * values here. The entropy string is still accepted and used as GCM
 * additional authenticated data, binding a ciphertext to the student/model
 * it was created for without being the actual security boundary.
 */
class AndroidFaceEmbeddingChannel {
    private var env: OrtEnvironment? = null
    private var session: OrtSession? = null
    private var inputName: String = ""
    private var outputName: String = ""
    private var ready: Boolean = false
    private var lastError: String = "Face embedding runtime has not been initialized."

    fun initialize(args: Map<*, *>?): Boolean {
        val modelPath = args.stringValue("model_path", "")
        if (modelPath.isBlank() || !File(modelPath).let { it.exists() && it.isFile }) {
            lastError = "SFace model file was not found"
            return false
        }
        return try {
            val environment = OrtEnvironment.getEnvironment()
            val options = OrtSession.SessionOptions()
            options.setOptimizationLevel(OrtSession.SessionOptions.OptLevel.ALL_OPT)
            tryEnableNnapi(options)
            val createdSession = environment.createSession(File(modelPath).readBytes(), options)
            inputName = createdSession.inputInfo.keys.first()
            outputName = createdSession.outputInfo.keys.first()
            env = environment
            session = createdSession
            ready = true
            lastError = ""
            true
        } catch (error: Throwable) {
            ready = false
            session = null
            lastError = error.message ?: error.toString()
            false
        }
    }

    private fun tryEnableNnapi(options: OrtSession.SessionOptions) {
        // Best-effort GPU/NPU acceleration, matching the same "try to
        // accelerate, silently fall back to CPU" pattern used for DirectML
        // on Windows. NNAPI is deprecated on very new Android versions but
        // still broadly available; a failure here must never prevent the
        // model from loading on CPU.
        try {
            options.addNnapi()
        } catch (_: Throwable) {
            // Falls back to the default CPU execution provider.
        }
    }

    fun health(): Map<String, Any?> = mapOf(
        "ready" to ready,
        "model_id" to "kslas-sface-2021dec-v1",
        "embedding_dimension" to 128,
        "production_enforcement" to false,
        "error" to lastError,
    )

    fun embedAlignedRgb(args: Map<*, *>?): Map<String, Any?>? {
        val activeEnv = env
        val activeSession = session
        if (!ready || activeEnv == null || activeSession == null) return null
        val bytes = args?.get("rgb_bytes") as? ByteArray
        val side = 112
        if (bytes == null || bytes.size != side * side * 3) {
            lastError = "embedAlignedRgb requires exactly 112x112 RGB bytes"
            return null
        }
        return try {
            val input = FloatArray(3 * side * side)
            for (pixel in 0 until side * side) {
                val r = bytes[pixel * 3].toUByteFloat()
                val g = bytes[pixel * 3 + 1].toUByteFloat()
                val b = bytes[pixel * 3 + 2].toUByteFloat()
                input[pixel] = (b - 127.5f) / 128.0f
                input[side * side + pixel] = (g - 127.5f) / 128.0f
                input[2 * side * side + pixel] = (r - 127.5f) / 128.0f
            }
            OnnxTensor.createTensor(
                activeEnv,
                FloatBuffer.wrap(input),
                longArrayOf(1, 3, side.toLong(), side.toLong()),
            ).use { tensor ->
                activeSession.run(mapOf(inputName to tensor)).use { outputs ->
                    // Iterate rather than index by name: this mirrors the
                    // pattern already used (and presumably verified) by
                    // `AndroidOptimizedVisionRuntimeEngine.runFrame` in
                    // MainActivity.kt, instead of relying on an unverified
                    // `Result.get(name)` call in this environment, which has
                    // no Android SDK to compile-check against.
                    var raw: OnnxTensor? = null
                    for (entry in outputs) {
                        val candidate = entry.value as? OnnxTensor ?: continue
                        if (entry.key == outputName || raw == null) raw = candidate
                    }
                    val tensorOutput = raw ?: return null
                    val data = tensorOutput.floatBuffer
                    val count = data.remaining()
                    if (count != 128) {
                        lastError = "SFace returned an unexpected embedding dimension"
                        return null
                    }
                    val values = FloatArray(count) { data.get(it) }
                    var norm = 0.0
                    for (value in values) norm += value.toDouble() * value.toDouble()
                    norm = sqrt(norm)
                    if (!norm.isFinite() || norm < 1e-6) return null
                    val embedding = values.map { (it / norm).toDouble() }
                    mapOf(
                        "model_id" to "kslas-sface-2021dec-v1",
                        "embedding" to embedding,
                        "normalized" to true,
                        "production_enforcement" to false,
                    )
                }
            }
        } catch (error: Throwable) {
            lastError = error.message ?: error.toString()
            null
        }
    }

    fun storeProtectedTemplate(args: Map<*, *>?): Boolean {
        val path = args.stringValue("path", "")
        val templateJson = args.stringValue("template_json", "")
        val entropy = args.stringValue("entropy", "")
        if (path.isBlank() || templateJson.isBlank() || entropy.isBlank()) return false
        return try {
            val key = protectionKey()
            val cipher = Cipher.getInstance(GCM_TRANSFORMATION)
            cipher.init(Cipher.ENCRYPT_MODE, key)
            cipher.updateAAD(entropy.toByteArray(Charsets.UTF_8))
            val ciphertext = cipher.doFinal(templateJson.toByteArray(Charsets.UTF_8))
            val iv = cipher.iv
            val file = File(path)
            file.parentFile?.mkdirs()
            file.outputStream().use { output ->
                output.write(intToBytes(iv.size))
                output.write(iv)
                output.write(ciphertext)
            }
            true
        } catch (error: Throwable) {
            lastError = error.message ?: error.toString()
            false
        }
    }

    fun loadProtectedTemplate(args: Map<*, *>?): String? {
        val path = args.stringValue("path", "")
        val entropy = args.stringValue("entropy", "")
        if (path.isBlank() || entropy.isBlank()) return null
        val file = File(path)
        if (!file.exists()) return null
        return try {
            val bytes = file.readBytes()
            if (bytes.size < 4) return null
            val ivLength = bytesToInt(bytes, 0)
            if (ivLength <= 0 || bytes.size < 4 + ivLength) return null
            val iv = bytes.copyOfRange(4, 4 + ivLength)
            val ciphertext = bytes.copyOfRange(4 + ivLength, bytes.size)
            val key = protectionKey()
            val cipher = Cipher.getInstance(GCM_TRANSFORMATION)
            cipher.init(Cipher.DECRYPT_MODE, key, GCMParameterSpec(128, iv))
            cipher.updateAAD(entropy.toByteArray(Charsets.UTF_8))
            String(cipher.doFinal(ciphertext), Charsets.UTF_8)
        } catch (error: Throwable) {
            lastError = error.message ?: error.toString()
            null
        }
    }

    private fun protectionKey(): SecretKey {
        val keyStore = KeyStore.getInstance(ANDROID_KEYSTORE)
        keyStore.load(null)
        (keyStore.getKey(KEY_ALIAS, null) as? SecretKey)?.let { return it }
        val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, ANDROID_KEYSTORE)
        val spec = KeyGenParameterSpec.Builder(
            KEY_ALIAS,
            KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
        )
            .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
            .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
            .setUserAuthenticationRequired(false)
            .build()
        generator.init(spec)
        return generator.generateKey()
    }

    private fun intToBytes(value: Int): ByteArray = byteArrayOf(
        (value ushr 24).toByte(),
        (value ushr 16).toByte(),
        (value ushr 8).toByte(),
        value.toByte(),
    )

    private fun bytesToInt(bytes: ByteArray, offset: Int): Int =
        ((bytes[offset].toInt() and 0xff) shl 24) or
            ((bytes[offset + 1].toInt() and 0xff) shl 16) or
            ((bytes[offset + 2].toInt() and 0xff) shl 8) or
            (bytes[offset + 3].toInt() and 0xff)

    private fun Byte.toUByteFloat(): Float = (toInt() and 0xff).toFloat()

    private companion object {
        const val ANDROID_KEYSTORE = "AndroidKeyStore"
        const val KEY_ALIAS = "kslas_identity_template_key"
        const val GCM_TRANSFORMATION = "AES/GCM/NoPadding"
    }
}

private fun Map<*, *>?.stringValue(key: String, fallback: String): String {
    return this?.get(key)?.toString() ?: fallback
}

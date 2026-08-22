import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  private let optimizedVisionRuntime = IOSOptimizedVisionRuntimeEngine()
  private let faceEmbeddingRuntime = IOSFaceEmbeddingRuntimeEngine()
  private let faceLandmarkerRuntime = IOSFaceLandmarkerRuntimeEngine()

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    if let controller = window?.rootViewController as? FlutterViewController {
      let channel = FlutterMethodChannel(
        name: "kslas.optimized_vision_runtime",
        binaryMessenger: controller.binaryMessenger
      )
      channel.setMethodCallHandler { [optimizedVisionRuntime] call, result in
        switch call.method {
        case "initialize":
          result(optimizedVisionRuntime.initialize(policy: call.arguments as? [String: Any]))
        case "runFrame":
          result(optimizedVisionRuntime.runFrame(request: call.arguments as? [String: Any]))
        default:
          result(FlutterMethodNotImplemented)
        }
      }

      // DRAFT / UNVERIFIED: these two channels are scaffolding only. There is
      // no Mac/Xcode available in the environment that wrote this to build or
      // run any of it, so — matching the honest-stub pattern already used
      // above for the optimized vision runtime — they always answer
      // truthfully that identity AI is unavailable rather than attempting an
      // unverified "real" implementation that could silently produce wrong
      // embeddings. A real implementation needs: SFace via onnxruntime-objc
      // (or a Core ML conversion) for face_embedding, and MediaPipe's iOS
      // Tasks Face Landmarker (the same 478-point model already used on
      // Android, see AndroidFaceLandmarkerChannel.kt) for face_landmarker.
      // Protected storage should use the iOS Keychain, mirroring the Android
      // Keystore approach in AndroidFaceEmbeddingChannel.kt.
      let embeddingChannel = FlutterMethodChannel(
        name: "kslas.face_embedding",
        binaryMessenger: controller.binaryMessenger
      )
      embeddingChannel.setMethodCallHandler { [faceEmbeddingRuntime] call, result in
        faceEmbeddingRuntime.handle(call: call, result: result)
      }

      let landmarkerChannel = FlutterMethodChannel(
        name: "kslas.face_landmarker",
        binaryMessenger: controller.binaryMessenger
      )
      landmarkerChannel.setMethodCallHandler { [faceLandmarkerRuntime] call, result in
        faceLandmarkerRuntime.handle(call: call, result: result)
      }
    }
    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}

private final class IOSOptimizedVisionRuntimeEngine {
  private var backend = "not_available"
  private var precision = "not_available"
  private var modelPath = ""
  private var lastInferenceMs = 0.0
  private var lastError =
    "iOS optimized vision runtime is registered, but Core ML / ONNX model assets are not linked."

  func initialize(policy: [String: Any]?) -> Bool {
    backend = policy?["backend"] as? String ?? "onnxRuntimeCoreML"
    precision = policy?["precision"] as? String ?? "fp16"
    modelPath = resolveModelPath(policy: policy)
    if Bundle.main.path(forResource: modelResourceName(), ofType: "mlmodelc") != nil {
      lastError =
        "Core ML model bundle found, but model-specific preprocessing and output decoding are not configured."
    } else {
      lastError = "Missing iOS optimized vision model asset: \(modelPath)"
    }
    return false
  }

  func runFrame(request: [String: Any]?) -> [String: Any] {
    let started = Date()
    defer {
      lastInferenceMs = Date().timeIntervalSince(started) * 1000.0
    }
    return unavailable(message: lastError)
  }

  private func resolveModelPath(policy: [String: Any]?) -> String {
    if let modelPath = policy?["model_path"] as? String, !modelPath.isEmpty {
      return modelPath
    }
    if let onnxPath = policy?["onnx_path"] as? String, !onnxPath.isEmpty {
      return onnxPath
    }
    return "assets/models/optimized_vision_runtime/object_reflection_shadow_detector.fp16.mlmodelc"
  }

  private func modelResourceName() -> String {
    return "object_reflection_shadow_detector.fp16"
  }

  private func unavailable(message: String) -> [String: Any] {
    return [
      "available": false,
      "backend": backend,
      "precision": precision,
      "inference_ms": lastInferenceMs,
      "outputs": [
        "message": message,
        "model_path": modelPath,
      ],
    ]
  }
}

/// DRAFT / UNVERIFIED. See the registration comment in `AppDelegate` above.
///
/// Answers every method honestly: `initialize` and `health` report not
/// ready, and `embedAlignedRgb` / `storeProtectedTemplate` /
/// `loadProtectedTemplate` all return nil/false rather than fabricating a
/// result. `NativeFaceEmbeddingRuntime` on the Dart side does not enable
/// iOS in its `_supportedPlatform` check yet specifically because this is
/// unverified — flip that on only once a real implementation here has been
/// built and tested on an actual device.
private final class IOSFaceEmbeddingRuntimeEngine {
  private let lastError =
    "iOS face embedding runtime is registered but not implemented. "
    + "Needs SFace via onnxruntime-objc (or a Core ML conversion) plus "
    + "Keychain-backed protected storage."

  func handle(call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "initialize":
      result(false)
    case "health":
      result([
        "ready": false,
        "model_id": "kslas-sface-2021dec-v1",
        "embedding_dimension": 128,
        "production_enforcement": false,
        "error": lastError,
      ])
    case "embedAlignedRgb":
      result(nil)
    case "storeProtectedTemplate":
      result(false)
    case "loadProtectedTemplate":
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}

/// DRAFT / UNVERIFIED. See the registration comment in `AppDelegate` above.
///
/// Needs MediaPipe's iOS Tasks Face Landmarker (the same 478-point model
/// already wired up on Android in `AndroidFaceLandmarkerChannel.kt`) to do
/// anything real; until then this always reports "not ready" / returns nil
/// rather than fabricating landmarks.
private final class IOSFaceLandmarkerRuntimeEngine {
  private let lastError =
    "iOS face landmarker runtime is registered but not implemented. "
    + "Needs MediaPipe's iOS Tasks Face Landmarker."

  func handle(call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "initialize":
      result(false)
    case "analyseFrame", "analyseRgb":
      result(nil)
    case "status":
      result([
        "ready": false,
        "last_error": lastError,
      ])
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}

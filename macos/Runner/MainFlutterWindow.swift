import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private let optimizedVisionRuntime = MacOSOptimizedVisionRuntimeEngine()
  private let faceEmbeddingRuntime = MacOSFaceEmbeddingRuntimeEngine()
  private let faceLandmarkerRuntime = MacOSFaceLandmarkerRuntimeEngine()

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    registerIdentityChannels(messenger: flutterViewController.engine.binaryMessenger)
    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }

  // DRAFT / UNVERIFIED: nothing on macOS had any of these three channels
  // registered before this. There is no Mac available in the environment
  // that wrote this to build or run any of it, so every handler below
  // answers honestly that identity/vision AI is unavailable rather than
  // attempting an unverified "real" implementation — the same principle
  // this codebase already applies on iOS
  // (see `ios/Runner/AppDelegate.swift`). A real implementation would need:
  // SFace via onnxruntime-objc (or a Core ML conversion) plus Keychain-
  // backed protected storage for face_embedding; MediaPipe's Tasks Face
  // Landmarker (or the macOS Vision framework) for face_landmarker; and an
  // ONNX/Core ML YOLO decode for optimized_vision_runtime, mirroring
  // `windows/runner/optimized_vision_runtime_engine.cpp` and
  // `AndroidOptimizedVisionRuntimeEngine` in
  // `android/app/src/main/kotlin/.../MainActivity.kt`.
  private func registerIdentityChannels(messenger: FlutterBinaryMessenger) {
    let visionChannel = FlutterMethodChannel(
      name: "kslas.optimized_vision_runtime",
      binaryMessenger: messenger
    )
    visionChannel.setMethodCallHandler { [optimizedVisionRuntime] call, result in
      optimizedVisionRuntime.handle(call: call, result: result)
    }

    let embeddingChannel = FlutterMethodChannel(
      name: "kslas.face_embedding",
      binaryMessenger: messenger
    )
    embeddingChannel.setMethodCallHandler { [faceEmbeddingRuntime] call, result in
      faceEmbeddingRuntime.handle(call: call, result: result)
    }

    let landmarkerChannel = FlutterMethodChannel(
      name: "kslas.face_landmarker",
      binaryMessenger: messenger
    )
    landmarkerChannel.setMethodCallHandler { [faceLandmarkerRuntime] call, result in
      faceLandmarkerRuntime.handle(call: call, result: result)
    }
  }
}

/// DRAFT / UNVERIFIED. See the registration comment above.
private final class MacOSOptimizedVisionRuntimeEngine {
  private var backend = "not_available"
  private var precision = "not_available"
  private let lastError =
    "macOS optimized vision runtime is registered but not implemented."

  func handle(call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "initialize":
      let policy = call.arguments as? [String: Any]
      backend = policy?["backend"] as? String ?? "onnxRuntimeCoreML"
      precision = policy?["precision"] as? String ?? "fp16"
      result(false)
    case "runFrame":
      result([
        "available": false,
        "backend": backend,
        "precision": precision,
        "inference_ms": 0.0,
        "outputs": ["message": lastError],
      ])
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}

/// DRAFT / UNVERIFIED. See the registration comment above.
///
/// `NativeFaceEmbeddingRuntime` on the Dart side does not enable macOS in
/// its `_supportedPlatform` check yet specifically because this is
/// unverified — flip that on only once a real implementation here has been
/// built and tested on an actual device.
private final class MacOSFaceEmbeddingRuntimeEngine {
  private let lastError =
    "macOS face embedding runtime is registered but not implemented. "
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

/// DRAFT / UNVERIFIED. See the registration comment above.
private final class MacOSFaceLandmarkerRuntimeEngine {
  private let lastError =
    "macOS face landmarker runtime is registered but not implemented. "
    + "Needs MediaPipe's Tasks Face Landmarker or the macOS Vision framework."

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

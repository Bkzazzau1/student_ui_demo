import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  private let optimizedVisionRuntime = IOSOptimizedVisionRuntimeEngine()

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

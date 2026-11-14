import Flutter
import UIKit

/// Registers the K-SLAS native channels on iOS/iPadOS:
///
/// - `kslas.face_landmarker`: MediaPipe Face Landmarker (same model as Android)
/// - `kslas.face_embedding`: SFace via ONNX Runtime, and Keychain-protected storage
/// - `kslas.optimized_vision_runtime`: YOLO proctoring detector via ONNX Runtime
/// - `kslas.exam_lockdown`: Guided Access, screen capture and device checks
///
/// The Rust core (`brain_core.framework`) is loaded by Flutter Rust Bridge.
@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private let faceLandmarker = KslasFaceLandmarkerRuntime()
  private let faceEmbedding = KslasFaceEmbeddingRuntime()
  private let optimizedVision = KslasOptimizedVisionRuntime()
  private var examLockdown: KslasExamLockdown?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let messenger = engineBridge.applicationRegistrar.messenger()

    FlutterMethodChannel(name: "kslas.face_landmarker", binaryMessenger: messenger)
      .setMethodCallHandler { [faceLandmarker] call, result in
        faceLandmarker.handle(call, result: result)
      }
    FlutterMethodChannel(name: "kslas.face_embedding", binaryMessenger: messenger)
      .setMethodCallHandler { [faceEmbedding] call, result in
        faceEmbedding.handle(call, result: result)
      }
    FlutterMethodChannel(name: "kslas.optimized_vision_runtime", binaryMessenger: messenger)
      .setMethodCallHandler { [optimizedVision] call, result in
        optimizedVision.handle(call, result: result)
      }
    examLockdown = KslasExamLockdown(messenger: messenger)
  }
}

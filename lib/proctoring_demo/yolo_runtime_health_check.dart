import 'optimized_vision_runtime_bridge.dart';

class YoloRuntimeHealthCheckResult {
  const YoloRuntimeHealthCheckResult({
    required this.ready,
    required this.modelPath,
    required this.classCount,
    required this.layout,
    required this.message,
  });

  final bool ready;
  final String modelPath;
  final int classCount;
  final String layout;
  final String message;

  Map<String, Object?> toJson() => <String, Object?>{
        'ready': ready,
        'model_path': modelPath,
        'class_count': classCount,
        'layout': layout,
        'message': message,
      };
}

class YoloRuntimeHealthCheck {
  YoloRuntimeHealthCheck({OptimizedVisionRuntimeBridge? runtime})
      : _runtime = runtime ?? OptimizedVisionRuntimeBridge();

  final OptimizedVisionRuntimeBridge _runtime;

  Future<YoloRuntimeHealthCheckResult> check() async {
    final ready = await _runtime.initialize();
    final manifest = _runtime.manifest;
    if (manifest == null) {
      return const YoloRuntimeHealthCheckResult(
        ready: false,
        modelPath: '',
        classCount: 0,
        layout: '',
        message: 'YOLO manifest is missing or invalid.',
      );
    }

    final modelPath = manifest.selectedModelPath(_runtime.policy);
    return YoloRuntimeHealthCheckResult(
      ready: ready,
      modelPath: modelPath,
      classCount: manifest.classNames.length,
      layout: manifest.outputLayout,
      message: ready
          ? 'YOLO runtime is initialized with a real ONNX model.'
          : 'YOLO runtime is not initialized. Confirm the ONNX model exists at the manifest model path.',
    );
  }
}

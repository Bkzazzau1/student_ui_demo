import 'dart:io';

enum VisionRuntimeBackend {
  onnxRuntimeDirectML,
  onnxRuntimeCoreML,
  onnxRuntimeCpu,
  tensorRt,
  fallbackDart,
}

enum VisionModelPrecision {
  int8,
  fp16,
  fp32Fallback,
}

class OptimizedVisionRuntimePolicy {
  const OptimizedVisionRuntimePolicy({
    required this.backend,
    required this.precision,
    required this.targetUtilization,
    required this.maxInputWidth,
    required this.maxInputHeight,
    required this.targetFps,
    required this.batchSize,
  });

  final VisionRuntimeBackend backend;
  final VisionModelPrecision precision;
  final double targetUtilization;
  final int maxInputWidth;
  final int maxInputHeight;
  final int targetFps;
  final int batchSize;

  Map<String, Object?> toJson() => <String, Object?>{
        'backend': backend.name,
        'precision': precision.name,
        'target_utilization': targetUtilization,
        'max_input_width': maxInputWidth,
        'max_input_height': maxInputHeight,
        'target_fps': targetFps,
        'batch_size': batchSize,
      };

  static OptimizedVisionRuntimePolicy forCurrentPlatform() {
    if (Platform.isWindows) {
      return const OptimizedVisionRuntimePolicy(
        backend: VisionRuntimeBackend.onnxRuntimeDirectML,
        precision: VisionModelPrecision.int8,
        targetUtilization: 0.15,
        maxInputWidth: 416,
        maxInputHeight: 416,
        targetFps: 1,
        batchSize: 1,
      );
    }
    if (Platform.isMacOS) {
      return const OptimizedVisionRuntimePolicy(
        backend: VisionRuntimeBackend.onnxRuntimeCoreML,
        precision: VisionModelPrecision.fp16,
        targetUtilization: 0.15,
        maxInputWidth: 416,
        maxInputHeight: 416,
        targetFps: 1,
        batchSize: 1,
      );
    }
    if (Platform.isLinux) {
      return const OptimizedVisionRuntimePolicy(
        backend: VisionRuntimeBackend.onnxRuntimeCpu,
        precision: VisionModelPrecision.int8,
        targetUtilization: 0.15,
        maxInputWidth: 416,
        maxInputHeight: 416,
        targetFps: 1,
        batchSize: 1,
      );
    }
    return const OptimizedVisionRuntimePolicy(
      backend: VisionRuntimeBackend.fallbackDart,
      precision: VisionModelPrecision.fp32Fallback,
      targetUtilization: 0.15,
      maxInputWidth: 320,
      maxInputHeight: 320,
      targetFps: 1,
      batchSize: 1,
    );
  }
}

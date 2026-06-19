import 'package:camera/camera.dart';
import 'package:flutter/services.dart';

import 'optimized_vision_runtime_policy.dart';

class OptimizedVisionRuntimeResult {
  const OptimizedVisionRuntimeResult({
    required this.available,
    required this.backend,
    required this.precision,
    required this.inferenceMs,
    required this.outputs,
  });

  final bool available;
  final String backend;
  final String precision;
  final double inferenceMs;
  final Map<String, Object?> outputs;

  Map<String, Object?> toJson() => <String, Object?>{
        'available': available,
        'backend': backend,
        'precision': precision,
        'inference_ms': inferenceMs,
        'outputs': outputs,
      };
}

class OptimizedVisionRuntimeBridge {
  OptimizedVisionRuntimeBridge({
    MethodChannel? channel,
    OptimizedVisionRuntimePolicy? policy,
  })  : _channel = channel ?? const MethodChannel('kslas.optimized_vision_runtime'),
        _policy = policy ?? OptimizedVisionRuntimePolicy.forCurrentPlatform();

  final MethodChannel _channel;
  final OptimizedVisionRuntimePolicy _policy;
  bool _initialized = false;
  bool _available = false;

  OptimizedVisionRuntimePolicy get policy => _policy;
  bool get available => _available;

  Future<bool> initialize() async {
    if (_initialized) return _available;
    _initialized = true;
    try {
      final ok = await _channel.invokeMethod<bool>('initialize', _policy.toJson());
      _available = ok == true;
      return _available;
    } on MissingPluginException {
      _available = false;
      return false;
    } catch (_) {
      _available = false;
      return false;
    }
  }

  Future<OptimizedVisionRuntimeResult?> runFrame({
    required CameraImage image,
    required List<String> tasks,
  }) async {
    if (!await initialize()) return null;
    try {
      final started = DateTime.now();
      final response = await _channel.invokeMapMethod<String, Object?>(
        'runFrame',
        <String, Object?>{
          'policy': _policy.toJson(),
          'tasks': tasks,
          'width': image.width,
          'height': image.height,
          'format': image.format.group.name,
          'timestamp_ms': DateTime.now().millisecondsSinceEpoch,
          'planes': image.planes
              .map((plane) => <String, Object?>{
                    'bytes': plane.bytes,
                    'bytes_per_row': plane.bytesPerRow,
                    'bytes_per_pixel': plane.bytesPerPixel ?? 1,
                    'width': plane.width,
                    'height': plane.height,
                  })
              .toList(),
        },
      );
      if (response == null) return null;
      final elapsedMs = DateTime.now().difference(started).inMicroseconds / 1000.0;
      return OptimizedVisionRuntimeResult(
        available: true,
        backend: response['backend']?.toString() ?? _policy.backend.name,
        precision: response['precision']?.toString() ?? _policy.precision.name,
        inferenceMs: double.tryParse(response['inference_ms']?.toString() ?? '') ?? elapsedMs,
        outputs: Map<String, Object?>.from(response['outputs'] as Map? ?? const <String, Object?>{}),
      );
    } on MissingPluginException {
      _available = false;
      return null;
    } catch (_) {
      return null;
    }
  }
}

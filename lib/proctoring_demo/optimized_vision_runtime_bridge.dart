import 'package:camera/camera.dart';
import 'package:flutter/services.dart';

import 'optimized_vision_runtime_policy.dart';
import 'yolo_exam_review_manifest.dart';

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
    String manifestAssetPath = YoloExamReviewManifest.defaultAssetPath,
  }) : _channel =
           channel ?? const MethodChannel('kslas.optimized_vision_runtime'),
       _policy = policy ?? OptimizedVisionRuntimePolicy.forCurrentPlatform(),
       _manifestAssetPath = manifestAssetPath;

  final MethodChannel _channel;
  final OptimizedVisionRuntimePolicy _policy;
  final String _manifestAssetPath;
  bool _initialized = false;
  bool _available = false;
  YoloExamReviewManifest? _manifest;

  OptimizedVisionRuntimePolicy get policy => _policy;
  bool get available => _available;
  YoloExamReviewManifest? get manifest => _manifest;

  Future<bool> initialize() async {
    if (_initialized) return _available;
    _initialized = true;
    try {
      final manifest = await YoloExamReviewManifest.load(
        assetPath: _manifestAssetPath,
      );
      if (manifest == null) {
        _available = false;
        return false;
      }
      _manifest = manifest;
      final initPolicy = <String, Object?>{
        ..._policy.toJson(),
        ...manifest.toPolicyJson(_policy),
      };
      final ok = await _channel.invokeMethod<bool>('initialize', initPolicy);
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
          'policy': <String, Object?>{
            ..._policy.toJson(),
            ...?_manifest?.toPolicyJson(_policy),
          },
          'tasks': tasks,
          'width': image.width,
          'height': image.height,
          'format': image.format.group.name,
          'timestamp_ms': DateTime.now().millisecondsSinceEpoch,
          'planes': image.planes
              .map(
                (plane) => <String, Object?>{
                  'bytes': plane.bytes,
                  'bytes_per_row': plane.bytesPerRow,
                  'bytes_per_pixel': plane.bytesPerPixel ?? 1,
                  'width': plane.width,
                  'height': plane.height,
                },
              )
              .toList(),
        },
      );
      if (response == null) return null;
      final elapsedMs =
          DateTime.now().difference(started).inMicroseconds / 1000.0;
      final available = response['available'] == true;
      return OptimizedVisionRuntimeResult(
        available: available,
        backend: response['backend']?.toString() ?? _policy.backend.name,
        precision: response['precision']?.toString() ?? _policy.precision.name,
        inferenceMs:
            double.tryParse(response['inference_ms']?.toString() ?? '') ??
            elapsedMs,
        outputs: Map<String, Object?>.from(
          response['outputs'] as Map? ?? const <String, Object?>{},
        ),
      );
    } on MissingPluginException {
      _available = false;
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<OptimizedVisionRuntimeResult?> runRgbFrame({
    required Uint8List rgbBytes,
    required int width,
    required int height,
    required List<String> tasks,
  }) async {
    if (!await initialize()) return null;
    if (width <= 0 || height <= 0 || rgbBytes.isEmpty) return null;
    try {
      final started = DateTime.now();
      final response = await _channel.invokeMapMethod<String, Object?>(
        'runFrame',
        <String, Object?>{
          'policy': <String, Object?>{
            ..._policy.toJson(),
            ...?_manifest?.toPolicyJson(_policy),
          },
          'tasks': tasks,
          'width': width,
          'height': height,
          'format': 'rgb888',
          'timestamp_ms': DateTime.now().millisecondsSinceEpoch,
          'planes': <Map<String, Object?>>[
            <String, Object?>{
              'bytes': rgbBytes,
              'bytes_per_row': width * 3,
              'bytes_per_pixel': 3,
              'width': width,
              'height': height,
            },
          ],
        },
      );
      if (response == null) return null;
      final elapsedMs =
          DateTime.now().difference(started).inMicroseconds / 1000.0;
      final available = response['available'] == true;
      return OptimizedVisionRuntimeResult(
        available: available,
        backend: response['backend']?.toString() ?? _policy.backend.name,
        precision: response['precision']?.toString() ?? _policy.precision.name,
        inferenceMs:
            double.tryParse(response['inference_ms']?.toString() ?? '') ??
            elapsedMs,
        outputs: Map<String, Object?>.from(
          response['outputs'] as Map? ?? const <String, Object?>{},
        ),
      );
    } on MissingPluginException {
      _available = false;
      return null;
    } catch (_) {
      return null;
    }
  }
}

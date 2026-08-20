import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/services.dart';

import 'gaze_head_pose_estimator.dart';
import 'native_head_pose_geometry_service.dart';

class NativeFaceLandmarkerRuntime {
  NativeFaceLandmarkerRuntime({
    MethodChannel? channel,
    NativeHeadPoseGeometryService? headPoseGeometry,
    String? assetPath,
  }) : _channel = channel ?? const MethodChannel('kslas.face_landmarker'),
       _headPoseGeometry =
           headPoseGeometry ?? const NativeHeadPoseGeometryService(),
       _configuredAssetPath = assetPath;

  final MethodChannel _channel;
  final NativeHeadPoseGeometryService _headPoseGeometry;
  final String? _configuredAssetPath;
  String get assetPath =>
      _configuredAssetPath ??
      (Platform.isWindows
          ? 'assets/models/face_landmarker_windows/face_landmarks.onnx'
          : 'assets/models/face_landmarker/face_landmarker.task');
  bool _ready = false;
  bool _failed = false;
  String? _runtimeModelPath;

  bool get ready => _ready;
  bool get failed => _failed;
  String? get runtimeModelPath => _runtimeModelPath;

  Future<bool> initialize() async {
    if (_ready) return true;
    if (_failed) return false;
    try {
      final modelBytes = await rootBundle.load(assetPath);
      final modelDir = Directory(
        '${Directory.systemTemp.path}/kslas_face_landmarker',
      );
      if (!await modelDir.exists()) {
        await modelDir.create(recursive: true);
      }
      final extension = Platform.isWindows ? 'onnx' : 'task';
      final modelFile = File('${modelDir.path}/face_landmarker.$extension');
      await modelFile.writeAsBytes(
        modelBytes.buffer.asUint8List(),
        flush: true,
      );
      final ok = await _channel.invokeMethod<bool>(
        'initialize',
        <String, Object?>{'model_path': modelFile.path},
      );
      _ready = ok == true;
      _failed = !_ready;
      _runtimeModelPath = modelFile.path;
      return _ready;
    } on MissingPluginException {
      _failed = true;
      return false;
    } catch (_) {
      _failed = true;
      return false;
    }
  }

  Future<GazeHeadPoseResult?> analyse(CameraImage image) async {
    if (!_ready && !await initialize()) return null;
    try {
      final planes = image.planes
          .map(
            (plane) => <String, Object?>{
              'bytes': Uint8List.fromList(plane.bytes),
              'bytes_per_row': plane.bytesPerRow,
              'bytes_per_pixel': plane.bytesPerPixel ?? 1,
              'height': plane.height,
              'width': plane.width,
            },
          )
          .toList();
      final result = await _channel
          .invokeMapMethod<String, Object?>('analyseFrame', <String, Object?>{
            'width': image.width,
            'height': image.height,
            'format': image.format.group.name,
            'planes': planes,
            'timestamp_ms': DateTime.now().millisecondsSinceEpoch,
          });
      if (result == null) return null;
      return _parseResult(result, image.width, image.height);
    } on MissingPluginException {
      _failed = true;
      _ready = false;
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<GazeHeadPoseResult?> analyseRgb({
    required Uint8List rgbBytes,
    required int width,
    required int height,
  }) async {
    if (!_ready && !await initialize()) return null;
    try {
      final result = await _channel.invokeMapMethod<String, Object?>(
        'analyseRgb',
        <String, Object?>{
          'width': width,
          'height': height,
          'rgb_bytes': rgbBytes,
        },
      );
      if (result == null) return null;
      return _parseResult(result, width, height);
    } on MissingPluginException {
      _failed = true;
      _ready = false;
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Returns the native landmark payload for enrollment/alignment code.
  /// A null result means no reliable face was produced; callers must not
  /// manufacture landmarks or embeddings in that case.
  Future<Map<String, Object?>?> analyseRgbRaw({
    required Uint8List rgbBytes,
    required int width,
    required int height,
  }) async {
    if (!_ready && !await initialize()) return null;
    try {
      return await _channel.invokeMapMethod<String, Object?>(
        'analyseRgb',
        <String, Object?>{
          'width': width,
          'height': height,
          'rgb_bytes': rgbBytes,
        },
      );
    } on MissingPluginException {
      _failed = true;
      _ready = false;
      return null;
    } catch (_) {
      return null;
    }
  }

  GazeHeadPoseResult _parseResult(
    Map<String, Object?> result,
    int imageWidth,
    int imageHeight,
  ) {
    final gaze = Map<String, Object?>.from(
      result['gaze_vector'] as Map? ?? const <String, Object?>{},
    );
    final pose = Map<String, Object?>.from(
      result['head_pose'] as Map? ?? const <String, Object?>{},
    );
    final landmarks = _readLandmarks(
      result['landmarks'] ?? result['face_landmarks'],
    );
    final rustHeadPose = _headPoseGeometry.analyzeLandmarks(
      landmarks: landmarks,
      imageWidth: imageWidth.toDouble(),
      imageHeight: imageHeight.toDouble(),
    );
    final label =
        result['label']?.toString() ??
        (rustHeadPose?.reason ?? 'landmark_runtime_result');
    final confidence = _toDouble(
      result['confidence'],
      fallback: rustHeadPose == null ? 0.0 : 0.86,
    ).clamp(0.0, 1.0).toDouble();
    final rustLookingAway = rustHeadPose?.lookingAway;
    final lookingAway = rustLookingAway ?? result['looking_away'] == true;
    final stableHeadPose = rustHeadPose == null
        ? result['stable_head_pose'] != false
        : !rustHeadPose.lookingAway;
    final yaw =
        rustHeadPose?.yawScore ??
        _toDouble(pose['yaw']).clamp(-1.0, 1.0).toDouble();
    final pitch =
        rustHeadPose?.pitchScore ??
        _toDouble(pose['pitch']).clamp(-1.0, 1.0).toDouble();
    final roll =
        rustHeadPose?.rollScore ??
        _toDouble(pose['roll']).clamp(-1.0, 1.0).toDouble();
    return GazeHeadPoseResult(
      gazeX: _toDouble(gaze['x']).clamp(-1.0, 1.0).toDouble(),
      gazeY: _toDouble(gaze['y']).clamp(-1.0, 1.0).toDouble(),
      gazeZ: _toDouble(gaze['z'], fallback: 1.0).clamp(-1.0, 1.0).toDouble(),
      yawProxy: yaw.clamp(-1.0, 1.0).toDouble(),
      pitchProxy: pitch.clamp(-1.0, 1.0).toDouble(),
      rollProxy: roll.clamp(-1.0, 1.0).toDouble(),
      confidence: confidence,
      stableHeadPose: stableHeadPose,
      lookingAway: lookingAway,
      label: rustHeadPose == null ? label : 'rust_head_pose_geometry',
      landmarkBased: landmarks.isNotEmpty,
    );
  }

  List<LandmarkPoint> _readLandmarks(Object? value) {
    if (value is! Iterable) return const <LandmarkPoint>[];
    return value
        .whereType<Map>()
        .map((item) => Map<String, Object?>.from(item))
        .toList(growable: false);
  }

  double _toDouble(Object? value, {double fallback = 0.0}) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? fallback;
  }
}

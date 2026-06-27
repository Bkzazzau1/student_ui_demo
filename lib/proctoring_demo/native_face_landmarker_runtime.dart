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
    this.assetPath = 'assets/models/face_landmarker/face_landmarker.task',
  })  : _channel = channel ?? const MethodChannel('kslas.face_landmarker'),
        _headPoseGeometry =
            headPoseGeometry ?? const NativeHeadPoseGeometryService();

  final MethodChannel _channel;
  final NativeHeadPoseGeometryService _headPoseGeometry;
  final String assetPath;
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
      final modelFile = File('${modelDir.path}/face_landmarker.task');
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
      final gaze = Map<String, Object?>.from(
        result['gaze_vector'] as Map? ?? const <String, Object?>{},
      );
      final pose = Map<String, Object?>.from(
        result['head_pose'] as Map? ?? const <String, Object?>{},
      );
      final landmarks = _readLandmarks(result['landmarks'] ?? result['face_landmarks']);
      final rustHeadPose = _headPoseGeometry.analyzeLandmarks(
        landmarks: landmarks,
        imageWidth: image.width.toDouble(),
        imageHeight: image.height.toDouble(),
      );
      final label = result['label']?.toString() ??
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
      final yaw = rustHeadPose?.yawScore ?? _toDouble(pose['yaw']).clamp(-1.0, 1.0).toDouble();
      final pitch = rustHeadPose?.pitchScore ?? _toDouble(pose['pitch']).clamp(-1.0, 1.0).toDouble();
      final roll = rustHeadPose?.rollScore ?? _toDouble(pose['roll']).clamp(-1.0, 1.0).toDouble();
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
      );
    } on MissingPluginException {
      _failed = true;
      _ready = false;
      return null;
    } catch (_) {
      return null;
    }
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

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/services.dart';

import 'gaze_head_pose_estimator.dart';

class NativeFaceLandmarkerRuntime {
  NativeFaceLandmarkerRuntime({
    MethodChannel? channel,
    this.assetPath = 'assets/models/face_landmarker/face_landmarker.task',
  }) : _channel = channel ?? const MethodChannel('kslas.face_landmarker');

  final MethodChannel _channel;
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
      final modelDir = Directory('${Directory.systemTemp.path}/kslas_face_landmarker');
      if (!await modelDir.exists()) {
        await modelDir.create(recursive: true);
      }
      final modelFile = File('${modelDir.path}/face_landmarker.task');
      await modelFile.writeAsBytes(
        modelBytes.buffer.asUint8List(),
        flush: true,
      );
      final ok = await _channel.invokeMethod<bool>('initialize', <String, Object?>{
        'model_path': modelFile.path,
      });
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
          .map((plane) => <String, Object?>{
                'bytes': Uint8List.fromList(plane.bytes),
                'bytes_per_row': plane.bytesPerRow,
                'bytes_per_pixel': plane.bytesPerPixel ?? 1,
                'height': plane.height,
                'width': plane.width,
              })
          .toList();
      final result = await _channel.invokeMapMethod<String, Object?>(
        'analyseFrame',
        <String, Object?>{
          'width': image.width,
          'height': image.height,
          'format': image.format.group.name,
          'planes': planes,
          'timestamp_ms': DateTime.now().millisecondsSinceEpoch,
        },
      );
      if (result == null) return null;
      final gaze = Map<String, Object?>.from(result['gaze_vector'] as Map? ?? const <String, Object?>{});
      final pose = Map<String, Object?>.from(result['head_pose'] as Map? ?? const <String, Object?>{});
      final label = result['label']?.toString() ?? 'landmark_runtime_result';
      final confidence = _toDouble(result['confidence'], fallback: 0.0).clamp(0.0, 1.0);
      final lookingAway = result['looking_away'] == true;
      final stableHeadPose = result['stable_head_pose'] != false;
      return GazeHeadPoseResult(
        gazeX: _toDouble(gaze['x']).clamp(-1.0, 1.0),
        gazeY: _toDouble(gaze['y']).clamp(-1.0, 1.0),
        gazeZ: _toDouble(gaze['z'], fallback: 1.0).clamp(-1.0, 1.0),
        yawProxy: _toDouble(pose['yaw']).clamp(-1.0, 1.0),
        pitchProxy: _toDouble(pose['pitch']).clamp(-1.0, 1.0),
        rollProxy: _toDouble(pose['roll']).clamp(-1.0, 1.0),
        confidence: confidence,
        stableHeadPose: stableHeadPose,
        lookingAway: lookingAway,
        label: label,
      );
    } on MissingPluginException {
      _failed = true;
      _ready = false;
      return null;
    } catch (_) {
      return null;
    }
  }

  double _toDouble(Object? value, {double fallback = 0.0}) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? fallback;
  }
}

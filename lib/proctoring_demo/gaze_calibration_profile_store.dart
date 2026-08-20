import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';

import '../rust/api/gaze_calibration.dart';

class GazeCalibrationProfileStore {
  static const MethodChannel _channel = MethodChannel('kslas.face_embedding');
  static final Map<String, GazeCalibrationProfileV2> _sessionProfiles = {};

  static GazeCalibrationProfileV2? profileForAttempt(String attemptId) =>
      _sessionProfiles[attemptId];

  Future<bool> save(GazeCalibrationProfileV2 profile) async {
    if (!Platform.isWindows) {
      _sessionProfiles[profile.attemptId] = profile;
      return true;
    }
    final path = await _path(
      profile.studentId,
      profile.deviceId,
      profile.attemptId,
    );
    if (path == null) return false;
    final stored =
        await _channel
            .invokeMethod<bool>('storeProtectedTemplate', <String, Object?>{
              'path': path,
              'template_json': jsonEncode(_toJson(profile)),
              'entropy': _entropy(
                profile.studentId,
                profile.deviceId,
                profile.modelSha256,
              ),
            }) ??
        false;
    if (stored) {
      _sessionProfiles[profile.attemptId] = profile;
    }
    return stored;
  }

  Future<String?> _path(
    String studentId,
    String deviceId,
    String attemptId,
  ) async {
    final root = Platform.environment['LOCALAPPDATA'];
    if (root == null || root.isEmpty) return null;
    final directory = Directory(
      '$root${Platform.pathSeparator}KSLAS${Platform.pathSeparator}calibration',
    );
    await directory.create(recursive: true);
    final key = sha256
        .convert(utf8.encode('$studentId:$deviceId:$attemptId'))
        .toString();
    return '${directory.path}${Platform.pathSeparator}$key.dpapi';
  }

  String _entropy(String studentId, String deviceId, String modelSha256) =>
      'kslas-gaze-v2:$studentId:$deviceId:$modelSha256';

  Map<String, Object?> _toJson(GazeCalibrationProfileV2 value) => {
    'profile_version': value.profileVersion,
    'usable': value.usable,
    'student_id': value.studentId,
    'device_id': value.deviceId,
    'exam_id': value.examId,
    'attempt_id': value.attemptId,
    'camera_id': value.cameraId,
    'screen_width': value.screenWidth,
    'screen_height': value.screenHeight,
    'display_scale': value.displayScale,
    'model_id': value.modelId,
    'model_sha256': value.modelSha256,
    'created_at_ms': value.createdAtMs,
    'expires_at_ms': value.expiresAtMs,
    'sample_count': value.sampleCount,
    'center_eye_x': value.centerEyeX,
    'center_eye_y': value.centerEyeY,
    'yaw_bias': value.yawBias,
    'pitch_bias': value.pitchBias,
    'roll_bias': value.rollBias,
    'horizontal_stddev': value.horizontalStddev,
    'vertical_stddev': value.verticalStddev,
    'yaw_stddev': value.yawStddev,
    'pitch_stddev': value.pitchStddev,
    'quality_score': value.qualityScore,
    'reason': value.reason,
    'zones': value.zones
        .map(
          (zone) => {
            'name': zone.name,
            'sample_count': zone.sampleCount,
            'eye_x': zone.eyeX,
            'eye_y': zone.eyeY,
            'yaw': zone.yaw,
            'pitch': zone.pitch,
            'eye_x_stddev': zone.eyeXStddev,
            'eye_y_stddev': zone.eyeYStddev,
          },
        )
        .toList(),
  };
}

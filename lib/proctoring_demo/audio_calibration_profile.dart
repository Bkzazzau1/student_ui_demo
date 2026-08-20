import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';

import 'audio_security_check_service.dart';

class AudioCalibrationProfile {
  const AudioCalibrationProfile({
    required this.studentId,
    required this.deviceId,
    required this.examId,
    required this.attemptId,
    required this.createdAtMs,
    required this.expiresAtMs,
    required this.averageRms,
    required this.peakRms,
    required this.noiseFloorRms,
    required this.zeroCrossingRate,
    required this.dynamicVariation,
    required this.qualityScore,
    required this.ambientClass,
  });

  static const String profileVersion = 'audio-calibration-v1';
  static const String modelId = 'native-audio-intelligence-v1';

  final String studentId;
  final String deviceId;
  final String examId;
  final String attemptId;
  final int createdAtMs;
  final int expiresAtMs;
  final double averageRms;
  final double peakRms;
  final double noiseFloorRms;
  final double zeroCrossingRate;
  final double dynamicVariation;
  final double qualityScore;
  final String ambientClass;

  bool get usable =>
      qualityScore >= 0.68 &&
      expiresAtMs > DateTime.now().toUtc().millisecondsSinceEpoch;

  Map<String, Object?> toJson() => <String, Object?>{
    'profile_version': profileVersion,
    'model_id': modelId,
    'student_id': studentId,
    'device_id': deviceId,
    'exam_id': examId,
    'attempt_id': attemptId,
    'created_at_ms': createdAtMs,
    'expires_at_ms': expiresAtMs,
    'average_rms': averageRms,
    'peak_rms': peakRms,
    'noise_floor_rms': noiseFloorRms,
    'zero_crossing_rate': zeroCrossingRate,
    'dynamic_variation': dynamicVariation,
    'quality_score': qualityScore,
    'ambient_class': ambientClass,
    'contains_raw_audio': false,
  };
}

class AudioCalibrationProfileStore {
  static const MethodChannel _channel = MethodChannel('kslas.face_embedding');
  static final Map<String, AudioCalibrationProfile> _profiles = {};

  static AudioCalibrationProfile? profileForAttempt(String attemptId) {
    final profile = _profiles[attemptId];
    return profile?.usable == true ? profile : null;
  }

  Future<AudioCalibrationProfile?> createAndSave({
    required AudioSecurityCheckResult result,
    required String studentId,
    required String examId,
    required String attemptId,
  }) async {
    if (!result.microphoneAvailable ||
        !result.permissionGranted ||
        !result.inputLevelOk ||
        result.sampleDurationSeconds < 15) {
      return null;
    }
    final now = DateTime.now().toUtc();
    final deviceId = sha256
        .convert(
          utf8.encode('${Platform.localHostname}:${Platform.operatingSystem}'),
        )
        .toString();
    final quality = _quality(result);
    final profile = AudioCalibrationProfile(
      studentId: studentId,
      deviceId: deviceId,
      examId: examId,
      attemptId: attemptId,
      createdAtMs: now.millisecondsSinceEpoch,
      expiresAtMs: now.add(const Duration(hours: 8)).millisecondsSinceEpoch,
      averageRms: result.averageRms,
      peakRms: result.peakRms,
      noiseFloorRms: result.noiseFloorRms,
      zeroCrossingRate: result.zeroCrossingRate,
      dynamicVariation: result.dynamicVariation,
      qualityScore: quality,
      ambientClass: result.dominantNoiseClass,
    );
    if (!profile.usable) return null;
    if (!Platform.isWindows) {
      _profiles[attemptId] = profile;
      return profile;
    }
    final root = Platform.environment['LOCALAPPDATA'];
    if (root == null || root.isEmpty) return null;
    final directory = Directory(
      '$root${Platform.pathSeparator}KSLAS${Platform.pathSeparator}calibration',
    );
    await directory.create(recursive: true);
    final key = sha256
        .convert(utf8.encode('$studentId:$deviceId:$attemptId:audio'))
        .toString();
    final stored = await _channel
        .invokeMethod<bool>('storeProtectedTemplate', <String, Object?>{
          'path': '${directory.path}${Platform.pathSeparator}$key.audio.dpapi',
          'template_json': jsonEncode(profile.toJson()),
          'entropy': 'kslas-audio-v1:$studentId:$deviceId:$attemptId',
        });
    if (stored == true) {
      _profiles[attemptId] = profile;
      return profile;
    }
    return null;
  }

  double _quality(AudioSecurityCheckResult result) {
    var score = 1.0;
    if (result.humanVoiceDetected) score -= 0.25;
    if (result.phoneRingDetected || result.notificationDetected) score -= 0.20;
    if (!result.ambientNoiseAllowed) score -= 0.10;
    if (result.peakRms < 0.002) score -= 0.40;
    return score.clamp(0.0, 1.0);
  }
}

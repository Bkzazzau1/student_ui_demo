import 'package:get_storage/get_storage.dart';

import '../rust/api/gaze_calibration.dart';
import 'gaze_head_pose_estimator.dart';
import 'gaze_calibration_profile_store.dart';

class CalibratedGazeDecision {
  const CalibratedGazeDecision({
    required this.zone,
    required this.confidence,
    required this.signalQuality,
    required this.calibrated,
    required this.actionable,
    required this.deviating,
    required this.reason,
  });

  final String zone;
  final double confidence;
  final double signalQuality;
  final bool calibrated;
  final bool actionable;
  final bool deviating;
  final String reason;

  Map<String, Object?> toJson() => <String, Object?>{
    'zone': zone,
    'confidence': confidence,
    'signal_quality': signalQuality,
    'calibrated': calibrated,
    'actionable': actionable,
    'deviating': deviating,
    'reason': reason,
  };
}

/// Builds and stores a per-attempt baseline. Raw frames and identity data are
/// never persisted; only normalized gaze/head statistics are retained.
class CalibratedGazeService {
  CalibratedGazeService({required this.attemptId, GetStorage? storage})
    : _storage = storage ?? GetStorage();

  final String attemptId;
  final GetStorage _storage;
  final List<GazeCalibrationSample> _samples = <GazeCalibrationSample>[];
  GazeCalibrationProfile? _profile;
  GazeCalibrationProfileV2? _profileV2;

  String get _key => 'gaze_calibration_v1_$attemptId';
  bool get ready {
    final profileV2 = _profileV2;
    if (profileV2 != null) {
      return profileV2.usable &&
          profileV2.expiresAtMs > DateTime.now().toUtc().millisecondsSinceEpoch;
    }
    return _profile?.usable == true;
  }

  int get sampleCount =>
      _profileV2?.sampleCount ?? _profile?.sampleCount ?? _samples.length;

  void load() {
    _profileV2 = GazeCalibrationProfileStore.profileForAttempt(attemptId);
    if (_profileV2?.usable == true) return;
    final value = _storage.read<Object?>(_key);
    if (value is! Map) return;
    final json = Map<String, Object?>.from(value);
    _profile = GazeCalibrationProfile(
      usable: json['usable'] == true,
      sampleCount: (json['sample_count'] as num?)?.toInt() ?? 0,
      zones: (json['zones'] as List? ?? const <Object>[])
          .map((value) => value.toString())
          .toList(growable: false),
      centerEyeX: (json['center_eye_x'] as num?)?.toDouble() ?? 0.5,
      centerEyeY: (json['center_eye_y'] as num?)?.toDouble() ?? 0.5,
      yawBias: (json['yaw_bias'] as num?)?.toDouble() ?? 0,
      pitchBias: (json['pitch_bias'] as num?)?.toDouble() ?? 0,
      qualityScore: (json['quality_score'] as num?)?.toDouble() ?? 0,
      reason: json['reason']?.toString() ?? 'loaded local calibration',
    );
  }

  CalibratedGazeDecision observe(
    GazeHeadPoseResult result, {
    required bool landmarkRuntimeReady,
  }) {
    final landmarkSignal = landmarkRuntimeReady && result.landmarkBased;
    if (!landmarkSignal) {
      return CalibratedGazeDecision(
        zone: 'camera_not_reliable',
        confidence: result.confidence,
        signalQuality: result.confidence,
        calibrated: false,
        actionable: false,
        deviating: false,
        reason: 'fallback-only gaze is observational and cannot pause an exam',
      );
    }

    if (!ready && result.confidence >= 0.72 && !result.lookingAway) {
      _samples.add(
        GazeCalibrationSample(
          zone: 'answer_area',
          eyeX: ((result.gazeX + 1) / 2).clamp(0.0, 1.0),
          eyeY: ((result.gazeY + 1) / 2).clamp(0.0, 1.0),
          headYaw: result.yawProxy,
          headPitch: result.pitchProxy,
          headRoll: result.rollProxy,
          confidence: result.confidence,
          timestampMs: DateTime.now().millisecondsSinceEpoch,
        ),
      );
      if (_samples.length >= 8) {
        _profile = buildGazeCalibrationProfile(samples: _samples);
        _persist();
      }
    }

    final profileV2 = _profileV2;
    if (profileV2 != null && profileV2.usable) {
      final prediction = predictCalibratedGazeZoneV2(
        profile: profileV2,
        eyeX: ((result.gazeX + 1) / 2).clamp(0.0, 1.0),
        eyeY: ((result.gazeY + 1) / 2).clamp(0.0, 1.0),
        headYaw: result.yawProxy,
        headPitch: result.pitchProxy,
        signalConfidence: result.confidence,
        nowMs: DateTime.now().millisecondsSinceEpoch,
      );
      final deviation =
          prediction.zone == 'outside_calibrated_screen' ||
          prediction.deviationScore >= 3.0;
      return CalibratedGazeDecision(
        zone: prediction.zone,
        confidence: prediction.confidence,
        signalQuality: result.confidence,
        calibrated: prediction.calibrated,
        actionable: prediction.actionable,
        deviating: prediction.actionable && deviation,
        reason: prediction.reason,
      );
    }

    final profile = _profile;
    if (profile == null || !profile.usable) {
      return CalibratedGazeDecision(
        zone: 'calibrating',
        confidence: result.confidence,
        signalQuality: result.confidence,
        calibrated: false,
        actionable: false,
        deviating: false,
        reason: 'learning personal neutral gaze ($sampleCount/8)',
      );
    }

    final prediction = predictCalibratedGazeZone(
      profile: profile,
      eyeX: ((result.gazeX + 1) / 2).clamp(0.0, 1.0),
      eyeY: ((result.gazeY + 1) / 2).clamp(0.0, 1.0),
      headYaw: result.yawProxy,
      headPitch: result.pitchProxy,
      signalConfidence: result.confidence,
    );
    final deviation =
        prediction.zone == 'downward_gaze' ||
        prediction.zone == 'top_screen_area' ||
        result.lookingAway;
    final actionable =
        prediction.calibrated &&
        result.confidence >= 0.72 &&
        profile.qualityScore >= 0.55;
    return CalibratedGazeDecision(
      zone: prediction.zone,
      confidence: prediction.confidence,
      signalQuality: result.confidence,
      calibrated: prediction.calibrated,
      actionable: actionable,
      deviating: actionable && deviation,
      reason: prediction.reason,
    );
  }

  void _persist() {
    final profile = _profile;
    if (profile == null) return;
    _storage.write(_key, <String, Object?>{
      'usable': profile.usable,
      'sample_count': profile.sampleCount,
      'zones': profile.zones,
      'center_eye_x': profile.centerEyeX,
      'center_eye_y': profile.centerEyeY,
      'yaw_bias': profile.yawBias,
      'pitch_bias': profile.pitchBias,
      'quality_score': profile.qualityScore,
      'reason': profile.reason,
    });
  }
}

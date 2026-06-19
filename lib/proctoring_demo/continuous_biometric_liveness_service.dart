import 'dart:math' as math;

import 'package:camera/camera.dart';

class ContinuousLivenessResult {
  const ContinuousLivenessResult({
    required this.frameFingerprint,
    required this.lumaMean,
    required this.lumaVariance,
    required this.edgeEnergy,
    required this.motionScore,
    required this.repeatedFrame,
    required this.flatTexture,
    required this.replayOrFreezeLikely,
    required this.spoofRiskScore,
    required this.label,
  });

  final String frameFingerprint;
  final double lumaMean;
  final double lumaVariance;
  final double edgeEnergy;
  final double motionScore;
  final bool repeatedFrame;
  final bool flatTexture;
  final bool replayOrFreezeLikely;
  final double spoofRiskScore;
  final String label;

  Map<String, Object?> toJson() => <String, Object?>{
    'frame_fingerprint': frameFingerprint,
    'luma_mean': lumaMean,
    'luma_variance': lumaVariance,
    'edge_energy': edgeEnergy,
    'motion_score': motionScore,
    'repeated_frame': repeatedFrame,
    'flat_texture': flatTexture,
    'replay_or_freeze_likely': replayOrFreezeLikely,
    'spoof_risk_score': spoofRiskScore,
    'label': label,
  };
}

class ContinuousBiometricLivenessService {
  int _frameCounter = 0;
  String? _lastFingerprint;
  List<int>? _lastGrid;
  int _repeatStreak = 0;
  int _flatTextureStreak = 0;
  final List<double> _motionHistory = <double>[];

  ContinuousLivenessResult? analyse(CameraImage image) {
    _frameCounter++;
    if (_frameCounter % 6 != 0) return null;
    if (image.planes.isEmpty || image.width <= 0 || image.height <= 0) {
      return null;
    }

    final plane = image.planes.first;
    final width = image.width;
    final height = image.height;
    final rowStride = plane.bytesPerRow;
    final bytes = plane.bytes;
    if (bytes.isEmpty || rowStride <= 0) return null;

    const gridW = 12;
    const gridH = 8;
    final grid = <int>[];
    var sum = 0.0;
    var sumSquares = 0.0;
    var edges = 0.0;
    var sampleCount = 0;

    for (var gy = 0; gy < gridH; gy++) {
      final y = ((gy + 0.5) * height / gridH)
          .floor()
          .clamp(0, height - 1)
          .toInt();
      for (var gx = 0; gx < gridW; gx++) {
        final x = ((gx + 0.5) * width / gridW)
            .floor()
            .clamp(0, width - 1)
            .toInt();
        final idx = y * rowStride + x;
        if (idx < 0 || idx >= bytes.length) continue;
        final value = bytes[idx];
        grid.add(value);
        sum += value;
        sumSquares += value * value;
        sampleCount++;
        final rightX = math
            .min(width - 1, x + math.max(1, width ~/ 48))
            .toInt();
        final downY = math
            .min(height - 1, y + math.max(1, height ~/ 48))
            .toInt();
        final rightIdx = y * rowStride + rightX;
        final downIdx = downY * rowStride + x;
        if (rightIdx >= 0 && rightIdx < bytes.length) {
          edges += (value - bytes[rightIdx]).abs();
        }
        if (downIdx >= 0 && downIdx < bytes.length) {
          edges += (value - bytes[downIdx]).abs();
        }
      }
    }

    if (sampleCount < 12) return null;
    final mean = (sum / sampleCount) / 255.0;
    final variance =
        ((sumSquares / sampleCount) - math.pow(sum / sampleCount, 2)) /
        (255.0 * 255.0);
    final edgeEnergy = (edges / math.max(1, sampleCount * 2) / 255.0).clamp(
      0.0,
      1.0,
    );
    final fingerprint = _fingerprintGrid(grid);
    final repeated = fingerprint == _lastFingerprint;
    if (repeated) {
      _repeatStreak++;
    } else {
      _repeatStreak = math.max(0, _repeatStreak - 1);
    }

    final motion = _lastGrid == null ? 0.0 : _gridDistance(_lastGrid!, grid);
    _motionHistory.add(motion);
    if (_motionHistory.length > 18) {
      _motionHistory.removeRange(0, _motionHistory.length - 18);
    }
    final motionAverage = _motionHistory.isEmpty
        ? 0.0
        : _motionHistory.fold<double>(0, (sum, item) => sum + item) /
              _motionHistory.length;

    final flatTexture = variance < 0.006 && edgeEnergy < 0.035;
    if (flatTexture) {
      _flatTextureStreak++;
    } else {
      _flatTextureStreak = math.max(0, _flatTextureStreak - 1);
    }

    final lowMotionTooLong =
        _motionHistory.length >= 8 && motionAverage < 0.008;
    final repeatedFrame = _repeatStreak >= 3 || lowMotionTooLong;
    final replayOrFreezeLikely = repeatedFrame || _flatTextureStreak >= 4;
    var risk = 0.0;
    if (repeatedFrame) risk += 0.45;
    if (_flatTextureStreak >= 4) risk += 0.35;
    if (edgeEnergy < 0.02 && variance < 0.004) risk += 0.15;
    if (mean < 0.07 || mean > 0.92) risk += 0.10;
    risk = risk.clamp(0.0, 1.0);
    final label = replayOrFreezeLikely
        ? repeatedFrame
              ? 'possible_frozen_or_replayed_face'
              : 'possible_photo_or_flat_screen_face'
        : 'continuous_liveness_present';

    _lastFingerprint = fingerprint;
    _lastGrid = grid;

    return ContinuousLivenessResult(
      frameFingerprint: fingerprint,
      lumaMean: mean,
      lumaVariance: variance.clamp(0.0, 1.0),
      edgeEnergy: edgeEnergy,
      motionScore: motionAverage.clamp(0.0, 1.0),
      repeatedFrame: repeatedFrame,
      flatTexture: _flatTextureStreak >= 4,
      replayOrFreezeLikely: replayOrFreezeLikely,
      spoofRiskScore: risk,
      label: label,
    );
  }

  double _gridDistance(List<int> previous, List<int> current) {
    final length = math.min(previous.length, current.length);
    if (length == 0) return 0.0;
    var total = 0.0;
    for (var i = 0; i < length; i++) {
      total += (previous[i] - current[i]).abs();
    }
    return (total / length / 255.0).clamp(0.0, 1.0);
  }

  String _fingerprintGrid(List<int> grid) {
    var hash = 0xcbf29ce484222325;
    const prime = 0x100000001b3;
    for (final value in grid) {
      final bucket = (value / 16).floor().clamp(0, 15);
      hash ^= bucket;
      hash = (hash * prime) & 0xFFFFFFFFFFFFFFFF;
    }
    return hash.toRadixString(16).padLeft(16, '0');
  }
}

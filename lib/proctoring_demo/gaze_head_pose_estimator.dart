import 'dart:math' as math;

import 'package:camera/camera.dart';

class GazeHeadPoseResult {
  const GazeHeadPoseResult({
    required this.gazeX,
    required this.gazeY,
    required this.gazeZ,
    required this.yawProxy,
    required this.pitchProxy,
    required this.rollProxy,
    required this.confidence,
    required this.stableHeadPose,
    required this.lookingAway,
    required this.label,
  });

  final double gazeX;
  final double gazeY;
  final double gazeZ;
  final double yawProxy;
  final double pitchProxy;
  final double rollProxy;
  final double confidence;
  final bool stableHeadPose;
  final bool lookingAway;
  final String label;

  Map<String, Object?> toJson() => <String, Object?>{
        'gaze_vector': <String, double>{
          'x': gazeX,
          'y': gazeY,
          'z': gazeZ,
        },
        'head_pose_proxy': <String, double>{
          'yaw': yawProxy,
          'pitch': pitchProxy,
          'roll': rollProxy,
        },
        'confidence': confidence,
        'stable_head_pose': stableHeadPose,
        'looking_away': lookingAway,
        'label': label,
      };
}

class GazeHeadPoseEstimator {
  int _frameCounter = 0;
  double _lastYaw = 0;
  double _lastPitch = 0;
  double _lastRoll = 0;

  GazeHeadPoseResult? analyse(CameraImage image) {
    _frameCounter++;
    if (_frameCounter % 6 != 0) return null;
    if (image.planes.isEmpty || image.width <= 0 || image.height <= 0) return null;

    final plane = image.planes.first;
    final width = image.width;
    final height = image.height;
    final rowStride = plane.bytesPerRow;
    final bytes = plane.bytes;
    if (bytes.isEmpty || rowStride <= 0) return null;

    var total = 0.0;
    var weightedX = 0.0;
    var weightedY = 0.0;
    var left = 0.0;
    var right = 0.0;
    var top = 0.0;
    var bottom = 0.0;
    var diagonalA = 0.0;
    var diagonalB = 0.0;

    final stepX = math.max(1, width ~/ 36);
    final stepY = math.max(1, height ~/ 28);
    final centerX = width / 2;
    final centerY = height / 2;
    final radiusX = width * 0.38;
    final radiusY = height * 0.42;

    for (var y = 0; y < height; y += stepY) {
      final dy = (y - centerY) / radiusY;
      for (var x = 0; x < width; x += stepX) {
        final dx = (x - centerX) / radiusX;
        if (dx * dx + dy * dy > 1.0) continue;
        final index = y * rowStride + x;
        if (index < 0 || index >= bytes.length) continue;
        final luma = bytes[index] / 255.0;
        final weight = (1.0 - luma).clamp(0.0, 1.0) + 0.04;
        total += weight;
        weightedX += x * weight;
        weightedY += y * weight;
        if (x < centerX) {
          left += weight;
        } else {
          right += weight;
        }
        if (y < centerY) {
          top += weight;
        } else {
          bottom += weight;
        }
        if (x / width > y / height) {
          diagonalA += weight;
        } else {
          diagonalB += weight;
        }
      }
    }

    if (total <= 0.001) return null;
    final gazeX = ((weightedX / total) - centerX) / centerX;
    final gazeY = ((weightedY / total) - centerY) / centerY;
    final yaw = ((right - left) / total).clamp(-1.0, 1.0);
    final pitch = ((bottom - top) / total).clamp(-1.0, 1.0);
    final roll = ((diagonalA - diagonalB) / total).clamp(-1.0, 1.0);
    final movement = ((yaw - _lastYaw).abs() + (pitch - _lastPitch).abs() + (roll - _lastRoll).abs()) / 3.0;
    _lastYaw = yaw;
    _lastPitch = pitch;
    _lastRoll = roll;

    final gazeMagnitude = math.sqrt(gazeX * gazeX + gazeY * gazeY);
    final headMagnitude = math.sqrt(yaw * yaw + pitch * pitch + roll * roll);
    final lookingAway = gazeMagnitude > 0.34 || yaw.abs() > 0.30 || pitch.abs() > 0.34;
    final stableHeadPose = movement < 0.18 && headMagnitude < 0.68;
    final confidence = (0.55 + math.min(total / 220.0, 0.40) - math.min(movement, 0.22)).clamp(0.0, 1.0);
    final label = lookingAway
        ? 'possible_looking_away'
        : stableHeadPose
            ? 'focused_forward'
            : 'head_motion_detected';

    return GazeHeadPoseResult(
      gazeX: gazeX.clamp(-1.0, 1.0),
      gazeY: gazeY.clamp(-1.0, 1.0),
      gazeZ: 1.0,
      yawProxy: yaw,
      pitchProxy: pitch,
      rollProxy: roll,
      confidence: confidence,
      stableHeadPose: stableHeadPose,
      lookingAway: lookingAway,
      label: label,
    );
  }
}

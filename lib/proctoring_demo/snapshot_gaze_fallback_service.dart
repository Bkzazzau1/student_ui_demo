import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

class SnapshotGazeFallbackResult {
  const SnapshotGazeFallbackResult({
    required this.ready,
    required this.centerX,
    required this.centerY,
    required this.baselineX,
    required this.baselineY,
    required this.shiftX,
    required this.shiftY,
    required this.shiftScore,
    required this.headPoseShiftLikely,
    required this.label,
  });

  final bool ready;
  final double centerX;
  final double centerY;
  final double baselineX;
  final double baselineY;
  final double shiftX;
  final double shiftY;
  final double shiftScore;
  final bool headPoseShiftLikely;
  final String label;

  Map<String, Object?> toJson() => <String, Object?>{
        'ready': ready,
        'center_x': centerX,
        'center_y': centerY,
        'baseline_x': baselineX,
        'baseline_y': baselineY,
        'shift_x': shiftX,
        'shift_y': shiftY,
        'shift_score': shiftScore,
        'head_pose_shift_likely': headPoseShiftLikely,
        'label': label,
        'source': 'snapshot_fallback',
      };
}

class SnapshotGazeFallbackService {
  static const int _baselineWindow = 3;
  final List<_Point> _baselineSamples = <_Point>[];
  _Point? _baseline;

  SnapshotGazeFallbackResult? analyseJpeg(Uint8List bytes) {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return null;
    final resized = img.copyResize(decoded, width: 96);
    final width = resized.width;
    final height = resized.height;
    if (width < 24 || height < 24) return null;

    final center = _estimateHeadCenter(resized);
    if (center == null) return null;

    if (_baseline == null) {
      _baselineSamples.add(center);
      if (_baselineSamples.length >= _baselineWindow) {
        _baseline = _Point(
          _baselineSamples.map((item) => item.x).reduce((a, b) => a + b) /
              _baselineSamples.length,
          _baselineSamples.map((item) => item.y).reduce((a, b) => a + b) /
              _baselineSamples.length,
        );
      }
      return SnapshotGazeFallbackResult(
        ready: false,
        centerX: center.x,
        centerY: center.y,
        baselineX: _baseline?.x ?? center.x,
        baselineY: _baseline?.y ?? center.y,
        shiftX: 0,
        shiftY: 0,
        shiftScore: 0,
        headPoseShiftLikely: false,
        label: 'learning_head_position',
      );
    }

    final baseline = _baseline!;
    final shiftX = center.x - baseline.x;
    final shiftY = center.y - baseline.y;
    final shiftScore = math.sqrt((shiftX * shiftX) + (shiftY * shiftY));
    final headPoseShiftLikely = shiftX.abs() >= 0.16 ||
        shiftY.abs() >= 0.13 ||
        shiftScore >= 0.18;

    return SnapshotGazeFallbackResult(
      ready: true,
      centerX: center.x,
      centerY: center.y,
      baselineX: baseline.x,
      baselineY: baseline.y,
      shiftX: shiftX,
      shiftY: shiftY,
      shiftScore: shiftScore,
      headPoseShiftLikely: headPoseShiftLikely,
      label: headPoseShiftLikely
          ? 'head_or_gaze_shift_detected'
          : 'head_position_stable',
    );
  }

  _Point? _estimateHeadCenter(img.Image image) {
    final width = image.width;
    final height = image.height;
    final xStart = (width * 0.18).round();
    final xEnd = (width * 0.82).round();
    final yStart = (height * 0.08).round();
    final yEnd = (height * 0.72).round();

    var weightedX = 0.0;
    var weightedY = 0.0;
    var totalWeight = 0.0;

    for (var y = yStart + 1; y < yEnd - 1; y += 2) {
      for (var x = xStart + 1; x < xEnd - 1; x += 2) {
        final pixel = image.getPixel(x, y);
        final left = image.getPixel(x - 1, y);
        final right = image.getPixel(x + 1, y);
        final up = image.getPixel(x, y - 1);
        final down = image.getPixel(x, y + 1);

        final luma = _luma(pixel);
        final edge = ((_luma(left) - _luma(right)).abs() +
                (_luma(up) - _luma(down)).abs()) /
            2.0;
        final saturation = _saturation(pixel);
        final skinLike = saturation >= 0.10 && saturation <= 0.72 && luma >= 30 && luma <= 230;
        final darkFeature = luma < 95 && edge > 10;
        final edgeFeature = edge > 18;
        if (!skinLike && !darkFeature && !edgeFeature) continue;

        final yBias = 1.0 - ((y / height) - 0.38).abs().clamp(0.0, 0.8);
        final weight = (edge * 0.55) + (skinLike ? 18.0 : 0.0) + (darkFeature ? 12.0 : 0.0);
        final finalWeight = weight * yBias;
        weightedX += (x / width) * finalWeight;
        weightedY += (y / height) * finalWeight;
        totalWeight += finalWeight;
      }
    }

    if (totalWeight < 80) return null;
    return _Point(
      (weightedX / totalWeight).clamp(0.0, 1.0),
      (weightedY / totalWeight).clamp(0.0, 1.0),
    );
  }

  double _luma(img.Pixel pixel) {
    return (0.299 * pixel.r) + (0.587 * pixel.g) + (0.114 * pixel.b);
  }

  double _saturation(img.Pixel pixel) {
    final r = pixel.r / 255.0;
    final g = pixel.g / 255.0;
    final b = pixel.b / 255.0;
    final maxValue = math.max(r, math.max(g, b));
    final minValue = math.min(r, math.min(g, b));
    if (maxValue == 0) return 0;
    return (maxValue - minValue) / maxValue;
  }
}

class _Point {
  const _Point(this.x, this.y);
  final double x;
  final double y;
}

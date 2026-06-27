import 'dart:math' as math;

import 'package:camera/camera.dart';

import 'native_vision_bridge.dart';

class VisualReflectionShadowResult {
  const VisualReflectionShadowResult({
    required this.brightHotspotScore,
    required this.shadowShiftScore,
    required this.lowerFrameActivity,
    required this.sideReflectionScore,
    required this.screenGlowLikely,
    required this.mirrorOrGlassLikely,
    required this.offscreenInteractionLikely,
    required this.visualRiskScore,
    required this.label,
    this.nativeFrameQuality,
  });

  final double brightHotspotScore;
  final double shadowShiftScore;
  final double lowerFrameActivity;
  final double sideReflectionScore;
  final bool screenGlowLikely;
  final bool mirrorOrGlassLikely;
  final bool offscreenInteractionLikely;
  final double visualRiskScore;
  final String label;
  final NativeVisionFrameQualitySnapshot? nativeFrameQuality;

  Map<String, Object?> toJson() => <String, Object?>{
        'bright_hotspot_score': brightHotspotScore,
        'shadow_shift_score': shadowShiftScore,
        'lower_frame_activity': lowerFrameActivity,
        'side_reflection_score': sideReflectionScore,
        'screen_glow_likely': screenGlowLikely,
        'mirror_or_glass_likely': mirrorOrGlassLikely,
        'offscreen_interaction_likely': offscreenInteractionLikely,
        'visual_risk_score': visualRiskScore,
        'label': label,
        if (nativeFrameQuality != null)
          'native_frame_quality': nativeFrameQuality!.toJson(),
      };
}

class VisualReflectionShadowService {
  VisualReflectionShadowService({NativeVisionBridge? nativeVision})
      : _nativeVision = nativeVision ?? const GeneratedNativeVisionBridge();

  final NativeVisionBridge _nativeVision;

  int _frameCounter = 0;
  List<double>? _lastGrid;
  final List<double> _hotspotHistory = <double>[];
  final List<double> _shadowHistory = <double>[];
  final List<double> _lowerMotionHistory = <double>[];

  VisualReflectionShadowResult? analyse(CameraImage image) {
    _frameCounter++;
    if (_frameCounter % 6 != 0) return null;
    if (image.planes.isEmpty || image.width <= 0 || image.height <= 0) {
      return null;
    }

    final nativeQuality = _nativeVision.analyzeFrameQuality(image);
    final plane = image.planes.first;
    final width = image.width;
    final height = image.height;
    final rowStride = plane.bytesPerRow;
    final bytes = plane.bytes;
    if (bytes.isEmpty || rowStride <= 0) return null;

    const gridW = 16;
    const gridH = 12;
    final grid = <double>[];
    var brightest = 0.0;
    var darkest = 1.0;
    var centerTotal = 0.0;
    var centerCount = 0;
    var sideTotal = 0.0;
    var sideCount = 0;
    var lowerTotal = 0.0;
    var lowerCount = 0;
    var localContrastTotal = 0.0;
    var localContrastCount = 0;

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
        final value = bytes[idx] / 255.0;
        grid.add(value);
        brightest = math.max(brightest, value);
        darkest = math.min(darkest, value);
        final centerX = gx >= 4 && gx <= 11;
        final centerY = gy >= 2 && gy <= 8;
        if (centerX && centerY) {
          centerTotal += value;
          centerCount++;
        }
        if (gx <= 2 || gx >= gridW - 3) {
          sideTotal += value;
          sideCount++;
        }
        if (gy >= gridH - 4) {
          lowerTotal += value;
          lowerCount++;
        }
        if (gx > 0) {
          final left = grid[grid.length - 2];
          localContrastTotal += (value - left).abs();
          localContrastCount++;
        }
      }
    }

    if (grid.length < 24) return null;
    final centerMean = centerCount == 0 ? 0.0 : centerTotal / centerCount;
    final sideMean = sideCount == 0 ? 0.0 : sideTotal / sideCount;
    final lowerMean = lowerCount == 0 ? 0.0 : lowerTotal / lowerCount;
    final contrast = localContrastCount == 0
        ? 0.0
        : localContrastTotal / localContrastCount;
    final hotspotScore = (brightest - centerMean).clamp(0.0, 1.0).toDouble();
    final sideReflectionScore =
        (sideMean - centerMean).clamp(0.0, 1.0).toDouble();
    final lowerMotion = _lastGrid == null
        ? 0.0
        : _regionMotion(_lastGrid!, grid, gridW, gridH, lowerOnly: true);
    final fullMotion = _lastGrid == null
        ? 0.0
        : _regionMotion(_lastGrid!, grid, gridW, gridH, lowerOnly: false);
    final shadowShift =
        ((brightest - darkest) * contrast).clamp(0.0, 1.0).toDouble();

    _push(_hotspotHistory, hotspotScore, 18);
    _push(_shadowHistory, shadowShift, 18);
    _push(_lowerMotionHistory, lowerMotion, 18);

    final hotspotAverage = _average(_hotspotHistory);
    final shadowAverage = _average(_shadowHistory);
    final lowerAverage = _average(_lowerMotionHistory);
    final suddenGlow = hotspotScore > 0.38 && hotspotScore > hotspotAverage + 0.12;
    final sharpShadow = shadowShift > 0.12 && shadowShift > shadowAverage + 0.05;
    final lowerInteraction = lowerAverage > 0.035 && lowerMotion > fullMotion * 1.35;
    final sideReflection = sideReflectionScore > 0.18 && sideMean > 0.42;

    var risk = 0.0;
    if (suddenGlow) risk += 0.35;
    if (sharpShadow) risk += 0.22;
    if (lowerInteraction) risk += 0.28;
    if (sideReflection) risk += 0.25;
    if (lowerMean > centerMean + 0.16 && lowerMotion > 0.025) risk += 0.10;
    risk = risk.clamp(0.0, 1.0).toDouble();

    final nativeQualityNeedsAttention = nativeQuality != null &&
        !nativeQuality.isUsable &&
        (nativeQuality.reason.contains('dark') ||
            nativeQuality.reason.contains('overexposed') ||
            nativeQuality.reason.contains('contrast') ||
            nativeQuality.reason.contains('blurry'));

    final label = suddenGlow
        ? 'possible_phone_screen_glow'
        : sideReflection
            ? 'possible_mirror_or_glass_reflection'
            : lowerInteraction
                ? 'possible_offscreen_hand_or_phone_interaction'
                : sharpShadow
                    ? 'sharp_shadow_or_light_shift_detected'
                    : nativeQualityNeedsAttention
                        ? 'native_frame_quality_needs_attention'
                        : 'visual_integrity_normal';

    _lastGrid = grid;
    return VisualReflectionShadowResult(
      brightHotspotScore: hotspotScore,
      shadowShiftScore: shadowShift,
      lowerFrameActivity: lowerAverage.clamp(0.0, 1.0).toDouble(),
      sideReflectionScore: sideReflectionScore,
      screenGlowLikely: suddenGlow,
      mirrorOrGlassLikely: sideReflection,
      offscreenInteractionLikely: lowerInteraction,
      visualRiskScore: risk,
      label: label,
      nativeFrameQuality: nativeQuality,
    );
  }

  double _regionMotion(
    List<double> previous,
    List<double> current,
    int gridW,
    int gridH, {
    required bool lowerOnly,
  }) {
    final length = math.min(previous.length, current.length);
    if (length == 0) return 0.0;
    var total = 0.0;
    var count = 0;
    for (var i = 0; i < length; i++) {
      final gy = i ~/ gridW;
      if (lowerOnly && gy < gridH - 4) continue;
      total += (previous[i] - current[i]).abs();
      count++;
    }
    if (count == 0) return 0.0;
    return (total / count).clamp(0.0, 1.0).toDouble();
  }

  void _push(List<double> values, double value, int maxLength) {
    values.add(value);
    if (values.length > maxLength) {
      values.removeRange(0, values.length - maxLength);
    }
  }

  double _average(List<double> values) {
    if (values.isEmpty) return 0.0;
    return values.fold<double>(0, (sum, item) => sum + item) / values.length;
  }
}

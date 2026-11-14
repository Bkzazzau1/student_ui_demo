import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:students_ui_demo/proctoring_demo/continuous_biometric_liveness_service.dart';

/// An Android luma frame: a bright "face" disc on a darker background plus
/// per-pixel sensor noise of [noise] grey levels.
CameraImage _frame(math.Random random, {required int noise}) {
  const width = 96;
  const height = 72;
  final luma = Uint8List(width * height);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final dx = x - width / 2;
      final dy = y - height / 2;
      final base = dx * dx + dy * dy < 400 ? 170 : 70;
      final jitter = noise == 0 ? 0 : random.nextInt(2 * noise + 1) - noise;
      luma[y * width + x] = (base + jitter).clamp(0, 255);
    }
  }
  // ignore: deprecated_member_use
  return CameraImage.fromPlatformData(<String, Object?>{
    'format': 35, // YUV_420_888
    'width': width,
    'height': height,
    'planes': [
      {
        'bytes': luma,
        'bytesPerRow': width,
        'bytesPerPixel': 1,
        'width': width,
        'height': height,
      },
    ],
  });
}

void main() {
  setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.android);
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  ContinuousLivenessResult? last(Iterable<CameraImage> frames) {
    final service = ContinuousBiometricLivenessService();
    ContinuousLivenessResult? result;
    var flagged = false;
    for (final frame in frames) {
      final value = service.analyse(frame);
      if (value != null) {
        result = value;
        flagged = flagged || value.replayOrFreezeLikely;
      }
    }
    expect(result, isNotNull);
    return flagged ? result : null;
  }

  test('a student sitting still with a quiet camera is not "frozen"', () {
    final random = math.Random(1);
    // One grey level of sensor noise: less than the old 0.008 motion floor.
    final frames = [for (var i = 0; i < 120; i++) _frame(random, noise: 1)];
    expect(last(frames), isNull);
  });

  test('a frozen feed (identical frames) is flagged', () {
    final frozen = _frame(math.Random(2), noise: 1);
    final flagged = last([for (var i = 0; i < 30; i++) frozen]);
    expect(flagged, isNotNull);
    expect(flagged!.repeatedFrame, isTrue);
  });
}

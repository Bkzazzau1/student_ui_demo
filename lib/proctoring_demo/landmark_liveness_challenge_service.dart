import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../rust/api/liveness_challenge.dart';

class LivenessChallengeSession {
  LivenessChallengeSession._({
    required this.challenge,
    required this.startedAtMs,
    required this.deadlineMs,
  });

  factory LivenessChallengeSession.start({
    math.Random? random,
    DateTime? now,
    Duration duration = const Duration(seconds: 8),
    List<String>? challenges,
  }) {
    final pool = challenges ?? availableChallenges();
    final generator = random ?? math.Random.secure();
    final started = (now ?? DateTime.now()).toUtc().millisecondsSinceEpoch;
    return LivenessChallengeSession._(
      challenge: pool[generator.nextInt(pool.length)],
      startedAtMs: started,
      deadlineMs: started + duration.inMilliseconds,
    );
  }

  /// Challenges this device can check. Windows reads a still photo about
  /// every 0.7 s, which catches a normal blink only 7-24% of the time, so it
  /// uses head movements only.
  static List<String> availableChallenges({TargetPlatform? platform}) {
    final target = platform ?? defaultTargetPlatform;
    if (!kIsWeb && target == TargetPlatform.windows) {
      return const <String>['turn_left', 'turn_right', 'look_up'];
    }
    return const <String>['blink', 'turn_left', 'turn_right', 'look_up'];
  }

  final String challenge;
  final int startedAtMs;
  final int deadlineMs;
  final List<LivenessObservation> _observations = <LivenessObservation>[];
  String? _lastSignature;
  _Face? _lastFace;

  String get instruction => switch (challenge) {
    'blink' => 'Blink once, then keep your eyes open.',
    'turn_left' => 'Slowly turn your head to the left.',
    'turn_right' => 'Slowly turn your head to the right.',
    'look_up' => 'Slowly look upward.',
    _ => 'Keep your face visible.',
  };

  int get observationCount => _observations.length;

  /// The most recent usable observation, if any.
  LivenessObservation? get lastObservation =>
      _observations.isEmpty ? null : _observations.last;

  /// Adds one frame's landmarks. Landmark x/y are normalized to the frame;
  /// [imageWidth] and [imageHeight] (the upright frame the landmarks were
  /// measured in) turn them into pixels, so eye openness and head pitch do
  /// not change with the frame's shape. Without them, the payload's
  /// `image_width`/`image_height` are used if present.
  LivenessChallengeResult? addLandmarkPayload(
    Map<String, Object?> payload, {
    required int timestampMs,
    int? imageWidth,
    int? imageHeight,
    bool flatTexture = false,
  }) {
    final width = (imageWidth ?? _int(payload['image_width']) ?? 1).toDouble();
    final height = (imageHeight ?? _int(payload['image_height']) ?? 1)
        .toDouble();
    final points = _readPoints(
      payload['landmarks'] ?? payload['face_landmarks'],
      width <= 0 ? 1 : width,
      height <= 0 ? 1 : height,
    );
    if (points.length < 468) return null;
    final face = _Face.from(points);
    if (face == null) return null;
    final confidence = _number(payload['confidence']);
    final signature = face.signature;
    _observations.add(
      LivenessObservation(
        timestampMs: timestampMs,
        faceConfidence: confidence,
        leftEyeOpen: face.leftEyeOpen,
        rightEyeOpen: face.rightEyeOpen,
        headYaw: face.yaw,
        headPitch: face.pitch,
        motionScore: face.motionFrom(_lastFace),
        repeatedFrame: signature == _lastSignature,
        flatTexture: flatTexture,
      ),
    );
    if (_observations.length > 90) _observations.removeAt(0);
    _lastSignature = signature;
    _lastFace = face;
    return evaluate(nowMs: timestampMs);
  }

  LivenessChallengeResult evaluate({int? nowMs}) => analyzeLivenessChallenge(
    challenge: challenge,
    observations: List<LivenessObservation>.unmodifiable(_observations),
    startedAtMs: startedAtMs,
    deadlineMs: deadlineMs,
    nowMs: nowMs ?? DateTime.now().toUtc().millisecondsSinceEpoch,
  );

  Map<int, _Point> _readPoints(Object? raw, double width, double height) {
    if (raw is! Iterable) return const {};
    final result = <int, _Point>{};
    for (final value in raw.whereType<Map>()) {
      final item = Map<String, Object?>.from(value);
      final index = (item['index'] as num?)?.toInt();
      if (index == null || item['name'] != null) continue;
      result[index] = _Point(
        _number(item['x']) * width,
        _number(item['y']) * height,
      );
    }
    return result;
  }

  int? _int(Object? value) =>
      value is num ? value.round() : int.tryParse('${value ?? ''}');

  double _number(Object? value) =>
      value is num ? value.toDouble() : double.tryParse('$value') ?? 0.0;
}

/// Liveness features of one face, in pixels.
class _Face {
  _Face._({
    required this.points,
    required this.eyeCenter,
    required this.eyeSpan,
    required this.leftEyeOpen,
    required this.rightEyeOpen,
    required this.yaw,
    required this.pitch,
  });

  static const List<int> _trackedPoints = <int>[
    1, 33, 133, 263, 362, 13, 14, 159, 145, 386, 374, //
  ];

  static _Face? from(Map<int, _Point> points) {
    for (final index in _trackedPoints) {
      if (!points.containsKey(index)) return null;
    }
    final leftEye = _Point.mid(points[33]!, points[133]!);
    final rightEye = _Point.mid(points[362]!, points[263]!);
    final eyeCenter = _Point.mid(leftEye, rightEye);
    final eyeSpan = leftEye.distanceTo(rightEye);
    if (eyeSpan < 1e-6) return null;
    // Head pose on the eye axis, so tilting the head (or a photo) sideways
    // in the image plane is not read as a turn.
    final axisX = _Point(
      (rightEye.x - leftEye.x) / eyeSpan,
      (rightEye.y - leftEye.y) / eyeSpan,
    );
    final axisY = _Point(-axisX.y, axisX.x);
    final nose = points[1]!.minus(eyeCenter);
    final mouth = _Point.mid(points[13]!, points[14]!).minus(eyeCenter);
    final yaw = (nose.dot(axisX) / eyeSpan * 2.0).clamp(-1.0, 1.0);
    final expectedNose = mouth.dot(axisY) * 0.52;
    final pitch = ((nose.dot(axisY) - expectedNose) / eyeSpan * 2.0).clamp(
      -1.0,
      1.0,
    );
    return _Face._(
      points: points,
      eyeCenter: eyeCenter,
      eyeSpan: eyeSpan,
      leftEyeOpen: _eyeAspect(points, 33, 133, 159, 145),
      rightEyeOpen: _eyeAspect(points, 362, 263, 386, 374),
      yaw: yaw,
      pitch: pitch,
    );
  }

  final Map<int, _Point> points;
  final _Point eyeCenter;
  final double eyeSpan;
  final double leftEyeOpen;
  final double rightEyeOpen;
  final double yaw;
  final double pitch;

  /// Mean landmark movement since [previous], in eye spans.
  double motionFrom(_Face? previous) {
    if (previous == null) return 0.0;
    var total = 0.0;
    for (final index in _trackedPoints) {
      total += points[index]!.distanceTo(previous.points[index]!);
    }
    return (total / _trackedPoints.length / eyeSpan).clamp(0.0, 1.0);
  }

  /// Landmark layout quantized to 1/50 of the eye span: identical for a
  /// frozen or replayed frame, different for any real camera frame.
  String get signature => _trackedPoints
      .map((index) {
        final point = points[index]!.minus(eyeCenter);
        return '${(point.x / eyeSpan * 50).round()}:'
            '${(point.y / eyeSpan * 50).round()}';
      })
      .join('|');

  static double _eyeAspect(
    Map<int, _Point> points,
    int outer,
    int inner,
    int upper,
    int lower,
  ) {
    final horizontal = points[outer]!.distanceTo(points[inner]!);
    if (horizontal < 1e-6) return 0.0;
    return (points[upper]!.distanceTo(points[lower]!) / horizontal).clamp(
      0.0,
      1.0,
    );
  }
}

class _Point {
  const _Point(this.x, this.y);

  factory _Point.mid(_Point a, _Point b) =>
      _Point((a.x + b.x) / 2, (a.y + b.y) / 2);

  final double x;
  final double y;

  _Point minus(_Point other) => _Point(x - other.x, y - other.y);

  double dot(_Point other) => x * other.x + y * other.y;

  double distanceTo(_Point other) =>
      math.sqrt(math.pow(x - other.x, 2) + math.pow(y - other.y, 2));
}

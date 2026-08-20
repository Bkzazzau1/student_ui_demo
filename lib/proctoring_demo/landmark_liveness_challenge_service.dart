import 'dart:math' as math;

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
  }) {
    const challenges = <String>['blink', 'turn_left', 'turn_right', 'look_up'];
    final generator = random ?? math.Random.secure();
    final started = (now ?? DateTime.now()).toUtc().millisecondsSinceEpoch;
    return LivenessChallengeSession._(
      challenge: challenges[generator.nextInt(challenges.length)],
      startedAtMs: started,
      deadlineMs: started + duration.inMilliseconds,
    );
  }

  final String challenge;
  final int startedAtMs;
  final int deadlineMs;
  final List<LivenessObservation> _observations = <LivenessObservation>[];
  String? _lastSignature;
  Map<int, _Point>? _lastPoints;

  String get instruction => switch (challenge) {
    'blink' => 'Blink once, then keep your eyes open.',
    'turn_left' => 'Slowly turn your head to the left.',
    'turn_right' => 'Slowly turn your head to the right.',
    'look_up' => 'Slowly look upward.',
    _ => 'Keep your face visible.',
  };

  int get observationCount => _observations.length;

  LivenessChallengeResult? addLandmarkPayload(
    Map<String, Object?> payload, {
    required int timestampMs,
    bool flatTexture = false,
  }) {
    final points = _readPoints(
      payload['landmarks'] ?? payload['face_landmarks'],
    );
    if (points.length < 468) return null;
    final confidence = _number(payload['confidence']);
    final leftEyeOpen = _eyeAspect(points, 33, 133, 159, 145);
    final rightEyeOpen = _eyeAspect(points, 362, 263, 386, 374);
    final pose = _headPose(points);
    final signature = _signature(points);
    final motion = _motion(points, _lastPoints);
    _observations.add(
      LivenessObservation(
        timestampMs: timestampMs,
        faceConfidence: confidence,
        leftEyeOpen: leftEyeOpen,
        rightEyeOpen: rightEyeOpen,
        headYaw: pose.x,
        headPitch: pose.y,
        motionScore: motion,
        repeatedFrame: signature == _lastSignature,
        flatTexture: flatTexture,
      ),
    );
    if (_observations.length > 90) _observations.removeAt(0);
    _lastSignature = signature;
    _lastPoints = points;
    return evaluate(nowMs: timestampMs);
  }

  LivenessChallengeResult evaluate({int? nowMs}) => analyzeLivenessChallenge(
    challenge: challenge,
    observations: List<LivenessObservation>.unmodifiable(_observations),
    startedAtMs: startedAtMs,
    deadlineMs: deadlineMs,
    nowMs: nowMs ?? DateTime.now().toUtc().millisecondsSinceEpoch,
  );

  Map<int, _Point> _readPoints(Object? raw) {
    if (raw is! Iterable) return const {};
    final result = <int, _Point>{};
    for (final value in raw.whereType<Map>()) {
      final item = Map<String, Object?>.from(value);
      final index = (item['index'] as num?)?.toInt();
      if (index == null) continue;
      result[index] = _Point(_number(item['x']), _number(item['y']));
    }
    return result;
  }

  double _eyeAspect(
    Map<int, _Point> points,
    int outer,
    int inner,
    int upper,
    int lower,
  ) {
    final horizontal = _distance(points[outer]!, points[inner]!);
    if (horizontal < 0.0001) return 0.0;
    return (_distance(points[upper]!, points[lower]!) / horizontal).clamp(
      0.0,
      1.0,
    );
  }

  _Point _headPose(Map<int, _Point> points) {
    final leftEye = _average(points[33]!, points[133]!);
    final rightEye = _average(points[362]!, points[263]!);
    final eyeCenter = _average(leftEye, rightEye);
    final eyeSpan = _distance(leftEye, rightEye).clamp(0.0001, 2.0);
    final nose = points[1]!;
    final mouth = _average(points[13]!, points[14]!);
    final yaw = ((nose.x - eyeCenter.x) / eyeSpan * 2.0).clamp(-1.0, 1.0);
    final expectedNoseY = eyeCenter.y + (mouth.y - eyeCenter.y) * 0.52;
    final pitch = ((nose.y - expectedNoseY) / eyeSpan * 2.0).clamp(-1.0, 1.0);
    return _Point(yaw, pitch);
  }

  double _motion(Map<int, _Point> current, Map<int, _Point>? previous) {
    if (previous == null) return 0.0;
    const indices = <int>[1, 33, 133, 263, 362, 13, 14, 159, 145, 386, 374];
    var total = 0.0;
    var count = 0;
    for (final index in indices) {
      final before = previous[index];
      final after = current[index];
      if (before == null || after == null) continue;
      total += _distance(before, after);
      count++;
    }
    return count == 0 ? 0.0 : (total / count).clamp(0.0, 1.0);
  }

  String _signature(Map<int, _Point> points) {
    const indices = <int>[1, 33, 133, 263, 362, 13, 14, 159, 145, 386, 374];
    return indices
        .map((index) {
          final point = points[index]!;
          return '${(point.x * 250).round()}:${(point.y * 250).round()}';
        })
        .join('|');
  }

  _Point _average(_Point a, _Point b) =>
      _Point((a.x + b.x) / 2, (a.y + b.y) / 2);

  double _distance(_Point a, _Point b) =>
      math.sqrt(math.pow(a.x - b.x, 2) + math.pow(a.y - b.y, 2));

  double _number(Object? value) =>
      value is num ? value.toDouble() : double.tryParse('$value') ?? 0.0;
}

class _Point {
  const _Point(this.x, this.y);

  final double x;
  final double y;
}

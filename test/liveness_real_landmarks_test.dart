// Liveness challenges on real face landmarks through the real Dart geometry
// and the real Rust evaluator.
//
// Fixture: test/fixtures/liveness/real_landmark_sequences.json (see its
// `source`). Each scenario is a sequence of frames with the 11 landmark
// points the liveness code reads, normalized to a frame of size w x h.
//
// Before the fixes: a still photo turned ~12 degrees passed "turn" 10/10,
// a frontal photo tilted sideways passed 17/20, and blinks failed for most
// faces in portrait frames (4/25 at 9:16).

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:students_ui_demo/proctoring_demo/landmark_liveness_challenge_service.dart';
import 'package:students_ui_demo/rust/brain_core_runtime.dart';

class _Pick implements math.Random {
  _Pick(this.index);

  final int index;

  @override
  int nextInt(int max) => index;

  @override
  double nextDouble() => 0;

  @override
  bool nextBool() => false;
}

const _all = <String>['blink', 'turn_left', 'turn_right', 'look_up'];

Map<String, Object?> _payload(Map<String, Object?> frame, List<int> tracked) {
  final p = (frame['p']! as List).cast<num>();
  final byIndex = <int, (double, double)>{
    for (var i = 0; i < tracked.length; i++)
      tracked[i]: (p[2 * i].toDouble(), p[2 * i + 1].toDouble()),
  };
  // The session needs a full mesh; untracked points are not read.
  return <String, Object?>{
    'confidence': frame['conf'],
    'landmarks': <Map<String, Object?>>[
      for (var i = 0; i < 478; i++)
        <String, Object?>{
          'index': i,
          'x': byIndex[i]?.$1 ?? 0.5,
          'y': byIndex[i]?.$2 ?? 0.5,
        },
    ],
  };
}

bool _passes(Map<String, Object?> scenario, List<int> tracked) {
  final challenge = scenario['challenge']! as String;
  final session = LivenessChallengeSession.start(
    random: _Pick(_all.indexOf(challenge)),
    now: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    duration: const Duration(seconds: 15),
    challenges: _all,
  );
  var passed = false;
  for (final raw in scenario['frames']! as List) {
    final frame = Map<String, Object?>.from(raw as Map);
    final result = session.addLandmarkPayload(
      _payload(frame, tracked),
      timestampMs: (frame['t']! as num).toInt(),
      imageWidth: (frame['w']! as num).toInt(),
      imageHeight: (frame['h']! as num).toInt(),
    );
    if (result?.state == 'live_challenge_passed') passed = true;
  }
  return passed;
}

void main() {
  late List<int> tracked;
  late Map<String, List<Map<String, Object?>>> byName;

  setUpAll(() async {
    await BrainCoreRuntime.ensureInitialized();
    final doc =
        jsonDecode(
              File(
                'test/fixtures/liveness/real_landmark_sequences.json',
              ).readAsStringSync(),
            )
            as Map<String, Object?>;
    tracked = (doc['tracked_indices']! as List).cast<int>();
    byName = <String, List<Map<String, Object?>>>{};
    for (final raw in doc['scenarios']! as List) {
      final scenario = Map<String, Object?>.from(raw as Map);
      byName.putIfAbsent(scenario['name']! as String, () => []).add(scenario);
    }
  });

  int passCount(String name) =>
      byName[name]!.where((scenario) => _passes(scenario, tracked)).length;

  test('photo attacks never pass a challenge', () {
    for (final name in const [
      'static_identical_photo_turned',
      'static_identical_photo_frontal',
      'photo_noisy_recapture',
      'photo_rolled_cw',
      'photo_rolled_ccw',
    ]) {
      expect(passCount(name), 0, reason: name);
    }
  });

  test('real 20 degree head turns pass', () {
    expect(passCount('live_turn_+20deg'), byName['live_turn_+20deg']!.length);
    expect(passCount('live_turn_-20deg'), byName['live_turn_-20deg']!.length);
  });

  test('a real 25 degree look-up passes', () {
    final scenarios = byName['live_look_up_+25deg']!;
    expect(passCount('live_look_up_+25deg'), greaterThanOrEqualTo(4));
    expect(scenarios.length, 5);
  });

  test('blinks pass in every frame shape, landscape and portrait', () {
    for (final shape in const [
      '250x250',
      '640x480',
      '1280x720',
      '480x640',
      '480x720',
      '720x1280',
    ]) {
      final name = 'blink_shape_$shape';
      expect(
        passCount(name),
        greaterThanOrEqualTo(byName[name]!.length - 1),
        reason: shape,
      );
    }
  });

  test('Windows does not ask for a blink', () {
    expect(
      LivenessChallengeSession.availableChallenges(
        platform: TargetPlatform.windows,
      ),
      isNot(contains('blink')),
    );
    expect(
      LivenessChallengeSession.availableChallenges(
        platform: TargetPlatform.android,
      ),
      contains('blink'),
    );
  });
}

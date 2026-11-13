import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:students_ui_demo/exam_demo/continuous_identity_policy.dart';

void main() {
  group('ContinuousIdentityPolicy', () {
    test('one "no" asks for a quick silent follow-up, two in a row pause', () {
      final policy = ContinuousIdentityPolicy();
      final first = policy.record(PassiveIdentityDecision.mismatch);
      expect(first.action, IdentityMonitorAction.followUpSoon);
      expect(first.requiresExplicitCheck, isFalse);

      final second = policy.record(PassiveIdentityDecision.mismatch);
      expect(second.action, IdentityMonitorAction.pauseForRecheck);
      expect(second.requiresExplicitCheck, isTrue);
    });

    test('a pass clears earlier concerns', () {
      final policy = ContinuousIdentityPolicy();
      policy.record(PassiveIdentityDecision.mismatch);
      final cleared = policy.record(PassiveIdentityDecision.verified);
      expect(cleared.action, IdentityMonitorAction.none);
      expect(policy.mismatchOccasions, 0);
      expect(
        policy.record(PassiveIdentityDecision.mismatch).action,
        IdentityMonitorAction.followUpSoon,
      );
    });

    test('an unclear check after a "no" keeps the follow-up going', () {
      final policy = ContinuousIdentityPolicy();
      policy.record(PassiveIdentityDecision.mismatch);
      final unclear = policy.record(PassiveIdentityDecision.inconclusive);
      expect(unclear.action, IdentityMonitorAction.followUpSoon);
      expect(
        policy.record(PassiveIdentityDecision.mismatch).requiresExplicitCheck,
        isTrue,
      );
    });

    test('identity cannot stay unconfirmed indefinitely', () {
      final policy = ContinuousIdentityPolicy(maxInconclusiveStreak: 3);
      expect(
        policy.record(PassiveIdentityDecision.inconclusive).action,
        IdentityMonitorAction.none,
      );
      policy.record(PassiveIdentityDecision.inconclusive);
      expect(
        policy.record(PassiveIdentityDecision.inconclusive).action,
        IdentityMonitorAction.pauseForRecheck,
      );
    });
  });

  group('IdentityCheckScheduler', () {
    test('times stay inside their windows and vary', () {
      final scheduler = IdentityCheckScheduler(random: math.Random(7));
      final regular = <Duration>{};
      for (var i = 0; i < 200; i++) {
        final first = scheduler.first();
        expect(first, greaterThanOrEqualTo(const Duration(seconds: 20)));
        expect(first, lessThanOrEqualTo(const Duration(seconds: 90)));

        final next = scheduler.after(IdentityMonitorAction.none);
        expect(next, greaterThanOrEqualTo(const Duration(seconds: 60)));
        expect(next, lessThanOrEqualTo(const Duration(seconds: 360)));
        regular.add(next);

        final followUp = scheduler.after(IdentityMonitorAction.followUpSoon);
        expect(followUp, greaterThanOrEqualTo(const Duration(seconds: 8)));
        expect(followUp, lessThanOrEqualTo(const Duration(seconds: 20)));
      }
      // Unannounced means unpredictable: no fixed rhythm to learn.
      expect(regular.length, greaterThan(150));
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:students_ui_demo/exam_demo/continuous_identity_policy.dart';

void main() {
  test('only five independent mismatches require explicit verification', () {
    final policy = ContinuousIdentityPolicy(requiredMismatchOccasions: 5);
    for (var i = 0; i < 4; i++) {
      expect(
        policy.record(PassiveIdentityDecision.mismatch).requiresExplicitCheck,
        isFalse,
      );
      policy.record(PassiveIdentityDecision.inconclusive);
    }
    expect(policy.occasions, 4);
    expect(
      policy.record(PassiveIdentityDecision.mismatch).requiresExplicitCheck,
      isTrue,
    );
  });

  test('a verified occasion clears earlier mismatch concerns', () {
    final policy = ContinuousIdentityPolicy(requiredMismatchOccasions: 5);
    policy.record(PassiveIdentityDecision.mismatch);
    policy.record(PassiveIdentityDecision.mismatch);
    policy.record(PassiveIdentityDecision.verified);
    expect(policy.mismatchOccasions, 0);
  });
}

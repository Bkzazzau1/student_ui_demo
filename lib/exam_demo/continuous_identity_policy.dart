enum PassiveIdentityDecision { verified, inconclusive, mismatch }

class PassiveIdentitySnapshot {
  const PassiveIdentitySnapshot({
    required this.decision,
    required this.occasions,
    required this.mismatchOccasions,
    required this.requiresExplicitCheck,
  });

  final PassiveIdentityDecision decision;
  final int occasions;
  final int mismatchOccasions;
  final bool requiresExplicitCheck;
}

/// Quality-gated, fully local policy for continuous identity assurance.
class ContinuousIdentityPolicy {
  ContinuousIdentityPolicy({this.requiredMismatchOccasions = 5});

  final int requiredMismatchOccasions;
  int _occasions = 0;
  int _mismatchOccasions = 0;

  int get occasions => _occasions;
  int get mismatchOccasions => _mismatchOccasions;

  PassiveIdentitySnapshot record(PassiveIdentityDecision decision) {
    if (decision == PassiveIdentityDecision.inconclusive) {
      return _snapshot(decision);
    }
    _occasions++;
    if (decision == PassiveIdentityDecision.verified) {
      _mismatchOccasions = 0;
    } else {
      _mismatchOccasions++;
    }
    return _snapshot(decision);
  }

  void reset() {
    _occasions = 0;
    _mismatchOccasions = 0;
  }

  PassiveIdentitySnapshot _snapshot(PassiveIdentityDecision decision) =>
      PassiveIdentitySnapshot(
        decision: decision,
        occasions: _occasions,
        mismatchOccasions: _mismatchOccasions,
        requiresExplicitCheck: _mismatchOccasions >= requiredMismatchOccasions,
      );
}

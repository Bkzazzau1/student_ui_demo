import 'dart:math' as math;

enum PassiveIdentityDecision { verified, inconclusive, mismatch }

/// What the exam should do after a silent in-exam identity check.
enum IdentityMonitorAction {
  /// Keep going; the next check comes at an unannounced random time.
  none,

  /// One reliable "no": check again silently within seconds, so a single
  /// bad angle or lighting change does not pause the exam.
  followUpSoon,

  /// Pause the exam and ask for a full identity check with liveness.
  pauseForRecheck,
}

class PassiveIdentitySnapshot {
  const PassiveIdentitySnapshot({
    required this.decision,
    required this.occasions,
    required this.mismatchOccasions,
    required this.inconclusiveStreak,
    required this.action,
  });

  final PassiveIdentityDecision decision;
  final int occasions;

  /// Consecutive reliable "no" results.
  final int mismatchOccasions;

  /// Consecutive checks that could not decide (face not visible, too dark).
  final int inconclusiveStreak;
  final IdentityMonitorAction action;

  bool get requiresExplicitCheck =>
      action == IdentityMonitorAction.pauseForRecheck;
}

/// Fully local policy for the silent identity checks during an exam.
///
/// * A "no" is followed by a quick silent re-check.
/// * [requiredMismatchOccasions] consecutive "no" results pause the exam for
///   a full check (liveness + identity). With the default of 2 and an 8-20 s
///   follow-up, a different person is caught within about half a minute.
/// * [maxInconclusiveStreak] checks in a row that cannot see the student's
///   face also pause the exam: identity cannot go unconfirmed indefinitely.
/// * A pass resets both counters.
class ContinuousIdentityPolicy {
  ContinuousIdentityPolicy({
    this.requiredMismatchOccasions = 2,
    this.maxInconclusiveStreak = 6,
  });

  final int requiredMismatchOccasions;
  final int maxInconclusiveStreak;
  int _occasions = 0;
  int _mismatchOccasions = 0;
  int _inconclusiveStreak = 0;

  int get occasions => _occasions;
  int get mismatchOccasions => _mismatchOccasions;
  int get inconclusiveStreak => _inconclusiveStreak;

  PassiveIdentitySnapshot record(PassiveIdentityDecision decision) {
    switch (decision) {
      case PassiveIdentityDecision.inconclusive:
        _inconclusiveStreak++;
        return _snapshot(
          decision,
          _inconclusiveStreak >= maxInconclusiveStreak
              ? IdentityMonitorAction.pauseForRecheck
              : _mismatchOccasions > 0
              ? IdentityMonitorAction.followUpSoon
              : IdentityMonitorAction.none,
        );
      case PassiveIdentityDecision.verified:
        _occasions++;
        _mismatchOccasions = 0;
        _inconclusiveStreak = 0;
        return _snapshot(decision, IdentityMonitorAction.none);
      case PassiveIdentityDecision.mismatch:
        _occasions++;
        _mismatchOccasions++;
        _inconclusiveStreak = 0;
        return _snapshot(
          decision,
          _mismatchOccasions >= requiredMismatchOccasions
              ? IdentityMonitorAction.pauseForRecheck
              : IdentityMonitorAction.followUpSoon,
        );
    }
  }

  void reset() {
    _occasions = 0;
    _mismatchOccasions = 0;
    _inconclusiveStreak = 0;
  }

  PassiveIdentitySnapshot _snapshot(
    PassiveIdentityDecision decision,
    IdentityMonitorAction action,
  ) => PassiveIdentitySnapshot(
    decision: decision,
    occasions: _occasions,
    mismatchOccasions: _mismatchOccasions,
    inconclusiveStreak: _inconclusiveStreak,
    action: action,
  );
}

/// Picks unannounced times for the silent in-exam identity checks.
///
/// Times are drawn from a secure random source over wide ranges, so a
/// student cannot learn a rhythm and swap places between checks.
class IdentityCheckScheduler {
  IdentityCheckScheduler({
    math.Random? random,
    this.firstCheck = const IdentityCheckWindow(
      Duration(seconds: 20),
      Duration(seconds: 90),
    ),
    this.regularCheck = const IdentityCheckWindow(
      Duration(seconds: 60),
      Duration(seconds: 360),
    ),
    this.followUpCheck = const IdentityCheckWindow(
      Duration(seconds: 8),
      Duration(seconds: 20),
    ),
  }) : _random = random ?? math.Random.secure();

  final math.Random _random;
  final IdentityCheckWindow firstCheck;
  final IdentityCheckWindow regularCheck;
  final IdentityCheckWindow followUpCheck;

  Duration first() => firstCheck.pick(_random);

  Duration after(IdentityMonitorAction action) => switch (action) {
    IdentityMonitorAction.followUpSoon => followUpCheck.pick(_random),
    _ => regularCheck.pick(_random),
  };
}

class IdentityCheckWindow {
  const IdentityCheckWindow(this.earliest, this.latest);

  final Duration earliest;
  final Duration latest;

  Duration pick(math.Random random) {
    final span = latest.inMilliseconds - earliest.inMilliseconds;
    if (span <= 0) return earliest;
    return earliest + Duration(milliseconds: random.nextInt(span + 1));
  }
}

import '../rust/api/face_verification.dart';
import '../rust/api/liveness_challenge.dart';
import 'face_embedding_pipeline.dart';

/// The full set of states the 1:1 identity check can end in.
///
/// This is deliberately richer than the raw Rust [FaceVerificationResult]
/// states: it separates "the AI stack itself is unavailable", "the sample
/// was too poor to judge", and "liveness did not pass" from an actual
/// reliable non-match, because collapsing those into one "mismatch" state
/// would be unfair to the student and useless for model evaluation.
enum FaceIdentityCheckState {
  verified,
  uncertain,
  mismatch,
  aiUnavailable,
  qualityRetry,
  livenessFailed,
}

extension FaceIdentityCheckStateWire on FaceIdentityCheckState {
  /// The stable string identifier used in logs/telemetry/tests.
  String get wireName => switch (this) {
    FaceIdentityCheckState.verified => 'identity_verified',
    FaceIdentityCheckState.uncertain => 'identity_uncertain',
    FaceIdentityCheckState.mismatch => 'identity_mismatch_sample',
    FaceIdentityCheckState.aiUnavailable => 'identity_ai_unavailable',
    FaceIdentityCheckState.qualityRetry => 'identity_quality_retry',
    FaceIdentityCheckState.livenessFailed => 'identity_liveness_failed',
  };
}

class FaceIdentityCheckOutcome {
  const FaceIdentityCheckOutcome({
    required this.state,
    required this.reason,
    this.similarity = 0.0,
    this.threshold = 0.0,
  });

  factory FaceIdentityCheckOutcome.aiUnavailable(String reason) =>
      FaceIdentityCheckOutcome(
        state: FaceIdentityCheckState.aiUnavailable,
        reason: reason,
      );

  factory FaceIdentityCheckOutcome.qualityRetry(String reason) =>
      FaceIdentityCheckOutcome(
        state: FaceIdentityCheckState.qualityRetry,
        reason: reason,
      );

  factory FaceIdentityCheckOutcome.livenessFailed(String reason) =>
      FaceIdentityCheckOutcome(
        state: FaceIdentityCheckState.livenessFailed,
        reason: reason,
      );

  factory FaceIdentityCheckOutcome.fromRust(FaceVerificationResult result) {
    final state = switch (result.state) {
      'identity_verified' => FaceIdentityCheckState.verified,
      'identity_mismatch_sample' => FaceIdentityCheckState.mismatch,
      _ => FaceIdentityCheckState.uncertain,
    };
    return FaceIdentityCheckOutcome(
      state: state,
      reason: result.reason,
      similarity: result.similarity,
      threshold: result.threshold,
    );
  }

  final FaceIdentityCheckState state;
  final String reason;
  final double similarity;
  final double threshold;

  bool get verified => state == FaceIdentityCheckState.verified;
}

/// Orchestrates the "ask only 1:1" identity check against the logged-in
/// student's own locked template. This never searches across students: it
/// is handed exactly one template and answers "does this live sample match
/// it", nothing more.
class FaceIdentityVerificationService {
  const FaceIdentityVerificationService({this.matchThreshold = 0.55});

  /// The public SFace benchmark threshold (0.363) is intentionally not used
  /// as an exam-security operating point. This higher threshold prioritizes
  /// rejecting impostors; multi-sample consensus below limits the resulting
  /// inconvenience to the enrolled student.
  final double matchThreshold;

  FaceIdentityCheckOutcome evaluateConsensus({
    required List<FaceIdentityCheckOutcome> outcomes,
    int requiredMatches = 2,
  }) {
    final reliable = outcomes.where(
      (outcome) =>
          outcome.state == FaceIdentityCheckState.verified ||
          outcome.state == FaceIdentityCheckState.mismatch,
    );
    final matches = reliable.where((outcome) => outcome.verified).toList();
    if (matches.length >= requiredMatches) {
      matches.sort((a, b) => a.similarity.compareTo(b.similarity));
      return FaceIdentityCheckOutcome(
        state: FaceIdentityCheckState.verified,
        reason: '$requiredMatches independent live samples matched.',
        similarity: matches[matches.length ~/ 2].similarity,
        threshold: matchThreshold,
      );
    }
    if (reliable.length >= requiredMatches) {
      final best = reliable.fold<FaceIdentityCheckOutcome>(
        reliable.first,
        (current, next) =>
            next.similarity > current.similarity ? next : current,
      );
      return FaceIdentityCheckOutcome(
        state: FaceIdentityCheckState.mismatch,
        reason: 'Independent live samples did not agree with the template.',
        similarity: best.similarity,
        threshold: matchThreshold,
      );
    }
    return FaceIdentityCheckOutcome.qualityRetry(
      'More high-quality live samples are required.',
    );
  }

  FaceIdentityCheckOutcome evaluateSample({
    required bool aiAvailable,
    required FaceEmbeddingPipelineResult? sample,
    required String pipelineFailureReason,
    required String templateJson,
    LivenessChallengeResult? liveness,
    int? nowMs,
  }) {
    if (!aiAvailable) {
      return FaceIdentityCheckOutcome.aiUnavailable(
        'Face identity AI is unavailable on this device.',
      );
    }
    if (sample == null) {
      return FaceIdentityCheckOutcome.qualityRetry(
        pipelineFailureReason.isEmpty
            ? 'The verification sample was not reliable.'
            : pipelineFailureReason,
      );
    }
    if (liveness != null && liveness.state != 'live_challenge_passed') {
      return FaceIdentityCheckOutcome.livenessFailed(
        liveness.reason.isEmpty
            ? 'Liveness could not be confirmed for this sample.'
            : liveness.reason,
      );
    }
    final result = verifyFaceEmbedding1To1(
      templateJson: templateJson,
      probeEmbedding: sample.embedding,
      signalQuality: sample.quality,
      matchThreshold: matchThreshold,
      nowMs: nowMs ?? DateTime.now().toUtc().millisecondsSinceEpoch,
    );
    return FaceIdentityCheckOutcome.fromRust(result);
  }
}

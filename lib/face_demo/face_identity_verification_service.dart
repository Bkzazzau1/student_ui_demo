import '../rust/api/liveness_challenge.dart';
import '../rust/api/official_face_id.dart';
import 'face_embedding_pipeline.dart';
import 'native_face_embedding_runtime.dart';

/// The full set of states the 1:1 identity check can end in.
///
/// This is deliberately richer than the raw Rust match states: it separates
/// "the AI stack itself is unavailable", "the sample was too poor to judge",
/// and "liveness did not pass" from an actual reliable non-match, because
/// collapsing those into one "mismatch" state would be unfair to the student
/// and useless for model evaluation.
enum FaceIdentityCheckState {
  verified,
  uncertain,
  mismatch,
  aiUnavailable,
  qualityRetry,
  livenessFailed,
}

extension FaceIdentityCheckStateWire on FaceIdentityCheckState {
  /// The stable string identifier used in logs/evidence/tests.
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
    this.centroidSimilarity = 0.0,
    this.threshold = 0.0,
    this.matchedSamples = 0,
    this.reliableSamples = 0,
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

  factory FaceIdentityCheckOutcome.fromRust(OfficialFaceMatchResult result) {
    final state = switch (result.state) {
      'identity_verified' => FaceIdentityCheckState.verified,
      'identity_mismatch_sample' => FaceIdentityCheckState.mismatch,
      _ => FaceIdentityCheckState.uncertain,
    };
    return FaceIdentityCheckOutcome(
      state: state,
      reason: result.reason,
      similarity: result.similarity,
      centroidSimilarity: result.centroidSimilarity,
      threshold: result.threshold,
      matchedSamples: state == FaceIdentityCheckState.verified ? 1 : 0,
      reliableSamples: result.reliable ? 1 : 0,
    );
  }

  final FaceIdentityCheckState state;
  final String reason;
  final double similarity;
  final double centroidSimilarity;
  final double threshold;
  final int matchedSamples;
  final int reliableSamples;

  bool get verified => state == FaceIdentityCheckState.verified;

  /// A reliable "no": the only outcomes that count against the student.
  bool get countsAsFailure =>
      state == FaceIdentityCheckState.mismatch ||
      state == FaceIdentityCheckState.livenessFailed;
}

/// The signed official template for the logged-in student, plus the keys
/// that may have signed it. Every match re-verifies the signature.
class OfficialFaceTemplateContext {
  const OfficialFaceTemplateContext({
    required this.studentId,
    required this.envelopeJson,
    required this.trustedKeysJson,
    required this.status,
  });

  final String studentId;
  final String envelopeJson;
  final String trustedKeysJson;
  final OfficialFaceTemplateStatus status;

  String get templateId => status.templateId;
  String get envelopeSha256 => status.envelopeSha256;

  /// Verifies [envelopeJson] for [studentId] against the installed model and
  /// preprocessing. Returns the status; callers must check `status.valid`.
  static OfficialFaceTemplateStatus verify({
    required String studentId,
    required String envelopeJson,
    required String trustedKeysJson,
    int? nowMs,
  }) => verifyOfficialFaceTemplate(
    envelopeJson: envelopeJson,
    trustedKeysJson: trustedKeysJson,
    expectedStudentId: studentId,
    expectedModelId: NativeFaceEmbeddingRuntime.modelId,
    expectedModelSha256: NativeFaceEmbeddingRuntime.modelSha256,
    expectedPreprocessingVersion:
        NativeFaceEmbeddingRuntime.preprocessingVersion,
    nowMs: nowMs ?? DateTime.now().toUtc().millisecondsSinceEpoch,
  );
}

/// Orchestrates the "ask only 1:1" identity check against the logged-in
/// student's own official template. This never searches across students: it
/// is handed exactly one template and answers "does this live sample match
/// it", nothing more.
class FaceIdentityVerificationService {
  const FaceIdentityVerificationService({
    this.matchThreshold = 0.40,
    this.minSignalQuality = 0.65,
  });

  /// PROVISIONAL until the volunteer study
  /// (docs/identity/volunteer_calibration_protocol.md) sets it from real
  /// students on the real devices. On 6,000 LFW pairs, including simulated
  /// laptop-webcam framing, the single-photo threshold for one false accept
  /// in 1,000 was at most 0.365; 0.40 accepted none of 9,000 different-person
  /// pairs and rejected 2-2.5% of same-person pairs, before the two-best-
  /// references score and the two-of-three consensus reduce that further.
  /// See docs/identity/face_pipeline_benchmark.md.
  final double matchThreshold;
  final double minSignalQuality;

  FaceIdentityCheckOutcome evaluateConsensus({
    required List<FaceIdentityCheckOutcome> outcomes,
    int requiredMatches = 2,
  }) {
    final reliable = outcomes
        .where(
          (outcome) =>
              outcome.state == FaceIdentityCheckState.verified ||
              outcome.state == FaceIdentityCheckState.mismatch,
        )
        .toList();
    final matches = reliable.where((outcome) => outcome.verified).toList();
    final mismatches = reliable.length - matches.length;
    if (matches.length >= requiredMatches && matches.length > mismatches) {
      matches.sort((a, b) => a.similarity.compareTo(b.similarity));
      final median = matches[matches.length ~/ 2];
      return FaceIdentityCheckOutcome(
        state: FaceIdentityCheckState.verified,
        reason: '${matches.length} live samples matched the official Face ID.',
        similarity: median.similarity,
        centroidSimilarity: median.centroidSimilarity,
        threshold: matchThreshold,
        matchedSamples: matches.length,
        reliableSamples: reliable.length,
      );
    }
    // A tie is not a decision either way: ask for more samples.
    if (mismatches >= requiredMatches && mismatches > matches.length) {
      final best = reliable.fold<FaceIdentityCheckOutcome>(
        reliable.first,
        (current, next) =>
            next.similarity > current.similarity ? next : current,
      );
      return FaceIdentityCheckOutcome(
        state: FaceIdentityCheckState.mismatch,
        reason: 'Live samples did not match the official Face ID.',
        similarity: best.similarity,
        centroidSimilarity: best.centroidSimilarity,
        threshold: matchThreshold,
        matchedSamples: matches.length,
        reliableSamples: reliable.length,
      );
    }
    final uncertainReasons = outcomes
        .where((outcome) => outcome.state == FaceIdentityCheckState.uncertain)
        .map((outcome) => outcome.reason)
        .toSet();
    return FaceIdentityCheckOutcome(
      state: FaceIdentityCheckState.qualityRetry,
      reason: uncertainReasons.isNotEmpty
          ? uncertainReasons.first
          : 'More clear live samples are needed.',
      matchedSamples: matches.length,
      reliableSamples: reliable.length,
    );
  }

  FaceIdentityCheckOutcome evaluateSample({
    required bool aiAvailable,
    required FaceEmbeddingPipelineResult? sample,
    required String pipelineFailureReason,
    required OfficialFaceTemplateContext template,
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
    final result = matchOfficialFaceTemplate1To1(
      envelopeJson: template.envelopeJson,
      trustedKeysJson: template.trustedKeysJson,
      expectedStudentId: template.studentId,
      expectedModelId: NativeFaceEmbeddingRuntime.modelId,
      expectedModelSha256: NativeFaceEmbeddingRuntime.modelSha256,
      expectedPreprocessingVersion:
          NativeFaceEmbeddingRuntime.preprocessingVersion,
      probeEmbedding: sample.embedding,
      signalQuality: sample.quality,
      minSignalQuality: minSignalQuality,
      matchThreshold: matchThreshold,
      nowMs: nowMs ?? DateTime.now().toUtc().millisecondsSinceEpoch,
    );
    return FaceIdentityCheckOutcome.fromRust(result);
  }
}

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:students_ui_demo/face_demo/face_embedding_pipeline.dart';
import 'package:students_ui_demo/face_demo/face_identity_landmark_matrix.dart';
import 'package:students_ui_demo/face_demo/face_identity_person_gate.dart';
import 'package:students_ui_demo/face_demo/face_identity_quality.dart';
import 'package:students_ui_demo/face_demo/face_identity_verification_service.dart';
import 'package:students_ui_demo/rust/api/face_verification.dart';
import 'package:students_ui_demo/rust/api/liveness_challenge.dart';
import 'package:students_ui_demo/rust/brain_core_runtime.dart';

const _acceptedPersonGate = FaceIdentityPersonGateResult(
  state: FaceIdentityPersonGateState.accepted,
  personCount: 1,
  personConfidence: 0.95,
  reason: 'ok',
);

FaceEmbeddingPipelineResult _sample(
  List<double> embedding, {
  double quality = 0.9,
}) {
  return FaceEmbeddingPipelineResult(
    embedding: embedding,
    quality: quality,
    faceConfidence: 0.9,
    alignedRgb: Uint8List(112 * 112 * 3),
    yaw: 0,
    pitch: 0,
    eyeOpenness: 0.05,
    smileWidth: 0.5,
    mouthOpenness: 0.02,
    landmarks: FaceLandmarkMatrix.empty(),
    personGate: _acceptedPersonGate,
    qualityGrade: const FaceIdentityQualityGrade(
      overallScore: 0.9,
      level: FaceIdentityQualityLevel.good,
      personPresent: true,
      singlePerson: true,
      facePresent: true,
      landmarksComplete: true,
      eyesVisible: true,
      noseVisible: true,
      mouthVisible: true,
      faceCentered: true,
      faceCoverage: 0.5,
      poseAcceptable: true,
      alignmentAcceptable: true,
      faceConfidence: 0.9,
      personConfidence: 0.95,
      yaw: 0,
      pitch: 0,
      roll: 0,
      failureReasons: <String>[],
    ),
  );
}

List<double> _vector(int dimension, int index) {
  final values = List<double>.filled(dimension, 0.0);
  values[index] = 1.0;
  return values;
}

String _template({
  required String studentId,
  required List<List<double>> embeddings,
  int expiresInDays = 365,
}) {
  return buildPortableFaceTemplate(
    studentId: studentId,
    enrollmentId: 'enrollment-1',
    modelId: 'kslas-sface-2021dec-v1',
    modelSha256: 'a' * 64,
    preprocessingVersion:
        'sface-five-point-similarity-bgr-minus-127.5-div-128-v1',
    embeddings: embeddings
        .map((e) => Float32List.fromList(e))
        .toList(growable: false),
    qualityScore: 0.9,
    createdAtMs: 0,
    expiresAtMs: expiresInDays * 24 * 60 * 60 * 1000,
  );
}

void main() {
  setUpAll(() async {
    await BrainCoreRuntime.ensureInitialized();
  });

  const service = FaceIdentityVerificationService();

  test(
    'a matching live embedding is verified against the student\'s own template',
    () {
      final template = _template(
        studentId: 'student-1',
        embeddings: [_vector(128, 0), _vector(128, 0), _vector(128, 0)],
      );

      final outcome = service.evaluateSample(
        aiAvailable: true,
        sample: _sample(_vector(128, 0)),
        pipelineFailureReason: '',
        templateJson: template,
        nowMs: 1000,
      );

      expect(outcome.state, FaceIdentityCheckState.verified);
      expect(outcome.verified, isTrue);
      expect(outcome.similarity, closeTo(1.0, 1e-6));
    },
  );

  test(
    'a reliable non-matching sample is a mismatch, not an accusation label',
    () {
      final template = _template(
        studentId: 'student-1',
        embeddings: [_vector(128, 0), _vector(128, 0), _vector(128, 0)],
      );

      final outcome = service.evaluateSample(
        aiAvailable: true,
        sample: _sample(_vector(128, 1)),
        pipelineFailureReason: '',
        templateJson: template,
        nowMs: 1000,
      );

      expect(outcome.state, FaceIdentityCheckState.mismatch);
      expect(outcome.verified, isFalse);
    },
  );

  test('consensus requires two independent matching live samples', () {
    const strict = FaceIdentityVerificationService();
    const match = FaceIdentityCheckOutcome(
      state: FaceIdentityCheckState.verified,
      reason: 'match',
      similarity: 0.72,
      threshold: 0.55,
    );
    const mismatch = FaceIdentityCheckOutcome(
      state: FaceIdentityCheckState.mismatch,
      reason: 'mismatch',
      similarity: 0.31,
      threshold: 0.55,
    );

    expect(
      strict.evaluateConsensus(outcomes: [match, mismatch, mismatch]).state,
      FaceIdentityCheckState.mismatch,
    );
    expect(
      strict.evaluateConsensus(outcomes: [match, mismatch, match]).state,
      FaceIdentityCheckState.verified,
    );
  });

  test(
    'a low-quality/failed capture retries instead of becoming a mismatch',
    () {
      final template = _template(
        studentId: 'student-1',
        embeddings: [_vector(128, 0), _vector(128, 0), _vector(128, 0)],
      );

      final outcome = service.evaluateSample(
        aiAvailable: true,
        sample: null,
        pipelineFailureReason: 'Move closer to the camera.',
        templateJson: template,
        nowMs: 1000,
      );

      expect(outcome.state, FaceIdentityCheckState.qualityRetry);
      expect(outcome.reason, 'Move closer to the camera.');
    },
  );

  test('an unavailable SFace runtime reports AI-unavailable, never a pass', () {
    final template = _template(
      studentId: 'student-1',
      embeddings: [_vector(128, 0), _vector(128, 0), _vector(128, 0)],
    );

    final outcome = service.evaluateSample(
      aiAvailable: false,
      sample: null,
      pipelineFailureReason: '',
      templateJson: template,
      nowMs: 1000,
    );

    expect(outcome.state, FaceIdentityCheckState.aiUnavailable);
    expect(outcome.verified, isFalse);
  });

  test(
    'a failed liveness challenge blocks verification even with a matching embedding',
    () {
      final template = _template(
        studentId: 'student-1',
        embeddings: [_vector(128, 0), _vector(128, 0), _vector(128, 0)],
      );

      final outcome = service.evaluateSample(
        aiAvailable: true,
        sample: _sample(_vector(128, 0)),
        pipelineFailureReason: '',
        templateJson: template,
        liveness: const LivenessChallengeResult(
          state: 'possible_presentation_attack',
          challenge: 'blink',
          completed: false,
          reliable: false,
          progress: 0,
          spoofRiskScore: 0.9,
          usableObservations: 8,
          reason: 'repeated flat frames need human review',
        ),
        nowMs: 1000,
      );

      expect(outcome.state, FaceIdentityCheckState.livenessFailed);
      expect(outcome.verified, isFalse);
    },
  );

  test('an invalid probe embedding dimension is uncertain, not a mismatch', () {
    final template = _template(
      studentId: 'student-1',
      embeddings: [_vector(128, 0), _vector(128, 0), _vector(128, 0)],
    );

    final outcome = service.evaluateSample(
      aiAvailable: true,
      sample: _sample(_vector(64, 0)),
      pipelineFailureReason: '',
      templateJson: template,
      nowMs: 1000,
    );

    expect(outcome.state, FaceIdentityCheckState.uncertain);
  });

  test('a corrupted template is uncertain, not a false verification', () {
    final outcome = service.evaluateSample(
      aiAvailable: true,
      sample: _sample(_vector(128, 0)),
      pipelineFailureReason: '',
      templateJson: '{not valid json',
      nowMs: 1000,
    );

    expect(outcome.state, FaceIdentityCheckState.uncertain);
    expect(outcome.verified, isFalse);
  });

  test(
    'this is strictly 1:1: a template built for another student never matches',
    () {
      final template = _template(
        studentId: 'student-2',
        embeddings: [_vector(128, 0), _vector(128, 0), _vector(128, 0)],
      );

      // validate_portable_face_template is what the app calls before ever
      // trusting a loaded template for "this" logged-in student.
      final status = validatePortableFaceTemplate(
        templateJson: template,
        expectedStudentId: 'student-1',
        expectedModelId: 'kslas-sface-2021dec-v1',
        expectedModelSha256: 'a' * 64,
        nowMs: 1000,
      );

      expect(status.valid, isFalse);
      expect(status.reason, contains('different student'));
    },
  );
}

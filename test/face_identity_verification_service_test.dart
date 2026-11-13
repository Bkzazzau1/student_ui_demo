import 'package:flutter_test/flutter_test.dart';
import 'package:students_ui_demo/face_demo/face_identity_verification_service.dart';
import 'package:students_ui_demo/rust/api/liveness_challenge.dart';
import 'package:students_ui_demo/rust/brain_core_runtime.dart';

import 'support/official_face_id_fixtures.dart';

void main() {
  setUpAll(() async {
    await BrainCoreRuntime.ensureInitialized();
  });

  const service = FaceIdentityVerificationService();

  OfficialFaceTemplateContext studentOneTemplate() => templateContext(
    studentId: 'student-1',
    envelope: issueTemplate(
      studentId: 'student-1',
      references: [unitVector(0), unitVector(0), unitVector(0)],
    ),
  );

  test('a live sample of the student matches their official template', () {
    final outcome = service.evaluateSample(
      aiAvailable: true,
      sample: pipelineSample(unitVector(0)),
      pipelineFailureReason: '',
      template: studentOneTemplate(),
      nowMs: 5000,
    );

    expect(outcome.state, FaceIdentityCheckState.verified);
    expect(outcome.similarity, closeTo(1.0, 1e-5));
    expect(outcome.centroidSimilarity, closeTo(1.0, 1e-5));
  });

  test('a reliable different face is a mismatch, not an accusation', () {
    final outcome = service.evaluateSample(
      aiAvailable: true,
      sample: pipelineSample(unitVector(1)),
      pipelineFailureReason: '',
      template: studentOneTemplate(),
      nowMs: 5000,
    );

    expect(outcome.state, FaceIdentityCheckState.mismatch);
    expect(outcome.countsAsFailure, isTrue);
  });

  test('strictly 1:1: a template issued to another student never verifies', () {
    final otherStudents = issueTemplate(
      studentId: 'student-2',
      references: [unitVector(0), unitVector(0), unitVector(0)],
    );
    final context = templateContext(
      studentId: 'student-1',
      envelope: otherStudents,
    );
    expect(context.status.valid, isFalse);
    expect(context.status.reason, contains('different student'));

    final outcome = service.evaluateSample(
      aiAvailable: true,
      sample: pipelineSample(unitVector(0)),
      pipelineFailureReason: '',
      template: context,
      nowMs: 5000,
    );
    expect(outcome.state, FaceIdentityCheckState.uncertain);
    expect(outcome.verified, isFalse);
  });

  test('a template signed by an untrusted key is never matched', () {
    final envelope = issueTemplate(
      studentId: 'student-1',
      references: [unitVector(0), unitVector(0), unitVector(0)],
    );
    final context = templateContext(
      studentId: 'student-1',
      envelope: envelope,
      trustedKeys: trustedKeysFor(seed: '02' * 32),
    );
    expect(context.status.valid, isFalse);

    final outcome = service.evaluateSample(
      aiAvailable: true,
      sample: pipelineSample(unitVector(0)),
      pipelineFailureReason: '',
      template: context,
      nowMs: 5000,
    );
    expect(outcome.state, FaceIdentityCheckState.uncertain);
  });

  test('a template built with different face alignment is rejected', () {
    final envelope = issueTemplate(
      studentId: 'student-1',
      references: [unitVector(0), unitVector(0), unitVector(0)],
      preprocessingVersion: 'some-other-alignment',
    );
    final context = templateContext(studentId: 'student-1', envelope: envelope);
    expect(context.status.valid, isFalse);
    expect(context.status.reason, contains('alignment'));
  });

  test('a failed liveness challenge blocks verification', () {
    final outcome = service.evaluateSample(
      aiAvailable: true,
      sample: pipelineSample(unitVector(0)),
      pipelineFailureReason: '',
      template: studentOneTemplate(),
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
      nowMs: 5000,
    );

    expect(outcome.state, FaceIdentityCheckState.livenessFailed);
    expect(outcome.countsAsFailure, isTrue);
  });

  test(
    'low quality, missing samples, and missing AI never count against the student',
    () {
      final template = studentOneTemplate();
      final lowQuality = service.evaluateSample(
        aiAvailable: true,
        sample: pipelineSample(unitVector(1), quality: 0.4),
        pipelineFailureReason: '',
        template: template,
        nowMs: 5000,
      );
      expect(lowQuality.state, FaceIdentityCheckState.uncertain);
      expect(lowQuality.countsAsFailure, isFalse);

      final missing = service.evaluateSample(
        aiAvailable: true,
        sample: null,
        pipelineFailureReason: 'Move closer to the camera.',
        template: template,
      );
      expect(missing.state, FaceIdentityCheckState.qualityRetry);
      expect(missing.reason, 'Move closer to the camera.');

      final noAi = service.evaluateSample(
        aiAvailable: false,
        sample: null,
        pipelineFailureReason: '',
        template: template,
      );
      expect(noAi.state, FaceIdentityCheckState.aiUnavailable);
      expect(noAi.countsAsFailure, isFalse);
    },
  );

  group('consensus', () {
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
    const unclear = FaceIdentityCheckOutcome(
      state: FaceIdentityCheckState.uncertain,
      reason: 'face sample quality is too low',
    );

    test('needs a majority of at least two agreeing samples', () {
      expect(
        service.evaluateConsensus(outcomes: [match, mismatch, mismatch]).state,
        FaceIdentityCheckState.mismatch,
      );
      expect(
        service.evaluateConsensus(outcomes: [match, mismatch, match]).state,
        FaceIdentityCheckState.verified,
      );
    });

    test('a tie or too few reliable samples asks for another try', () {
      expect(
        service
            .evaluateConsensus(outcomes: [match, match, mismatch, mismatch])
            .state,
        FaceIdentityCheckState.qualityRetry,
      );
      final retry = service.evaluateConsensus(
        outcomes: [match, unclear, unclear],
      );
      expect(retry.state, FaceIdentityCheckState.qualityRetry);
      expect(retry.reason, 'face sample quality is too low');
    });

    test('reports how many samples matched', () {
      final result = service.evaluateConsensus(
        outcomes: [match, match, unclear],
      );
      expect(result.matchedSamples, 2);
      expect(result.reliableSamples, 2);
    });
  });
}

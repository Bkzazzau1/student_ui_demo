import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:students_ui_demo/exam_demo/continuous_identity_policy.dart';
import 'package:students_ui_demo/face_demo/face_identity_verification_service.dart';
import 'package:students_ui_demo/face_demo/identity_evidence.dart';
import 'package:students_ui_demo/face_demo/in_exam_identity_checker.dart';
import 'package:students_ui_demo/face_demo/official_identity_session.dart';
import 'package:students_ui_demo/face_demo/protected_local_store.dart';

import 'identity_evidence_outbox_test.dart' show RecordingSchool;
import 'support/official_face_id_fixtures.dart';

class ScriptedEvaluator implements InExamFrameEvaluator {
  final List<FaceIdentityCheckState> script = <FaceIdentityCheckState>[];
  int calls = 0;

  @override
  Future<FaceIdentityCheckOutcome> evaluate(
    Uint8List encodedFrame,
    OfficialFaceTemplateContext template,
  ) async {
    calls++;
    final state = script.isEmpty
        ? FaceIdentityCheckState.verified
        : script.removeAt(0);
    return FaceIdentityCheckOutcome(
      state: state,
      reason: state.wireName,
      similarity: state == FaceIdentityCheckState.verified ? 0.8 : 0.2,
      threshold: 0.55,
    );
  }
}

void main() {
  late DateTime now;
  late ScriptedEvaluator evaluator;
  late IdentityEvidenceOutbox outbox;
  late int pauses;
  late InExamIdentityChecker checker;
  var frameCounter = 0;

  Uint8List frame() => Uint8List.fromList(<int>[frameCounter++, 7, 7]);

  setUp(() {
    now = DateTime.utc(2026, 11, 13, 10);
    evaluator = ScriptedEvaluator();
    pauses = 0;
    outbox = IdentityEvidenceOutbox(
      store: InMemoryProtectedLocalStore(),
      institutionId: 'test-school',
      clock: () => now,
    );
    SchoolIdentityServices.instance.override(
      school: RecordingSchool(),
      outbox: outbox,
    );
    checker = InExamIdentityChecker(
      studentId: 'STD/1',
      examId: 'exam-1',
      attemptId: 'attempt-1',
      onPauseForRecheck: () => pauses++,
      evaluator: evaluator,
      scheduler: IdentityCheckScheduler(
        firstCheck: const IdentityCheckWindow(
          Duration(seconds: 30),
          Duration(seconds: 30),
        ),
        regularCheck: const IdentityCheckWindow(
          Duration(seconds: 120),
          Duration(seconds: 120),
        ),
        followUpCheck: const IdentityCheckWindow(
          Duration(seconds: 10),
          Duration(seconds: 10),
        ),
      ),
      templateLoader: () async => fakeTemplateContext('STD/1'),
      outbox: () async => outbox,
      clock: () => now,
      collectTimeout: const Duration(minutes: 5),
    );
  });

  tearDown(() => checker.dispose());

  /// Feeds frames one second apart until the occasion is evaluated.
  Future<void> runOccasion({bool sameFrame = false}) async {
    final repeated = frame();
    for (var index = 0; index < 3; index++) {
      expect(checker.wantsFrame, isTrue);
      checker.offerFrame(() => sameFrame ? repeated : frame());
      now = now.add(const Duration(seconds: 1));
    }
    await pumpEventQueue();
  }

  test('checks only at the scheduled random time', () async {
    expect(checker.wantsFrame, isFalse);
    now = now.add(const Duration(seconds: 29));
    expect(checker.wantsFrame, isFalse);
    now = now.add(const Duration(seconds: 1));
    expect(checker.wantsFrame, isTrue);
  });

  test('a pass is recorded and the next check is a regular one', () async {
    now = now.add(const Duration(seconds: 30));
    await runOccasion();

    expect(evaluator.calls, 3);
    expect(pauses, 0);
    final records = await outbox.pending();
    expect(records, isEmpty, reason: 'evidence is uploaded straight away');
    expect(
      checker.nextCheckAt.difference(now).inSeconds,
      inInclusiveRange(118, 120),
    );
  });

  test(
    'a "no" triggers a silent follow-up; a second "no" pauses the exam',
    () async {
      evaluator.script.addAll(List.filled(6, FaceIdentityCheckState.mismatch));
      now = now.add(const Duration(seconds: 30));
      await runOccasion();
      expect(pauses, 0);
      expect(
        checker.nextCheckAt.difference(now).inSeconds,
        inInclusiveRange(8, 10),
      );

      now = checker.nextCheckAt;
      await runOccasion();
      expect(pauses, 1);
      expect(checker.stopped, isTrue);
      expect(checker.wantsFrame, isFalse);
    },
  );

  test('a frozen camera picture counts as a failed check', () async {
    now = now.add(const Duration(seconds: 30));
    await runOccasion(sameFrame: true);
    expect(evaluator.calls, 0);
    expect(checker.policy.mismatchOccasions, 1);
  });

  test('a follow-up pass clears the concern', () async {
    evaluator.script.addAll(List.filled(3, FaceIdentityCheckState.mismatch));
    now = now.add(const Duration(seconds: 30));
    await runOccasion();
    now = checker.nextCheckAt;
    await runOccasion();
    expect(pauses, 0);
    expect(checker.policy.mismatchOccasions, 0);
  });

  test('evidence names the kind of check', () async {
    final school = RecordingSchool();
    SchoolIdentityServices.instance.override(school: school, outbox: outbox);
    evaluator.script.addAll(List.filled(3, FaceIdentityCheckState.mismatch));
    now = now.add(const Duration(seconds: 30));
    await runOccasion();
    now = checker.nextCheckAt;
    await runOccasion();
    await pumpEventQueue();

    final kinds = school.received
        .map((record) => record['check_kind'])
        .toList();
    expect(kinds, ['in_exam_random', 'in_exam_follow_up']);
    expect(school.received.first['review_photo_jpeg_b64'], isNotNull);
    expect(school.received.last['review_photo_jpeg_b64'], isNull);
  });
}

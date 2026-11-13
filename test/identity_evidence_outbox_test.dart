import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:students_ui_demo/face_demo/face_identity_verification_service.dart';
import 'package:students_ui_demo/face_demo/identity_evidence.dart';
import 'package:students_ui_demo/face_demo/official_face_id_models.dart';
import 'package:students_ui_demo/face_demo/protected_local_store.dart';
import 'package:students_ui_demo/face_demo/school_identity_service.dart';

import 'support/official_face_id_fixtures.dart';

class RecordingSchool implements SchoolIdentityService {
  final List<Map<String, Object?>> received = <Map<String, Object?>>[];
  bool offline = false;

  @override
  String get institutionId => 'test-school';

  @override
  bool get isSample => true;

  @override
  Future<List<String>> uploadIdentityEvidence(
    List<Map<String, Object?>> records,
  ) async {
    if (offline) throw const SchoolIdentityUnavailable('offline');
    received.addAll(records);
    return records.map((record) => record['record_id']!.toString()).toList();
  }

  @override
  Future<String?> downloadOfficialTemplate(String studentId) async => null;

  @override
  Future<OfficialFaceIdStatus> fetchStatus(String studentId) async =>
      OfficialFaceIdStatus(studentId: studentId);

  @override
  Future<String> submitRegistration(
    OfficialFaceIdSubmission submission,
  ) async => submission.submissionId;

  @override
  Future<String> trustedTemplateKeysJson() async => '[]';
}

void main() {
  late DateTime now;
  late IdentityEvidenceOutbox outbox;
  final photo = Uint8List.fromList(<int>[0xFF, 0xD8, 1, 2, 3]);

  setUp(() {
    now = DateTime.utc(2026, 11, 13, 9);
    outbox = IdentityEvidenceOutbox(
      store: InMemoryProtectedLocalStore(),
      institutionId: 'test-school',
      deviceClass: 'desktop',
      clock: () => now,
    );
  });

  IdentityEvidenceDraft draft(FaceIdentityCheckState state) =>
      IdentityEvidenceDraft(
        kind: IdentityCheckKind.inExamRandom,
        studentId: 'STD/1',
        examId: 'exam-1',
        attemptId: 'attempt-1',
        outcome: FaceIdentityCheckOutcome(
          state: state,
          reason: state.wireName,
          similarity: 0.42,
          threshold: 0.55,
        ),
        samplesAttempted: 3,
        template: fakeTemplateContext('STD/1'),
        reviewPhotoJpeg: photo,
      );

  test('records are sealed and chained per student and attempt', () async {
    final first = await outbox.record(draft(FaceIdentityCheckState.verified));
    now = now.add(const Duration(minutes: 3));
    final second = await outbox.record(draft(FaceIdentityCheckState.mismatch));

    expect(IdentityEvidenceOutbox.verifySeal(first), isTrue);
    expect(IdentityEvidenceOutbox.verifySeal(second), isTrue);
    expect(first['previous_record_sha256'], '');
    expect(second['previous_record_sha256'], first['record_sha256']);
    expect(second['check_kind'], 'in_exam_random');
    expect(second['decision'], 'identity_mismatch_sample');
    expect((second['template']! as Map)['template_id'], 'tpl-fake');
  });

  test('a photo is kept only for a failed check', () async {
    final pass = await outbox.record(draft(FaceIdentityCheckState.verified));
    final unclear = await outbox.record(
      draft(FaceIdentityCheckState.uncertain),
    );
    final fail = await outbox.record(draft(FaceIdentityCheckState.mismatch));

    expect(pass['review_photo_jpeg_b64'], isNull);
    expect(pass['review_photo_sha256'], isNull);
    expect(unclear['review_photo_jpeg_b64'], isNull);
    expect(fail['review_photo_jpeg_b64'], isNotNull);
    expect(fail['review_photo_sha256'], isNotNull);
  });

  test('any edit breaks the seal', () async {
    final record = await outbox.record(draft(FaceIdentityCheckState.mismatch));
    final edited = Map<String, Object?>.from(record)
      ..['decision'] = 'identity_verified';
    expect(IdentityEvidenceOutbox.verifySeal(edited), isFalse);
  });

  test(
    'review photos are removed after 30 days without breaking the seal',
    () async {
      await outbox.record(draft(FaceIdentityCheckState.mismatch));
      now = now.add(const Duration(days: 29));
      expect(await outbox.purgeExpiredReviewPhotos(), 0);

      now = now.add(const Duration(days: 2));
      expect(await outbox.purgeExpiredReviewPhotos(), 1);
      final kept = (await outbox.pending()).single;
      expect(kept['review_photo_jpeg_b64'], isNull);
      expect(kept['review_photo_sha256'], isNotNull);
      expect(IdentityEvidenceOutbox.verifySeal(kept), isTrue);
    },
  );

  test('uploaded records leave the queue; offline records stay', () async {
    final school = RecordingSchool()..offline = true;
    await outbox.record(draft(FaceIdentityCheckState.verified));
    expect(await outbox.flush(school), 0);
    expect(await outbox.pending(), hasLength(1));

    school.offline = false;
    expect(await outbox.flush(school), 1);
    expect(await outbox.pending(), isEmpty);
    expect(school.received.single['student_id'], 'STD/1');
  });

  test('canonical JSON sorts keys at every level', () {
    expect(
      IdentityEvidenceOutbox.canonicalJson(<String, Object?>{
        'b': 1,
        'a': <String, Object?>{'d': true, 'c': null},
        'e': <Object?>[2, 'x'],
      }),
      '{"a":{"c":null,"d":true},"b":1,"e":[2,"x"]}',
    );
  });
}

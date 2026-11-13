import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:students_ui_demo/face_demo/face_identity_verification_service.dart';
import 'package:students_ui_demo/face_demo/local_sample_school_identity_service.dart';
import 'package:students_ui_demo/face_demo/native_face_embedding_runtime.dart';
import 'package:students_ui_demo/face_demo/official_face_id_models.dart';
import 'package:students_ui_demo/face_demo/protected_local_store.dart';
import 'package:students_ui_demo/rust/brain_core_runtime.dart';

import 'support/official_face_id_fixtures.dart';

/// Rebuilds each reference as [rebuiltFor] says (defaults to the device
/// embedding), standing in for the school's own face pipeline.
class FakeRebuilder implements OfficialTemplateRebuilder {
  FakeRebuilder({this.rebuiltFor, this.unusablePoses = const <String>{}});

  final List<double> Function(OfficialFaceIdPhoto photo)? rebuiltFor;
  final Set<String> unusablePoses;

  @override
  Future<RebuiltReference> rebuild(OfficialFaceIdPhoto photo) async {
    if (unusablePoses.contains(photo.poseCode)) {
      return const RebuiltReference.unusable('no face');
    }
    final embedding = rebuiltFor?.call(photo) ?? photo.deviceEmbedding;
    return RebuiltReference.usable(embedding, 0.9);
  }
}

const _poses = <String>[
  'front_face',
  'left_angle',
  'right_angle',
  'look_down',
  'look_up',
  'smile',
  'open_mouth',
];

OfficialFaceIdSubmission submission(
  String studentId, {
  String id = 'sub-1',
  int faceIndex = 0,
  DateTime? at,
}) {
  final now = at ?? DateTime.utc(2026, 11, 1);
  return OfficialFaceIdSubmission(
    submissionId: id,
    studentId: studentId,
    submittedAt: now,
    consentVersion: 'test-consent',
    consentAcceptedAt: now,
    modelId: NativeFaceEmbeddingRuntime.modelId,
    modelSha256: NativeFaceEmbeddingRuntime.modelSha256,
    preprocessingVersion: NativeFaceEmbeddingRuntime.preprocessingVersion,
    capturePlatform: 'windows',
    captureDeviceClass: 'desktop',
    poseOrder: _poses,
    photos: [
      for (final pose in _poses)
        OfficialFaceIdPhoto(
          poseCode: pose,
          title: pose,
          jpegBytes: Uint8List.fromList(<int>[1, 2, 3, faceIndex]),
          qualityScore: 0.9,
          deviceEmbedding: unitVector(faceIndex),
        ),
    ],
  );
}

void main() {
  setUpAll(() async {
    await BrainCoreRuntime.ensureInitialized();
  });

  late InMemoryProtectedLocalStore store;
  late DateTime now;

  LocalSampleSchoolIdentityService school({FakeRebuilder? rebuilder}) =>
      LocalSampleSchoolIdentityService(
        store: store,
        rebuilder: rebuilder ?? FakeRebuilder(),
        clock: () => now,
      );

  setUp(() {
    store = InMemoryProtectedLocalStore();
    now = DateTime.now().toUtc();
  });

  Future<OfficialFaceTemplateContext> downloaded(
    LocalSampleSchoolIdentityService service,
    String studentId,
  ) async {
    final envelope = await service.downloadOfficialTemplate(studentId);
    expect(envelope, isNotNull);
    return templateContext(
      studentId: studentId,
      envelope: envelope!,
      trustedKeys: await service.trustedTemplateKeysJson(),
      nowMs: now.millisecondsSinceEpoch,
    );
  }

  test(
    'a registration waits for approval and cannot be used before it',
    () async {
      final service = school();
      expect(
        (await service.fetchStatus('STD/1')).state,
        OfficialFaceIdState.notSubmitted,
      );

      await service.submitRegistration(submission('STD/1'));

      final status = await service.fetchStatus('STD/1');
      expect(status.state, OfficialFaceIdState.pendingApproval);
      expect(await service.downloadOfficialTemplate('STD/1'), isNull);
      final pending = await service.pendingReviews();
      expect(pending.single.studentId, 'STD/1');
      expect(pending.single.photoCount, 7);
    },
  );

  test(
    'approval rebuilds and signs a template only this student can use',
    () async {
      final service = school();
      await service.submitRegistration(submission('STD/1'));
      final result = await service.approve('sub-1');
      expect(result.approved, isTrue, reason: result.message);
      expect(result.usablePhotos, 7);

      final status = await service.fetchStatus('STD/1');
      expect(status.state, OfficialFaceIdState.approved);
      expect(status.activeTemplateId, result.templateId);
      expect(await service.pendingReviews(), isEmpty);

      final context = await downloaded(service, 'STD/1');
      expect(context.status.valid, isTrue, reason: context.status.reason);
      expect(context.status.buildSource, 'rebuilt_from_approved_photos');
      expect(context.status.referenceCount, 7);
      expect(context.status.keyEnvironment, 'sample');

      final envelope = (await service.downloadOfficialTemplate('STD/1'))!;
      final asOther = templateContext(
        studentId: 'STD/2',
        envelope: envelope,
        trustedKeys: await service.trustedTemplateKeysJson(),
        nowMs: now.millisecondsSinceEpoch,
      );
      expect(asOther.status.valid, isFalse);
    },
  );

  test('photos that disagree with the device data are not approved', () async {
    final service = school(
      rebuilder: FakeRebuilder(
        rebuiltFor: (photo) =>
            photo.poseCode == 'smile' ? unitVector(5) : photo.deviceEmbedding,
      ),
    );
    await service.submitRegistration(submission('STD/1'));
    final result = await service.approve('sub-1');
    expect(result.approved, isFalse);
    expect(result.message, contains('does not match'));
    expect(
      (await service.fetchStatus('STD/1')).state,
      OfficialFaceIdState.pendingApproval,
    );
  });

  test('too few clear photos cannot be approved', () async {
    final service = school(
      rebuilder: FakeRebuilder(
        unusablePoses: const {'left_angle', 'right_angle', 'look_up'},
      ),
    );
    await service.submitRegistration(submission('STD/1'));
    final result = await service.approve('sub-1');
    expect(result.approved, isFalse);
    expect(result.usablePhotos, 4);
  });

  test('a rejected student sees the reason and can register again', () async {
    final service = school();
    await service.submitRegistration(submission('STD/1'));
    expect(await service.reject('sub-1', reason: 'Face is covered.'), isTrue);

    final rejected = await service.fetchStatus('STD/1');
    expect(rejected.state, OfficialFaceIdState.rejected);
    expect(rejected.lastRejectionReason, 'Face is covered.');
    expect((await service.approve('sub-1')).approved, isFalse);

    await service.submitRegistration(submission('STD/1', id: 'sub-2'));
    expect(
      (await service.fetchStatus('STD/1')).state,
      OfficialFaceIdState.pendingApproval,
    );
  });

  test(
    'an approved Face ID stays active until its replacement is approved',
    () async {
      final service = school();
      await service.submitRegistration(submission('STD/1'));
      final first = await service.approve('sub-1');

      await service.submitRegistration(
        submission('STD/1', id: 'sub-2', faceIndex: 3),
      );
      final waiting = await service.fetchStatus('STD/1');
      expect(waiting.state, OfficialFaceIdState.approved);
      expect(waiting.hasPendingSubmission, isTrue);
      expect(waiting.activeTemplateId, first.templateId);

      final second = await service.approve('sub-2');
      expect(second.approved, isTrue);
      final replaced = await service.fetchStatus('STD/1');
      expect(replaced.activeTemplateId, second.templateId);
      expect(replaced.hasPendingSubmission, isFalse);
    },
  );

  test('a newer registration replaces one still waiting for review', () async {
    final service = school();
    await service.submitRegistration(submission('STD/1'));
    await service.submitRegistration(submission('STD/1', id: 'sub-2'));

    final pending = await service.pendingReviews();
    expect(pending.map((item) => item.submissionId), ['sub-2']);
    expect((await service.approve('sub-1')).approved, isFalse);
  });

  test('stores uploaded identity evidence', () async {
    final service = school();
    final stored = await service.uploadIdentityEvidence([
      <String, Object?>{'record_id': 'idev-1', 'decision': 'identity_verified'},
      <String, Object?>{'record_id': '../escape'},
    ]);
    expect(stored, ['idev-1']);
    expect(
      (await service.storedEvidence()).single['decision'],
      'identity_verified',
    );
  });
}

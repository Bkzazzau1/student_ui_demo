import 'package:flutter_test/flutter_test.dart';
import 'package:students_ui_demo/face_demo/demo_face_id_service.dart';
import 'package:students_ui_demo/face_demo/face_identity_enrollment_gate.dart';

DemoFaceIdSnapshot _snapshot({required bool locked, int capturedSamples = 0}) {
  return DemoFaceIdSnapshot(
    studentId: 'KASU/STU/2026/001',
    requiredSamples: 7,
    capturedSamples: capturedSamples,
    lastQualityScore: null,
    updatedAt: null,
    backendSynced: locked,
    locked: locked,
    enrollmentId: locked ? 'enrollment-1' : '',
    status: locked ? 'dev_local_approved' : 'not_enrolled',
    downloadedImageUrls: const <String>[],
  );
}

void main() {
  const gate = FaceIdentityEnrollmentGate();

  test('a brand-new student with no local template requires enrollment', () {
    expect(
      gate.requiresEnrollment(
        snapshot: _snapshot(locked: false),
        hasValidLocalTemplate: false,
      ),
      isTrue,
    );
  });

  test('a locked snapshot with a valid local template never re-enrolls', () {
    expect(
      gate.requiresEnrollment(
        snapshot: _snapshot(locked: true, capturedSamples: 7),
        hasValidLocalTemplate: true,
      ),
      isFalse,
    );
    expect(
      gate.shouldConfirmExistingIdentity(
        snapshot: _snapshot(locked: true, capturedSamples: 7),
        hasValidLocalTemplate: true,
      ),
      isTrue,
    );
  });

  test('a valid local template short-circuits enrollment even if the snapshot is stale', () {
    // A device restart, cache clear, or "not yet backend-locked" snapshot
    // must never force a second enrollment once a valid protected template
    // already exists locally.
    expect(
      gate.requiresEnrollment(
        snapshot: _snapshot(locked: false),
        hasValidLocalTemplate: true,
      ),
      isFalse,
    );
  });

  test('a locked snapshot without a loadable template does not silently re-enroll', () {
    // Locked-but-missing-template (e.g. the protected template file was
    // removed on this device) must be handled by an explicit device
    // re-setup step, not by silently starting a new guided capture. The
    // gate reports "no automatic enrollment" here; callers that also need
    // to detect this specific edge case check `snapshot.locked` directly.
    expect(
      gate.requiresEnrollment(
        snapshot: _snapshot(locked: true, capturedSamples: 7),
        hasValidLocalTemplate: false,
      ),
      isFalse,
    );
  });
}

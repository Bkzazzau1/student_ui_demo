import 'demo_face_id_service.dart';

/// Decides, once, whether a student needs to go through guided enrollment
/// or should go straight to confirming an identity that already exists.
///
/// This is the single source of truth for the "enroll once" rule: normal
/// navigation, logout/login, or an application restart must never re-trigger
/// enrollment for a student who already has a valid locked local identity.
class FaceIdentityEnrollmentGate {
  const FaceIdentityEnrollmentGate();

  /// True when guided capture should run for this student.
  bool requiresEnrollment({
    required DemoFaceIdSnapshot snapshot,
    required bool hasValidLocalTemplate,
  }) {
    if (hasValidLocalTemplate) return false;
    return !snapshot.locked;
  }

  /// True when the student already has an identity to confirm instead.
  bool shouldConfirmExistingIdentity({
    required DemoFaceIdSnapshot snapshot,
    required bool hasValidLocalTemplate,
  }) => !requiresEnrollment(
    snapshot: snapshot,
    hasValidLocalTemplate: hasValidLocalTemplate,
  );
}

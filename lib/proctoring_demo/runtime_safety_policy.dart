import 'package:flutter/foundation.dart';

/// Central policy for build-time overrides and real-exam safety.
///
/// Development flags are useful while testing camera, microphone, and backend
/// integration. They must never unlock a real supervised exam in release mode.
class RuntimeSafetyPolicy {
  const RuntimeSafetyPolicy._();

  static const bool allowExamOverride = bool.fromEnvironment(
    'KSLAS_ALLOW_EXAM_OVERRIDE',
    defaultValue: false,
  );

  static const bool allowAudioReviewOverride = bool.fromEnvironment(
    'KSLAS_ALLOW_AUDIO_REVIEW_OVERRIDE',
    defaultValue: false,
  );

  static const bool allowSystemReviewOverride = bool.fromEnvironment(
    'KSLAS_ALLOW_SYSTEM_REVIEW_OVERRIDE',
    defaultValue: false,
  );

  static const bool allowLocalStartApproval = bool.fromEnvironment(
    'KSLAS_ALLOW_LOCAL_START_APPROVAL',
    defaultValue: false,
  );

  static bool get anyOverrideRequested =>
      allowExamOverride ||
      allowAudioReviewOverride ||
      allowSystemReviewOverride ||
      allowLocalStartApproval;

  static bool canUseExamOverride({required bool strictExam}) {
    if (!allowExamOverride) return false;
    return _canUseOverrideForAssessment(strictExam: strictExam);
  }

  static bool canUseAudioOverride({required bool strictExam}) {
    if (!allowAudioReviewOverride && !allowExamOverride) return false;
    return _canUseOverrideForAssessment(strictExam: strictExam);
  }

  static bool canUseSystemOverride({required bool strictExam}) {
    if (!allowSystemReviewOverride && !allowExamOverride) return false;
    return _canUseOverrideForAssessment(strictExam: strictExam);
  }

  static bool canUseLocalStartApproval({required bool strictExam}) {
    if (!allowLocalStartApproval) return false;
    return _canUseOverrideForAssessment(strictExam: strictExam);
  }

  static bool _canUseOverrideForAssessment({required bool strictExam}) {
    if (!strictExam) return true;
    return !kReleaseMode;
  }

  static String blockedOverrideMessage({required String checkName}) {
    return '$checkName testing override is disabled for supervised exams in release builds.';
  }
}

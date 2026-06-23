enum LiveMonitoringMode {
  strictExam,
  gradedAssessmentLight,
  standard,
}

class LiveMonitoringProfile {
  const LiveMonitoringProfile({
    required this.mode,
    required this.studentLabel,
    required this.reviewAudience,
    required this.cameraIssuePausesAttempt,
    required this.audioIssuePausesAttempt,
    required this.objectIssuePausesAttempt,
    required this.gazeIssuePausesAttempt,
    required this.systemIssuePausesAttempt,
    required this.needsSystemChecks,
    required this.objectFrameCooldown,
  });

  final LiveMonitoringMode mode;
  final String studentLabel;
  final String reviewAudience;
  final bool cameraIssuePausesAttempt;
  final bool audioIssuePausesAttempt;
  final bool objectIssuePausesAttempt;
  final bool gazeIssuePausesAttempt;
  final bool systemIssuePausesAttempt;
  final bool needsSystemChecks;
  final Duration objectFrameCooldown;

  bool get strictPauseEnabled =>
      cameraIssuePausesAttempt ||
      audioIssuePausesAttempt ||
      objectIssuePausesAttempt ||
      gazeIssuePausesAttempt ||
      systemIssuePausesAttempt;

  Map<String, Object?> toJson() => <String, Object?>{
        'mode': mode.name,
        'student_label': studentLabel,
        'review_audience': reviewAudience,
        'camera_issue_pauses_attempt': cameraIssuePausesAttempt,
        'audio_issue_pauses_attempt': audioIssuePausesAttempt,
        'object_issue_pauses_attempt': objectIssuePausesAttempt,
        'gaze_issue_pauses_attempt': gazeIssuePausesAttempt,
        'system_issue_pauses_attempt': systemIssuePausesAttempt,
        'needs_system_checks': needsSystemChecks,
        'object_frame_cooldown_ms': objectFrameCooldown.inMilliseconds,
      };

  static LiveMonitoringProfile forAssessmentType(
    String assessmentType, {
    String? reviewAudience,
  }) {
    final normalized = assessmentType.trim().toLowerCase().replaceAll('-', '_');
    if (normalized == 'exam' || normalized == 'final_exam') {
      return LiveMonitoringProfile.strictExam(reviewAudience: reviewAudience);
    }
    if (normalized == 'graded' || normalized == 'graded_assessment') {
      return LiveMonitoringProfile.gradedAssessmentLight(
        reviewAudience: reviewAudience,
      );
    }
    return LiveMonitoringProfile.standard(reviewAudience: reviewAudience);
  }

  factory LiveMonitoringProfile.strictExam({String? reviewAudience}) {
    return LiveMonitoringProfile(
      mode: LiveMonitoringMode.strictExam,
      studentLabel: 'Secure exam checks',
      reviewAudience: reviewAudience ?? 'invigilator',
      cameraIssuePausesAttempt: true,
      audioIssuePausesAttempt: true,
      objectIssuePausesAttempt: true,
      gazeIssuePausesAttempt: true,
      systemIssuePausesAttempt: true,
      needsSystemChecks: true,
      objectFrameCooldown: const Duration(seconds: 15),
    );
  }

  factory LiveMonitoringProfile.gradedAssessmentLight({String? reviewAudience}) {
    return LiveMonitoringProfile(
      mode: LiveMonitoringMode.gradedAssessmentLight,
      studentLabel: 'Light assessment monitoring',
      reviewAudience: reviewAudience ?? 'lecturer',
      cameraIssuePausesAttempt: false,
      audioIssuePausesAttempt: false,
      objectIssuePausesAttempt: false,
      gazeIssuePausesAttempt: false,
      systemIssuePausesAttempt: false,
      needsSystemChecks: false,
      objectFrameCooldown: const Duration(seconds: 45),
    );
  }

  factory LiveMonitoringProfile.standard({String? reviewAudience}) {
    return LiveMonitoringProfile(
      mode: LiveMonitoringMode.standard,
      studentLabel: 'Standard access',
      reviewAudience: reviewAudience ?? 'lecturer',
      cameraIssuePausesAttempt: false,
      audioIssuePausesAttempt: false,
      objectIssuePausesAttempt: false,
      gazeIssuePausesAttempt: false,
      systemIssuePausesAttempt: false,
      needsSystemChecks: false,
      objectFrameCooldown: const Duration(minutes: 1),
    );
  }

  bool shouldPauseForEventType(String eventType) {
    switch (eventType) {
      case 'camera_unavailable':
      case 'camera_reconnect_timeout':
      case 'camera_view_needs_review':
      case 'multiple_people_detected':
        return cameraIssuePausesAttempt;
      case 'microphone_unavailable':
      case 'microphone_reconnect_timeout':
      case 'audio_voice_isolation_alert':
      case 'background_voice_environment_warning':
      case 'audio_repeated_fingerprint_detected':
        return audioIssuePausesAttempt;
      case 'yolo_phone_detected':
      case 'yolo_extra_screen_detected':
      case 'yolo_book_or_paper_detected':
      case 'yolo_calculator_detected':
      case 'object_reflection_shadow_risk':
      case 'object_reflection_shadow_warning':
        return objectIssuePausesAttempt;
      case 'gaze_head_pose_deviation':
      case 'continuous_liveness_spoof_risk':
      case 'continuous_liveness_continuity_loss':
        return gazeIssuePausesAttempt;
      case 'system_monitoring_unavailable':
        return systemIssuePausesAttempt;
      default:
        return false;
    }
  }
}

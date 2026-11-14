import 'demo_exam_models.dart';

enum AssessmentMonitoringMode {
  strictExam,
  gradedLight,
  standardAccess,
}

class AssessmentMonitoringProfile {
  const AssessmentMonitoringProfile({
    required this.mode,
    required this.label,
    required this.panelTitle,
    required this.requiresCamera,
    required this.requiresMicrophone,
    required this.usesSystemSecurityPanel,
    required this.usesReviewClipSampler,
    required this.usesCompanionCamera,
    required this.autoSubmitWhenBackgrounded,
    required this.pauseOnCriticalMonitoringEvent,
    required this.reviewAudience,
  });

  final AssessmentMonitoringMode mode;
  final String label;
  final String panelTitle;
  final bool requiresCamera;
  final bool requiresMicrophone;
  final bool usesSystemSecurityPanel;
  final bool usesReviewClipSampler;
  final bool usesCompanionCamera;
  final bool autoSubmitWhenBackgrounded;
  final bool pauseOnCriticalMonitoringEvent;
  final String reviewAudience;

  bool get showsLiveMonitor => requiresCamera || requiresMicrophone;

  Map<String, Object?> toJson() => <String, Object?>{
        'mode': mode.name,
        'label': label,
        'panel_title': panelTitle,
        'requires_camera': requiresCamera,
        'requires_microphone': requiresMicrophone,
        'uses_system_security_panel': usesSystemSecurityPanel,
        'uses_review_clip_sampler': usesReviewClipSampler,
        'uses_companion_camera': usesCompanionCamera,
        'auto_submit_when_backgrounded': autoSubmitWhenBackgrounded,
        'pause_on_critical_monitoring_event': pauseOnCriticalMonitoringEvent,
        'review_audience': reviewAudience,
      };

  static AssessmentMonitoringProfile forAssessment(DemoAssessment assessment) {
    if (assessment.isStrictExam) {
      return const AssessmentMonitoringProfile(
        mode: AssessmentMonitoringMode.strictExam,
        label: 'Secure exam mode',
        panelTitle: 'Live exam checks',
        requiresCamera: true,
        requiresMicrophone: true,
        usesSystemSecurityPanel: true,
        usesReviewClipSampler: true,
        usesCompanionCamera: true,
        autoSubmitWhenBackgrounded: true,
        pauseOnCriticalMonitoringEvent: true,
        reviewAudience: 'invigilator',
      );
    }

    if (assessment.isGradedAssessment) {
      return const AssessmentMonitoringProfile(
        mode: AssessmentMonitoringMode.gradedLight,
        label: 'Light assessment monitoring',
        panelTitle: 'Assessment checks',
        requiresCamera: true,
        requiresMicrophone: true,
        usesSystemSecurityPanel: false,
        usesReviewClipSampler: false,
        usesCompanionCamera: false,
        autoSubmitWhenBackgrounded: false,
        pauseOnCriticalMonitoringEvent: false,
        reviewAudience: 'lecturer',
      );
    }

    return const AssessmentMonitoringProfile(
      mode: AssessmentMonitoringMode.standardAccess,
      label: 'Standard access',
      panelTitle: 'Learning activity',
      requiresCamera: false,
      requiresMicrophone: false,
      usesSystemSecurityPanel: false,
      usesReviewClipSampler: false,
      usesCompanionCamera: false,
      autoSubmitWhenBackgrounded: false,
      pauseOnCriticalMonitoringEvent: false,
      reviewAudience: 'lecturer',
    );
  }
}

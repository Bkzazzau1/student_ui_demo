enum AssessmentAccessKind {
  exam,
  gradedAssessment,
  ungradedAssessment,
  practiceQuestion,
  assignment,
}

enum AssessmentDeviceClass {
  desktop,
  tablet,
  ipad,
  mobilePhone,
  unknown,
}

class AssessmentDeviceAccessDecision {
  const AssessmentDeviceAccessDecision({
    required this.allowed,
    required this.title,
    required this.message,
    required this.requiresDesktopMode,
  });

  final bool allowed;
  final String title;
  final String message;
  final bool requiresDesktopMode;

  Map<String, Object?> toJson() => <String, Object?>{
        'allowed': allowed,
        'title': title,
        'message': message,
        'requires_desktop_mode': requiresDesktopMode,
      };
}

class AssessmentDeviceAccessPolicy {
  const AssessmentDeviceAccessPolicy._();

  static AssessmentDeviceAccessDecision decisionFor({
    required AssessmentAccessKind assessmentKind,
    required AssessmentDeviceClass deviceClass,
  }) {
    final isExam = assessmentKind == AssessmentAccessKind.exam;
    final examAllowed = deviceClass == AssessmentDeviceClass.desktop ||
        deviceClass == AssessmentDeviceClass.tablet ||
        deviceClass == AssessmentDeviceClass.ipad;

    if (!isExam) {
      return const AssessmentDeviceAccessDecision(
        allowed: true,
        title: 'Available on this device',
        message:
            'You can use this device for graded assessments, ungraded assessments, practice questions, and assignments.',
        requiresDesktopMode: false,
      );
    }

    if (examAllowed) {
      return const AssessmentDeviceAccessDecision(
        allowed: true,
        title: 'Exam device ready',
        message: 'Exams can be taken on desktop, tablet, or iPad devices.',
        requiresDesktopMode: true,
      );
    }

    return const AssessmentDeviceAccessDecision(
      allowed: false,
      title: 'Use a larger approved device',
      message:
          'This exam must be taken on a desktop, tablet, or iPad. Please switch device before starting.',
      requiresDesktopMode: true,
    );
  }

  static AssessmentAccessKind kindFromString(String value) {
    switch (value.trim().toLowerCase().replaceAll('-', '_')) {
      case 'exam':
      case 'final_exam':
        return AssessmentAccessKind.exam;
      case 'graded':
      case 'graded_assessment':
      case 'assessment_graded':
        return AssessmentAccessKind.gradedAssessment;
      case 'ungraded':
      case 'ungraded_assessment':
      case 'assessment_ungraded':
        return AssessmentAccessKind.ungradedAssessment;
      case 'practice':
      case 'practice_question':
      case 'practice_questions':
        return AssessmentAccessKind.practiceQuestion;
      case 'assignment':
      case 'course_assignment':
        return AssessmentAccessKind.assignment;
      default:
        return AssessmentAccessKind.practiceQuestion;
    }
  }
}

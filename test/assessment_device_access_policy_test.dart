import 'package:flutter_test/flutter_test.dart';
import 'package:students_ui_demo/exam_demo/assessment_device_access_policy.dart';

void main() {
  group('AssessmentDeviceAccessPolicy', () {
    test('allows graded assessments on mobile phones', () {
      final decision = AssessmentDeviceAccessPolicy.decisionFor(
        assessmentKind: AssessmentAccessKind.gradedAssessment,
        deviceClass: AssessmentDeviceClass.mobilePhone,
      );

      expect(decision.allowed, isTrue);
      expect(decision.requiresDesktopMode, isFalse);
    });

    test('allows ungraded assessments, practice, and assignments on phones', () {
      for (final kind in const <AssessmentAccessKind>[
        AssessmentAccessKind.ungradedAssessment,
        AssessmentAccessKind.practiceQuestion,
        AssessmentAccessKind.assignment,
      ]) {
        final decision = AssessmentDeviceAccessPolicy.decisionFor(
          assessmentKind: kind,
          deviceClass: AssessmentDeviceClass.mobilePhone,
        );

        expect(decision.allowed, isTrue);
      }
    });

    test('blocks exams on mobile phones', () {
      final decision = AssessmentDeviceAccessPolicy.decisionFor(
        assessmentKind: AssessmentAccessKind.exam,
        deviceClass: AssessmentDeviceClass.mobilePhone,
      );

      expect(decision.allowed, isFalse);
      expect(decision.requiresDesktopMode, isTrue);
    });

    test('allows exams on desktop, tablet, and ipad', () {
      for (final deviceClass in const <AssessmentDeviceClass>[
        AssessmentDeviceClass.desktop,
        AssessmentDeviceClass.tablet,
        AssessmentDeviceClass.ipad,
      ]) {
        final decision = AssessmentDeviceAccessPolicy.decisionFor(
          assessmentKind: AssessmentAccessKind.exam,
          deviceClass: deviceClass,
        );

        expect(decision.allowed, isTrue);
        expect(decision.requiresDesktopMode, isTrue);
      }
    });

    test('maps backend assessment type strings', () {
      expect(
        AssessmentDeviceAccessPolicy.kindFromString('graded_assessment'),
        AssessmentAccessKind.gradedAssessment,
      );
      expect(
        AssessmentDeviceAccessPolicy.kindFromString('ungraded-assessment'),
        AssessmentAccessKind.ungradedAssessment,
      );
      expect(
        AssessmentDeviceAccessPolicy.kindFromString('final_exam'),
        AssessmentAccessKind.exam,
      );
    });
  });
}

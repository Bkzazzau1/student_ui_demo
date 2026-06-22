import 'package:flutter_test/flutter_test.dart';
import 'package:students_ui_demo/exam_demo/assessment_monitoring_profile.dart';
import 'package:students_ui_demo/exam_demo/demo_exam_models.dart';

void main() {
  const course = DemoCourse(
    code: 'CSC 201',
    title: 'Data Structures',
    lecturer: 'Dr. Amina Yusuf',
  );

  const strictExam = DemoAssessment(
    id: 'exam-1',
    course: course,
    title: 'Final Examination',
    kind: 'Exam',
    durationMinutes: 120,
    graded: true,
    remoteProctored: true,
    policy: AssessmentPolicy.strictExam,
    sections: <DemoExamSection>[DemoExamSection.objective],
  );

  const gradedAssessment = DemoAssessment(
    id: 'graded-1',
    course: course,
    title: 'Week 3 Graded Assessment',
    kind: 'Graded Assessment',
    durationMinutes: 30,
    graded: true,
    remoteProctored: true,
    policy: AssessmentPolicy.gradedAssessment,
    sections: <DemoExamSection>[DemoExamSection.objective],
  );

  const practice = DemoAssessment(
    id: 'practice-1',
    course: course,
    title: 'Practice Questions',
    kind: 'Practice',
    durationMinutes: 0,
    graded: false,
    remoteProctored: false,
    policy: AssessmentPolicy.practice,
    sections: <DemoExamSection>[DemoExamSection.objective],
  );

  test('strict exam uses full monitoring profile', () {
    final profile = AssessmentMonitoringProfile.forAssessment(strictExam);

    expect(profile.mode, AssessmentMonitoringMode.strictExam);
    expect(profile.usesSystemSecurityPanel, isTrue);
    expect(profile.usesReviewClipSampler, isTrue);
    expect(profile.usesCompanionCamera, isTrue);
    expect(profile.autoSubmitWhenBackgrounded, isTrue);
    expect(profile.pauseOnCriticalMonitoringEvent, isTrue);
    expect(profile.reviewAudience, 'invigilator');
  });

  test('graded assessment uses light monitoring profile', () {
    final profile = AssessmentMonitoringProfile.forAssessment(gradedAssessment);

    expect(profile.mode, AssessmentMonitoringMode.gradedLight);
    expect(profile.requiresCamera, isTrue);
    expect(profile.requiresMicrophone, isTrue);
    expect(profile.usesSystemSecurityPanel, isFalse);
    expect(profile.usesReviewClipSampler, isFalse);
    expect(profile.usesCompanionCamera, isFalse);
    expect(profile.autoSubmitWhenBackgrounded, isFalse);
    expect(profile.pauseOnCriticalMonitoringEvent, isFalse);
    expect(profile.reviewAudience, 'lecturer');
  });

  test('practice uses standard access profile', () {
    final profile = AssessmentMonitoringProfile.forAssessment(practice);

    expect(profile.mode, AssessmentMonitoringMode.standardAccess);
    expect(profile.showsLiveMonitor, isFalse);
    expect(profile.usesSystemSecurityPanel, isFalse);
    expect(profile.usesReviewClipSampler, isFalse);
    expect(profile.usesCompanionCamera, isFalse);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:students_ui_demo/exam_demo/assessment_device_access_policy.dart';
import 'package:students_ui_demo/exam_demo/assessment_device_gate.dart';
import 'package:students_ui_demo/exam_demo/demo_exam_models.dart';

void main() {
  const course = DemoCourse(
    code: 'CSC 201',
    title: 'Data Structures',
    lecturer: 'Dr. Amina Yusuf',
  );

  const exam = DemoAssessment(
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

  const graded = DemoAssessment(
    id: 'ga-1',
    course: course,
    title: 'Week 3 Graded Assessment',
    kind: 'Graded Assessment',
    durationMinutes: 30,
    graded: true,
    remoteProctored: true,
    policy: AssessmentPolicy.gradedAssessment,
    sections: <DemoExamSection>[DemoExamSection.objective],
  );

  test('resolves desktop and mobile device classes', () {
    expect(
      AssessmentDeviceClassResolver.resolve(
        platform: TargetPlatform.windows,
        shortestSide: 390,
      ),
      AssessmentDeviceClass.desktop,
    );
    expect(
      AssessmentDeviceClassResolver.resolve(
        platform: TargetPlatform.android,
        shortestSide: 390,
      ),
      AssessmentDeviceClass.mobilePhone,
    );
    expect(
      AssessmentDeviceClassResolver.resolve(
        platform: TargetPlatform.android,
        shortestSide: 720,
      ),
      AssessmentDeviceClass.tablet,
    );
    expect(
      AssessmentDeviceClassResolver.resolve(
        platform: TargetPlatform.iOS,
        shortestSide: 720,
      ),
      AssessmentDeviceClass.ipad,
    );
  });

  testWidgets('blocks exam attempt on mobile phone', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: AssessmentDeviceGate(
          assessment: exam,
          deviceClassOverride: AssessmentDeviceClass.mobilePhone,
          child: Text('Attempt screen'),
        ),
      ),
    );

    expect(find.text('Attempt screen'), findsNothing);
    expect(find.text('Use a larger approved device'), findsOneWidget);
  });

  testWidgets('allows graded assessment attempt on mobile phone', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: AssessmentDeviceGate(
          assessment: graded,
          deviceClassOverride: AssessmentDeviceClass.mobilePhone,
          child: Text('Attempt screen'),
        ),
      ),
    );

    expect(find.text('Attempt screen'), findsOneWidget);
    expect(find.text('Use a larger approved device'), findsNothing);
  });
}

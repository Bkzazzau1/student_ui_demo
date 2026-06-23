import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:students_ui_demo/exam_demo/student_assessment_hub_extras.dart';

void main() {
  test('assignments are available with mobile access label', () {
    final assignments = DemoStudentHubExtras.assignmentsForDate(
      DateTime(2026, 6, 23),
    );

    expect(assignments, isNotEmpty);
    expect(assignments.first.accessLabel, contains('Mobile allowed'));
    expect(assignments.first.dueLabel, '26/06/2026');
  });

  test('feedback items are available with released date label', () {
    final feedback = DemoStudentHubExtras.feedbackForDate(
      DateTime(2026, 6, 23),
    );

    expect(feedback, isNotEmpty);
    expect(feedback.first.releasedLabel, '22/06/2026');
    expect(feedback.first.scoreLabel, isNotEmpty);
  });

  testWidgets('extras panel renders assignments and feedback', (tester) async {
    final date = DateTime(2026, 6, 23);
    DemoAssignmentItem? openedAssignment;
    DemoFeedbackItem? openedFeedback;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: StudentAssessmentHubExtrasPanel(
              assignments: DemoStudentHubExtras.assignmentsForDate(date),
              feedbackItems: DemoStudentHubExtras.feedbackForDate(date),
              onOpenAssignment: (assignment) {
                openedAssignment = assignment;
              },
              onOpenFeedback: (feedbackItem) {
                openedFeedback = feedbackItem;
              },
            ),
          ),
        ),
      ),
    );

    expect(find.text('Assignments'), findsOneWidget);
    expect(find.text('Feedback'), findsOneWidget);
    expect(find.text('Open assignment'), findsWidgets);
    expect(find.text('View feedback'), findsWidgets);

    await tester.tap(find.text('Open assignment').first);
    expect(openedAssignment, isNotNull);

    await tester.ensureVisible(find.text('View feedback').first);
    await tester.tap(find.text('View feedback').first);
    expect(openedFeedback, isNotNull);
  });
}

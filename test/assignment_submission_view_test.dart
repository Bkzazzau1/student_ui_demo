import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:students_ui_demo/exam_demo/assignment_submission_view.dart';
import 'package:students_ui_demo/exam_demo/student_assessment_hub_extras.dart';

void main() {
  testWidgets('assignment submission view submits typed answer', (tester) async {
    final assignment = DemoStudentHubExtras.assignmentsForDate(
      DateTime(2026, 6, 23),
    ).first;
    AssignmentSubmissionResult? result;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () async {
                result = await Navigator.of(context).push<AssignmentSubmissionResult>(
                  MaterialPageRoute<AssignmentSubmissionResult>(
                    builder: (_) => AssignmentSubmissionView(assignment: assignment),
                  ),
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('Assignment submission'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'My assignment response');
    await tester.pump();

    await tester.tap(find.text('Submit assignment'));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.assignment.id, assignment.id);
    expect(result!.answerText, 'My assignment response');
    expect(result!.hasAttachment, isFalse);
  });

  testWidgets('assignment submission view can attach demo file', (tester) async {
    final assignment = DemoStudentHubExtras.assignmentsForDate(
      DateTime(2026, 6, 23),
    ).first;

    await tester.pumpWidget(
      MaterialApp(
        home: AssignmentSubmissionView(assignment: assignment),
      ),
    );

    await tester.tap(find.text('Attach demo file'));
    await tester.pump();

    expect(find.text('assignment_response.pdf'), findsOneWidget);
    expect(find.text('Remove attachment'), findsOneWidget);
  });
}

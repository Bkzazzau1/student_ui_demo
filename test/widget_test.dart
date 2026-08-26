import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:students_ui_demo/exam_demo/demo_exam_home.dart';
import 'package:students_ui_demo/exam_demo/demo_exam_service.dart';
import 'package:students_ui_demo/exam_demo/secure_exam_setup_view.dart';
import 'package:students_ui_demo/main.dart';

void main() {
  testWidgets('student assessment gateway renders', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const StudentsUiDemoApp());

    expect(find.text('K-SLAS Exam Portal'), findsOneWidget);
    expect(find.text('Student Login'), findsOneWidget);
    expect(find.textContaining('prefilled'), findsOneWidget);
  });

  testWidgets('mobile login is focused, visible, and overflow-free', (
    WidgetTester tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(const StudentsUiDemoApp());
    await tester.pumpAndSettle();

    expect(find.text('K-SLAS Exam Portal'), findsOneWidget);
    expect(find.text('Student Login'), findsOneWidget);
    expect(find.text('Sign In'), findsOneWidget);
    expect(tester.getBottomRight(find.text('Sign In')).dy, lessThan(844));
    expect(tester.takeException(), isNull);
  });

  testWidgets('student can open logout page', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const StudentsUiDemoApp());

    await tester.ensureVisible(find.text('Sign In'));
    await tester.tap(find.text('Sign In'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Sign out'));
    await tester.pumpAndSettle();

    expect(find.text('End student session?'), findsOneWidget);
    expect(find.text('Stay in portal'), findsOneWidget);
    expect(find.text('Sign out'), findsWidgets);
  });

  testWidgets('mobile dashboard prioritizes the next exam without overflow', (
    WidgetTester tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(const MaterialApp(home: DemoExamHome()));
    await tester.pumpAndSettle();

    expect(find.text('Exam Portal'), findsOneWidget);
    expect(find.text('Next assessment'), findsOneWidget);
    expect(find.text('STUDENT TOOLS'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Next assessment')).dy,
      lessThan(tester.getTopLeft(find.text('STUDENT TOOLS')).dy),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('graded mobile setup puts readiness before final identity', (
    WidgetTester tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final assessment = DemoExamService.assessmentsForDate(
      DateTime.now(),
    ).firstWhere((item) => item.isGradedAssessment);

    await tester.pumpWidget(
      MaterialApp(home: SecureExamSetupView(assessment: assessment)),
    );
    await tester.pump();

    expect(find.text('Phone security and sound'), findsOneWidget);
    expect(find.text('Final readiness'), findsOneWidget);
    expect(find.text('Identity check — final step'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Final readiness')).dy,
      lessThan(tester.getTopLeft(find.text('Identity check — final step')).dy),
    );
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(milliseconds: 1));
  });
}

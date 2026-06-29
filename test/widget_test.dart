import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:students_ui_demo/main.dart';

void main() {
  testWidgets('student assessment gateway renders', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const StudentsUiDemoApp());

    expect(find.text('K-SLAS Student Portal'), findsOneWidget);
    expect(find.text('Student Login'), findsOneWidget);
    expect(find.text('Demo Credentials'), findsOneWidget);
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
}

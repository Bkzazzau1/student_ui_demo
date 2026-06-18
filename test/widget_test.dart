import 'package:flutter_test/flutter_test.dart';
import 'package:students_ui_demo/main.dart';

void main() {
  testWidgets('student assessment gateway renders', (WidgetTester tester) async {
    await tester.pumpWidget(const StudentsUiDemoApp());

    expect(find.text('K-SLAS Student Portal'), findsWidgets);
    expect(find.text('Mid-semester proctored examination'), findsOneWidget);
  });
}

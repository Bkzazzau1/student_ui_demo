import 'package:flutter_test/flutter_test.dart';
import 'package:students_ui_demo/main.dart';

void main() {
  testWidgets('proctoring demo renders', (WidgetTester tester) async {
    await tester.pumpWidget(const StudentsUiDemoApp());

    expect(find.text('Student Examinations Demo'), findsWidgets);
    expect(find.text('Examinations and assessments'), findsOneWidget);
    expect(find.text('Mid-semester examination'), findsOneWidget);
  });
}

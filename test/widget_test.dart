import 'package:flutter_test/flutter_test.dart';
import 'package:get_storage/get_storage.dart';
import 'package:students_ui_demo/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await GetStorage.init();
  });

  testWidgets('student login screen renders', (WidgetTester tester) async {
    await tester.pumpWidget(const StudentsUiDemoApp());

    expect(find.text('K-SLAS Student Portal'), findsWidgets);
    expect(find.text('Sign in to continue'), findsOneWidget);
    expect(find.text('Continue to student portal'), findsOneWidget);
  });
}

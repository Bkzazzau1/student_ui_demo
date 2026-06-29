import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_storage/get_storage.dart';
import 'package:students_ui_demo/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final storageDirectory =
        await Directory.systemTemp.createTemp('students_ui_demo_test_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return storageDirectory.path;
        }
        return null;
      },
    );
    await GetStorage('GetStorage', storageDirectory.path).initStorage;
  });

  testWidgets('student login screen renders', (WidgetTester tester) async {
    await tester.pumpWidget(const StudentsUiDemoApp());

    expect(find.text('K-SLAS Student Portal'), findsWidgets);
    expect(find.text('Sign in to continue'), findsOneWidget);
    expect(find.text('Continue to student portal'), findsOneWidget);
  });
}

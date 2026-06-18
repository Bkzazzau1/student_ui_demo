import 'package:flutter/material.dart';
import 'package:get_storage/get_storage.dart';

import 'exam_demo/demo_exam_home.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await GetStorage.init();
  runApp(const StudentsUiDemoApp());
}

class StudentsUiDemoApp extends StatelessWidget {
  const StudentsUiDemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'K-SLAS Student Portal',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1D4ED8),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      home: const DemoExamHome(),
    );
  }
}

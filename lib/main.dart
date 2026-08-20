import 'package:flutter/material.dart';
import 'package:get_storage/get_storage.dart';

import 'auth/student_login_view.dart';
import 'exam_demo/air_board_fingertip_view.dart';
import 'rust/brain_core_runtime.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await GetStorage.init();
  await BrainCoreRuntime.ensureInitialized();
  runApp(const StudentsUiDemoApp());
}

class StudentsUiDemoApp extends StatelessWidget {
  const StudentsUiDemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'KASU DLI Assessment Portal',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF5F7FB),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0F4C81),
          brightness: Brightness.light,
        ),
      ),
      routes: <String, WidgetBuilder>{
        '/air-board': (_) => const AirBoardFingertipView(),
      },
      home: const StudentLoginView(),
    );
  }
}

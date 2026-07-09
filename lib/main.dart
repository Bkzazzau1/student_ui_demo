import 'package:flutter/material.dart';
import 'package:get_storage/get_storage.dart';

import 'auth/student_login_view.dart';
import 'exam_demo/air_board_demo_view.dart';

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
        '/air-board': (_) => const AirBoardDemoView(),
      },
      builder: (context, child) {
        return Stack(
          children: [
            child ?? const SizedBox.shrink(),
            Positioned(
              right: 18,
              bottom: 18,
              child: SafeArea(
                child: _AirBoardShortcut(
                  onPressed: () => Navigator.of(context).pushNamed('/air-board'),
                ),
              ),
            ),
          ],
        );
      },
      home: const StudentLoginView(),
    );
  }
}

class _AirBoardShortcut extends StatelessWidget {
  const _AirBoardShortcut({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xFF0F4C81),
          borderRadius: BorderRadius.circular(999),
          boxShadow: const [
            BoxShadow(
              color: Color(0x260F172A),
              blurRadius: 18,
              offset: Offset(0, 10),
            ),
          ],
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: onPressed,
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.border_color_outlined, color: Colors.white, size: 18),
                SizedBox(width: 8),
                Text(
                  'Rough-work board',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

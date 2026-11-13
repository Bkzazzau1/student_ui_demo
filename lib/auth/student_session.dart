import 'package:flutter/foundation.dart';

/// The student who is signed in on this device.
///
/// Face ID registration, the official template download, identity checks,
/// and identity evidence all use this one id, so a face can only ever be
/// compared with the signed-in student's own official Face ID.
abstract final class StudentSession {
  /// Sample id used until the university's student records are connected.
  static const String sampleStudentId = 'KSLAS/STD/2026/001';

  static final ValueNotifier<String> _studentId = ValueNotifier<String>(
    sampleStudentId,
  );

  static String get studentId => _studentId.value;

  static ValueListenable<String> get listenable => _studentId;

  static void signIn(String studentId) {
    final trimmed = studentId.trim();
    _studentId.value = trimmed.isEmpty ? sampleStudentId : trimmed;
  }
}

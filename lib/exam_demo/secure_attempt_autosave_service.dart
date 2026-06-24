import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:get_storage/get_storage.dart';

class SecureAttemptAutosaveSnapshot {
  const SecureAttemptAutosaveSnapshot({
    required this.studentId,
    required this.examId,
    required this.attemptId,
    required this.answers,
    required this.currentIndex,
    required this.remainingSeconds,
    required this.startedAt,
    required this.updatedAt,
    required this.checksum,
    required this.checksumValid,
  });

  final String studentId;
  final String examId;
  final String attemptId;
  final Map<String, String> answers;
  final int currentIndex;
  final int remainingSeconds;
  final DateTime startedAt;
  final DateTime updatedAt;
  final String checksum;
  final bool checksumValid;

  bool get hasAnswers => answers.values.any((value) => value.trim().isNotEmpty);

  Map<String, Object?> toJson() => <String, Object?>{
        'student_id': studentId,
        'exam_id': examId,
        'attempt_id': attemptId,
        'answers': answers,
        'current_index': currentIndex,
        'remaining_seconds': remainingSeconds,
        'started_at': startedAt.toUtc().toIso8601String(),
        'updated_at': updatedAt.toUtc().toIso8601String(),
        'checksum': checksum,
        'checksum_valid': checksumValid,
      };
}

class SecureAttemptAutosaveService {
  SecureAttemptAutosaveService({GetStorage? storage}) : _storage = storage ?? GetStorage();

  static const int schemaVersion = 1;
  static const String _prefix = 'kslas_secure_attempt_autosave_v1';

  final GetStorage _storage;

  Future<void> save({
    required String studentId,
    required String examId,
    required String attemptId,
    required Map<String, String> answers,
    required int currentIndex,
    required int remainingSeconds,
    required DateTime startedAt,
  }) async {
    final payload = _payload(
      studentId: studentId,
      examId: examId,
      attemptId: attemptId,
      answers: answers,
      currentIndex: currentIndex,
      remainingSeconds: remainingSeconds,
      startedAt: startedAt,
      updatedAt: DateTime.now(),
    );
    final record = <String, Object?>{
      ...payload,
      'schema_version': schemaVersion,
      'checksum': _checksum(payload),
    };
    await _storage.write(_key(attemptId), jsonEncode(record));
  }

  SecureAttemptAutosaveSnapshot? load(String attemptId) {
    final raw = _storage.read<String>(_key(attemptId));
    if (raw == null || raw.trim().isEmpty) return null;

    try {
      final record = jsonDecode(raw) as Map<String, dynamic>;
      final payload = Map<String, Object?>.from(record)
        ..remove('schema_version')
        ..remove('checksum');
      final checksum = (record['checksum'] ?? '').toString();
      final checksumValid = checksum == _checksum(payload);
      final answers = <String, String>{};
      final decodedAnswers = record['answers'];
      if (decodedAnswers is Map) {
        for (final entry in decodedAnswers.entries) {
          answers[entry.key.toString()] = entry.value?.toString() ?? '';
        }
      }

      return SecureAttemptAutosaveSnapshot(
        studentId: (record['student_id'] ?? '').toString(),
        examId: (record['exam_id'] ?? '').toString(),
        attemptId: (record['attempt_id'] ?? attemptId).toString(),
        answers: answers,
        currentIndex: int.tryParse((record['current_index'] ?? '0').toString()) ?? 0,
        remainingSeconds: int.tryParse((record['remaining_seconds'] ?? '0').toString()) ?? 0,
        startedAt: DateTime.tryParse((record['started_at'] ?? '').toString()) ?? DateTime.now(),
        updatedAt: DateTime.tryParse((record['updated_at'] ?? '').toString()) ?? DateTime.now(),
        checksum: checksum,
        checksumValid: checksumValid,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> clear(String attemptId) => _storage.remove(_key(attemptId));

  Map<String, Object?> _payload({
    required String studentId,
    required String examId,
    required String attemptId,
    required Map<String, String> answers,
    required int currentIndex,
    required int remainingSeconds,
    required DateTime startedAt,
    required DateTime updatedAt,
  }) {
    final sortedAnswers = Map<String, String>.fromEntries(
      answers.entries.toList()..sort((left, right) => left.key.compareTo(right.key)),
    );
    return <String, Object?>{
      'student_id': studentId,
      'exam_id': examId,
      'attempt_id': attemptId,
      'answers': sortedAnswers,
      'current_index': currentIndex,
      'remaining_seconds': remainingSeconds,
      'started_at': startedAt.toUtc().toIso8601String(),
      'updated_at': updatedAt.toUtc().toIso8601String(),
    };
  }

  String _checksum(Map<String, Object?> payload) {
    final canonical = jsonEncode(payload);
    return sha256.convert(utf8.encode(canonical)).toString();
  }

  String _key(String attemptId) => '$_prefix:$attemptId';
}

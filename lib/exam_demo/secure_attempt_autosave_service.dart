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
    this.recoveredFrom = 'primary',
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
  final String recoveredFrom;

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
        'recovered_from': recoveredFrom,
      };
}

class SecureAttemptAutosaveService {
  SecureAttemptAutosaveService({GetStorage? storage}) : _storage = storage ?? GetStorage();

  static const int schemaVersion = 2;
  static const String _prefix = 'kslas_secure_attempt_autosave_v2';
  static const String _legacyPrefix = 'kslas_secure_attempt_autosave_v1';

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
    final previousPrimary = _storage.read<String>(_primaryKey(attemptId));
    if (previousPrimary != null && previousPrimary.trim().isNotEmpty) {
      await _storage.write(_backupKey(attemptId), previousPrimary);
    }

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
    await _storage.write(_primaryKey(attemptId), jsonEncode(record));
  }

  SecureAttemptAutosaveSnapshot? load(String attemptId) {
    final primary = _decodeSnapshot(
      raw: _storage.read<String>(_primaryKey(attemptId)),
      attemptId: attemptId,
      recoveredFrom: 'primary',
    );
    if (primary != null && primary.checksumValid) return primary;

    final backup = _decodeSnapshot(
      raw: _storage.read<String>(_backupKey(attemptId)),
      attemptId: attemptId,
      recoveredFrom: 'backup',
    );
    if (backup != null && backup.checksumValid) return backup;

    final legacy = _decodeSnapshot(
      raw: _storage.read<String>(_legacyKey(attemptId)),
      attemptId: attemptId,
      recoveredFrom: 'legacy',
    );
    if (legacy != null && legacy.checksumValid) return legacy;

    return primary ?? backup ?? legacy;
  }

  Future<void> clear(String attemptId) async {
    await _storage.remove(_primaryKey(attemptId));
    await _storage.remove(_backupKey(attemptId));
    await _storage.remove(_legacyKey(attemptId));
  }

  SecureAttemptAutosaveSnapshot? _decodeSnapshot({
    required String? raw,
    required String attemptId,
    required String recoveredFrom,
  }) {
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
        recoveredFrom: recoveredFrom,
      );
    } catch (_) {
      return null;
    }
  }

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

  String _primaryKey(String attemptId) => '$_prefix:$attemptId:primary';
  String _backupKey(String attemptId) => '$_prefix:$attemptId:backup';
  String _legacyKey(String attemptId) => '$_legacyPrefix:$attemptId';
}

import 'package:get_storage/get_storage.dart';

/// Remembers that a student used every pre-exam identity try for an exam,
/// so leaving and reopening the setup screen does not grant fresh tries.
/// Only the invigilator (through the school system) releases the lock.
class IdentityAttemptLock {
  IdentityAttemptLock({GetStorage? storage})
    : _storage = storage ?? GetStorage();

  final GetStorage _storage;

  static String _key(String studentId, String examId) =>
      'identity_attempt_lock::$studentId::$examId';

  bool isLocked({required String studentId, required String examId}) =>
      _storage.read<String>(_key(studentId, examId)) != null;

  Future<void> lock({
    required String studentId,
    required String examId,
    required String evidenceRecordId,
  }) => _storage.write(
    _key(studentId, examId),
    '${DateTime.now().toUtc().toIso8601String()}|$evidenceRecordId',
  );

  Future<void> release({required String studentId, required String examId}) =>
      _storage.remove(_key(studentId, examId));
}

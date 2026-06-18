import 'package:get_storage/get_storage.dart';

class DemoFaceIdSnapshot {
  const DemoFaceIdSnapshot({
    required this.studentId,
    required this.requiredSamples,
    required this.capturedSamples,
    required this.lastQualityScore,
    required this.updatedAt,
  });

  final String studentId;
  final int requiredSamples;
  final int capturedSamples;
  final double? lastQualityScore;
  final DateTime? updatedAt;

  bool get isComplete => capturedSamples >= requiredSamples;

  String get statusText {
    if (isComplete) {
      return 'Face ID is active for secure examination startup.';
    }
    final remaining = requiredSamples - capturedSamples;
    return 'Capture $remaining more face sample${remaining == 1 ? '' : 's'} to activate Face ID.';
  }
}

class DemoFaceIdService {
  DemoFaceIdService({GetStorage? storage}) : _storage = storage ?? GetStorage();

  static const int requiredSamples = 3;
  static const String studentId = 'KASU/DEMO/2026/001';
  static const String _capturedKey = 'demo_face_id_captured_samples';
  static const String _qualityKey = 'demo_face_id_last_quality';
  static const String _updatedAtKey = 'demo_face_id_updated_at';

  final GetStorage _storage;

  DemoFaceIdSnapshot load() {
    final captured = (_storage.read<int>(_capturedKey) ?? 0).clamp(
      0,
      requiredSamples,
    );
    final quality = _storage.read<double>(_qualityKey);
    final updatedRaw = _storage.read<String>(_updatedAtKey);
    return DemoFaceIdSnapshot(
      studentId: studentId,
      requiredSamples: requiredSamples,
      capturedSamples: captured,
      lastQualityScore: quality,
      updatedAt: updatedRaw == null ? null : DateTime.tryParse(updatedRaw),
    );
  }

  Future<DemoFaceIdSnapshot> addSample({required double qualityScore}) async {
    final current = load();
    final nextCount = (current.capturedSamples + 1).clamp(0, requiredSamples);
    await _storage.write(_capturedKey, nextCount);
    await _storage.write(_qualityKey, qualityScore.clamp(0.0, 1.0));
    await _storage.write(_updatedAtKey, DateTime.now().toIso8601String());
    return load();
  }

  Future<DemoFaceIdSnapshot> reset() async {
    await _storage.remove(_capturedKey);
    await _storage.remove(_qualityKey);
    await _storage.remove(_updatedAtKey);
    return load();
  }
}

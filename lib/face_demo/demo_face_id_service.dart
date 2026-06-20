import 'package:get_storage/get_storage.dart';

import 'face_identity_enrollment_api.dart';

class DemoFaceIdSnapshot {
  const DemoFaceIdSnapshot({
    required this.studentId,
    required this.requiredSamples,
    required this.capturedSamples,
    required this.lastQualityScore,
    required this.updatedAt,
    required this.backendSynced,
    required this.locked,
    required this.enrollmentId,
    required this.status,
    required this.downloadedImageUrls,
  });

  final String studentId;
  final int requiredSamples;
  final int capturedSamples;
  final double? lastQualityScore;
  final DateTime? updatedAt;
  final bool backendSynced;
  final bool locked;
  final String enrollmentId;
  final String status;
  final List<String> downloadedImageUrls;

  bool get isComplete => backendSynced && locked && capturedSamples >= requiredSamples;

  String get statusText {
    if (isComplete) {
      return 'Face ID is active, protected, and ready for secure exam identity checks.';
    }
    if (backendSynced && !locked) {
      return 'A saved Face ID record exists but is not ready yet. Contact the exam office.';
    }
    final remaining = requiredSamples - capturedSamples;
    return 'Capture $remaining more guided identity image${remaining == 1 ? '' : 's'} to activate Face ID for exam identity checks.';
  }
}

class DemoFaceIdService {
  DemoFaceIdService({GetStorage? storage}) : _storage = storage ?? GetStorage();

  static const int requiredSamples = 6;
  static const String studentId = 'KASU/STU/2026/001';
  static const String _capturedKey = 'demo_face_id_captured_samples';
  static const String _qualityKey = 'demo_face_id_last_quality';
  static const String _updatedAtKey = 'demo_face_id_updated_at';
  static const String _backendSyncedKey = 'demo_face_id_backend_synced';
  static const String _lockedKey = 'demo_face_id_locked';
  static const String _enrollmentIdKey = 'demo_face_id_enrollment_id';
  static const String _statusKey = 'demo_face_id_status';
  static const String _imageUrlsKey = 'demo_face_id_image_urls';

  final GetStorage _storage;

  DemoFaceIdSnapshot load() {
    final captured = (_storage.read<int>(_capturedKey) ?? 0).clamp(
      0,
      requiredSamples,
    );
    final quality = _storage.read<double>(_qualityKey);
    final updatedRaw = _storage.read<String>(_updatedAtKey);
    final imageUrls = (_storage.read<List>(_imageUrlsKey) ?? const [])
        .map((item) => item.toString())
        .where((item) => item.isNotEmpty)
        .toList();
    return DemoFaceIdSnapshot(
      studentId: studentId,
      requiredSamples: requiredSamples,
      capturedSamples: captured,
      lastQualityScore: quality,
      updatedAt: updatedRaw == null ? null : DateTime.tryParse(updatedRaw),
      backendSynced: _storage.read<bool>(_backendSyncedKey) ?? false,
      locked: _storage.read<bool>(_lockedKey) ?? false,
      enrollmentId: _storage.read<String>(_enrollmentIdKey) ?? '',
      status: _storage.read<String>(_statusKey) ?? 'not_enrolled',
      downloadedImageUrls: imageUrls,
    );
  }

  Future<DemoFaceIdSnapshot> addSample({required double qualityScore}) async {
    final current = load();
    if (current.locked) return current;
    final nextCount = (current.capturedSamples + 1).clamp(0, requiredSamples);
    await _storage.write(_capturedKey, nextCount);
    await _storage.write(_qualityKey, qualityScore.clamp(0.0, 1.0));
    await _storage.write(_updatedAtKey, DateTime.now().toIso8601String());
    await _storage.write(_backendSyncedKey, false);
    await _storage.write(_lockedKey, false);
    return load();
  }

  Future<DemoFaceIdSnapshot> applyBackendEnrollment(FaceIdentityEnrollmentResponse response) async {
    await _storage.write(_capturedKey, response.uploadedImages.clamp(0, requiredSamples));
    final bestQuality = response.images.isEmpty
        ? 0.0
        : response.images.map((image) => image.qualityScore).reduce((a, b) => a > b ? a : b);
    await _storage.write(_qualityKey, bestQuality);
    await _storage.write(_updatedAtKey, DateTime.now().toIso8601String());
    await _storage.write(_backendSyncedKey, response.activeLocked);
    await _storage.write(_lockedKey, response.locked);
    await _storage.write(_enrollmentIdKey, response.enrollmentId);
    await _storage.write(_statusKey, response.status);
    await _storage.write(
      _imageUrlsKey,
      response.images.map((image) => image.viewUrl).where((url) => url.isNotEmpty).toList(),
    );
    return load();
  }

  Future<DemoFaceIdSnapshot> resetLocalDraftOnly() async {
    final current = load();
    if (current.locked) return current;
    await _storage.remove(_capturedKey);
    await _storage.remove(_qualityKey);
    await _storage.remove(_updatedAtKey);
    await _storage.remove(_backendSyncedKey);
    await _storage.remove(_lockedKey);
    await _storage.remove(_enrollmentIdKey);
    await _storage.remove(_statusKey);
    await _storage.remove(_imageUrlsKey);
    return load();
  }
}

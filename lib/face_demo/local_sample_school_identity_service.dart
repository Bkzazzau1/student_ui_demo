import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../rust/api/official_face_id.dart';
import 'face_embedding_pipeline.dart';
import 'native_face_embedding_runtime.dart';
import 'official_face_id_models.dart';
import 'protected_local_store.dart';
import 'school_identity_service.dart';

/// Rebuilds one reference embedding from an approved registration photo.
///
/// The school builds the official template from the photos its staff
/// approved, never from embeddings the registration device sent: a modified
/// app could otherwise pair genuine photos with another person's embeddings.
abstract class OfficialTemplateRebuilder {
  Future<RebuiltReference> rebuild(OfficialFaceIdPhoto photo);
}

class RebuiltReference {
  const RebuiltReference.usable(this.embedding, this.quality) : failure = '';

  const RebuiltReference.unusable(this.failure)
    : embedding = const <double>[],
      quality = 0;

  final List<double> embedding;
  final double quality;
  final String failure;

  bool get usable => failure.isEmpty;
}

/// Runs the same on-device face pipeline over the stored photo. In the real
/// school system this runs on the school's servers.
class PipelineTemplateRebuilder implements OfficialTemplateRebuilder {
  PipelineTemplateRebuilder({FaceEmbeddingPipeline? pipeline})
    : _pipeline = pipeline ?? FaceEmbeddingPipeline();

  final FaceEmbeddingPipeline _pipeline;

  @override
  Future<RebuiltReference> rebuild(OfficialFaceIdPhoto photo) async {
    final result = await _pipeline.processEncodedImage(photo.jpegBytes);
    if (result == null) {
      return RebuiltReference.unusable(
        _pipeline.lastFailureReason.isEmpty
            ? 'no reliable face in the photo'
            : _pipeline.lastFailureReason,
      );
    }
    return RebuiltReference.usable(result.embedding, result.quality);
  }
}

class SampleSchoolReviewItem {
  const SampleSchoolReviewItem({
    required this.submissionId,
    required this.studentId,
    required this.submittedAt,
    required this.photoCount,
    required this.replacesApprovedFaceId,
  });

  final String submissionId;
  final String studentId;
  final DateTime submittedAt;
  final int photoCount;
  final bool replacesApprovedFaceId;
}

class SampleSchoolApprovalResult {
  const SampleSchoolApprovalResult._({
    required this.approved,
    required this.message,
    this.templateId,
    this.usablePhotos = 0,
  });

  final bool approved;
  final String message;
  final String? templateId;
  final int usablePhotos;
}

/// A local stand-in for the university's identity system, used for testing
/// until the real system is connected. It keeps the same separation the real
/// system must keep: photos and templates live in "school" storage, staff
/// approve or reject, and only signed templates reach the exam flow.
///
/// Everything it stores is encrypted with [ProtectedLocalStore]. Its signing
/// key is a sample key; production builds must not trust it.
class LocalSampleSchoolIdentityService implements SchoolIdentityService {
  LocalSampleSchoolIdentityService({
    required ProtectedLocalStore store,
    required OfficialTemplateRebuilder rebuilder,
    math.Random? random,
    DateTime Function()? clock,
    this.templateValidity = const Duration(days: 365),
    this.minimumUsablePhotos = 5,
    this.minimumReferenceQuality = 0.65,
    this.deviceAgreementThreshold = 0.90,
  }) : _store = store,
       _rebuilder = rebuilder,
       _random = random ?? math.Random.secure(),
       _clock = clock ?? DateTime.now;

  /// Uses the protected per-app directory on Windows/Android; falls back to
  /// memory (lost on restart) where protected storage is unavailable.
  static Future<LocalSampleSchoolIdentityService> openDefault() async {
    final root = await KslasPrivateDirectory.resolve('sample_school');
    final ProtectedLocalStore store = root == null
        ? InMemoryProtectedLocalStore()
        : NativeProtectedLocalStore(root);
    return LocalSampleSchoolIdentityService(
      store: store,
      rebuilder: PipelineTemplateRebuilder(),
    );
  }

  static const String sampleInstitutionId = 'kslas-sample-school';
  static const String sampleReviewer = 'sample-school-registrar';
  static const String _purpose = 'sample-school';

  final ProtectedLocalStore _store;
  final OfficialTemplateRebuilder _rebuilder;
  final math.Random _random;
  final DateTime Function() _clock;
  final Duration templateValidity;
  final int minimumUsablePhotos;
  final double minimumReferenceQuality;
  final double deviceAgreementThreshold;

  @override
  String get institutionId => sampleInstitutionId;

  @override
  bool get isSample => true;

  @override
  Future<String> trustedTemplateKeysJson() async {
    final key = await _signingKey();
    return jsonEncode(<Map<String, String>>[
      <String, String>{
        'key_id': key.keyId,
        'public_key_hex': key.publicKeyHex,
        'environment': 'sample',
      },
    ]);
  }

  @override
  Future<OfficialFaceIdStatus> fetchStatus(String studentId) async {
    final record = await _studentRecord(studentId);
    return OfficialFaceIdStatus.fromJson(record);
  }

  @override
  Future<String> submitRegistration(OfficialFaceIdSubmission submission) async {
    if (submission.studentId.trim().isEmpty) {
      throw const SchoolIdentityUnavailable('student id is required');
    }
    if (submission.photos.length < minimumUsablePhotos) {
      throw SchoolIdentityUnavailable(
        'at least $minimumUsablePhotos photos are required',
      );
    }
    final submissionId = submission.submissionId.isEmpty
        ? 'sub-${_randomHex(8)}'
        : submission.submissionId;
    if (await _readJson(_submissionPath(submissionId)) != null) {
      throw const SchoolIdentityUnavailable('submission id already exists');
    }
    final record = await _studentRecord(submission.studentId);
    // A student registers once: a waiting or approved registration closes
    // registration until the school rejects it or reopens it.
    if (!OfficialFaceIdStatus.fromJson(record).registrationOpen) {
      throw const SchoolIdentityUnavailable(
        'Face ID registration is closed for this student. Contact the exam '
        'office if your Face ID needs to change.',
      );
    }
    final now = _clock().toUtc();
    await _writeJson(_submissionPath(submissionId), <String, Object?>{
      ...submission.toJson(),
      'submission_id': submissionId,
      'review': <String, Object?>{'status': 'pending'},
    });
    record['pending_submission_id'] = submissionId;
    record['pending_submitted_at'] = now.toIso8601String();
    record.remove('registration_reopened');
    _appendHistory(record, 'submitted', submissionId, now);
    await _writeJson(_studentPath(submission.studentId), record);
    return submissionId;
  }

  @override
  Future<String?> downloadOfficialTemplate(String studentId) async {
    final record = await _studentRecord(studentId);
    final templateId = record['active_template_id']?.toString() ?? '';
    if (templateId.isEmpty) return null;
    return _store.read(_templatePath(studentId), purpose: _purpose);
  }

  @override
  Future<List<String>> uploadIdentityEvidence(
    List<Map<String, Object?>> records,
  ) async {
    final stored = <String>[];
    for (final record in records) {
      final id = record['record_id']?.toString() ?? '';
      if (id.isEmpty || id.contains('/') || id.contains('\\')) continue;
      await _writeJson('evidence/$id.json', record);
      stored.add(id);
    }
    return stored;
  }

  // ---- Sample school administration (testing only) ----------------------

  Future<List<SampleSchoolReviewItem>> pendingReviews() async {
    final items = <SampleSchoolReviewItem>[];
    for (final path in await _store.list('submissions')) {
      final json = await _readJson(path);
      if (json == null) continue;
      final review = Map<String, Object?>.from(
        (json['review'] as Map?) ?? const <String, Object?>{},
      );
      if (review['status'] != 'pending') continue;
      final studentId = json['student_id']?.toString() ?? '';
      final record = await _studentRecord(studentId);
      items.add(
        SampleSchoolReviewItem(
          submissionId: json['submission_id']?.toString() ?? '',
          studentId: studentId,
          submittedAt: DateTime.parse(json['submitted_at']!.toString()),
          photoCount: ((json['photos'] as List?) ?? const []).length,
          replacesApprovedFaceId:
              (record['active_template_id']?.toString() ?? '').isNotEmpty,
        ),
      );
    }
    items.sort((a, b) => a.submittedAt.compareTo(b.submittedAt));
    return items;
  }

  Future<OfficialFaceIdSubmission?> loadSubmission(String submissionId) async {
    final json = await _readJson(_submissionPath(submissionId));
    return json == null ? null : OfficialFaceIdSubmission.fromJson(json);
  }

  /// Approves a pending submission: rebuilds the references from the photos,
  /// checks them against what the device sent, then signs the template.
  Future<SampleSchoolApprovalResult> approve(
    String submissionId, {
    String reviewer = sampleReviewer,
  }) async {
    final json = await _readJson(_submissionPath(submissionId));
    if (json == null) {
      return const SampleSchoolApprovalResult._(
        approved: false,
        message: 'Submission not found.',
      );
    }
    final review = Map<String, Object?>.from(
      (json['review'] as Map?) ?? const <String, Object?>{},
    );
    if (review['status'] != 'pending') {
      return SampleSchoolApprovalResult._(
        approved: false,
        message: 'Submission is ${review['status']}, not pending.',
      );
    }
    final submission = OfficialFaceIdSubmission.fromJson(json);
    final built = await _buildAndStoreTemplate(
      submission,
      reviewer: reviewer,
      checkDeviceAgreement: true,
    );
    if (!built.approved) return built;
    final templateId = built.templateId!;
    final now = _clock().toUtc();

    final record = await _studentRecord(submission.studentId);
    final previous = record['active_submission_id']?.toString() ?? '';
    if (previous.isNotEmpty && previous != submissionId) {
      await _setReview(previous, 'superseded', 'replaced by $submissionId');
    }
    record['active_template_id'] = templateId;
    record['active_submission_id'] = submissionId;
    record['active_approved_at'] = now.toIso8601String();
    if (record['pending_submission_id'] == submissionId) {
      record.remove('pending_submission_id');
      record.remove('pending_submitted_at');
    }
    record.remove('last_rejection_reason');
    record.remove('last_rejected_at');
    _appendHistory(record, 'approved', submissionId, now, by: reviewer);
    await _writeJson(_studentPath(submission.studentId), record);
    await _setReview(submissionId, 'approved', '', reviewer: reviewer);
    return built;
  }

  /// Model-upgrade path: rebuilds every active template from its stored,
  /// already-approved photos with the face model and preprocessing this
  /// build uses. Students do not register again. Returns how many templates
  /// were rebuilt.
  Future<int> rebuildActiveTemplates({
    String reviewer = 'sample-school-model-upgrade',
  }) async {
    var rebuilt = 0;
    for (final path in await _store.list('students')) {
      final record = await _readJson(path);
      final submissionId = record?['active_submission_id']?.toString() ?? '';
      if (record == null || submissionId.isEmpty) continue;
      final json = await _readJson(_submissionPath(submissionId));
      if (json == null) continue;
      final submission = OfficialFaceIdSubmission.fromJson(json);
      final built = await _buildAndStoreTemplate(
        submission,
        reviewer: reviewer,
        // The device embeddings were made with the previous model or
        // preprocessing, so they cannot be compared; the photos were
        // approved by staff when they were submitted.
        checkDeviceAgreement: false,
      );
      if (!built.approved) continue;
      final now = _clock().toUtc();
      record['active_template_id'] = built.templateId;
      _appendHistory(
        record,
        'rebuilt_for_model',
        submissionId,
        now,
        by: reviewer,
      );
      await _writeJson(path, record);
      rebuilt++;
    }
    return rebuilt;
  }

  /// Rebuilds references from the photos with the current pipeline, signs
  /// the template, and stores it as the student's active template.
  Future<SampleSchoolApprovalResult> _buildAndStoreTemplate(
    OfficialFaceIdSubmission submission, {
    required String reviewer,
    required bool checkDeviceAgreement,
  }) async {
    final sameModel =
        submission.modelId == OfficialFaceIdModel.modelId &&
        submission.modelSha256 == OfficialFaceIdModel.modelSha256 &&
        submission.preprocessingVersion ==
            OfficialFaceIdModel.preprocessingVersion;
    final references = <List<double>>[];
    final labels = <String>[];
    var qualityTotal = 0.0;
    for (final photo in submission.photos) {
      final rebuilt = await _rebuilder.rebuild(photo);
      if (!rebuilt.usable || rebuilt.quality < minimumReferenceQuality) {
        continue;
      }
      if (checkDeviceAgreement &&
          sameModel &&
          photo.deviceEmbedding.isNotEmpty &&
          _cosine(photo.deviceEmbedding, rebuilt.embedding) <
              deviceAgreementThreshold) {
        return SampleSchoolApprovalResult._(
          approved: false,
          message:
              'The "${photo.title}" photo does not match the data the device '
              'sent. Reject this submission and ask the student to register '
              'again.',
        );
      }
      references.add(rebuilt.embedding);
      labels.add(photo.poseCode);
      qualityTotal += rebuilt.quality;
    }
    if (references.length < minimumUsablePhotos) {
      return SampleSchoolApprovalResult._(
        approved: false,
        usablePhotos: references.length,
        message:
            'Only ${references.length} of ${submission.photos.length} photos '
            'are clear enough (need $minimumUsablePhotos). Reject and ask for '
            'new photos.',
      );
    }

    final now = _clock().toUtc();
    final templateId = 'tpl-${_randomHex(8)}';
    final key = await _signingKey();
    final envelope = issueSampleSchoolOfficialTemplate(
      request: OfficialTemplateIssueRequest(
        templateId: templateId,
        institutionId: institutionId,
        studentId: submission.studentId,
        submissionId: submission.submissionId,
        modelId: OfficialFaceIdModel.modelId,
        modelSha256: OfficialFaceIdModel.modelSha256,
        preprocessingVersion: OfficialFaceIdModel.preprocessingVersion,
        references: references
            .map((reference) => Float32List.fromList(reference))
            .toList(growable: false),
        referenceLabels: labels,
        qualityScore: qualityTotal / references.length,
        buildSource: 'rebuilt_from_approved_photos',
        approvedBy: reviewer,
        approvedAtMs: now.millisecondsSinceEpoch,
        issuedAtMs: now.millisecondsSinceEpoch,
        expiresAtMs: now.add(templateValidity).millisecondsSinceEpoch,
      ),
      signingSeedHex: key.seedHex,
      keyId: key.keyId,
    );
    if (!await _store.write(
      _templatePath(submission.studentId),
      envelope,
      purpose: _purpose,
    )) {
      return const SampleSchoolApprovalResult._(
        approved: false,
        message: 'The approved template could not be stored securely.',
      );
    }
    return SampleSchoolApprovalResult._(
      approved: true,
      templateId: templateId,
      usablePhotos: references.length,
      message:
          'Approved. Official template built from ${references.length} photos.',
    );
  }

  /// Staff action: lets a student register again (for example their
  /// appearance changed). An approved Face ID stays in use until the new
  /// registration is approved.
  Future<bool> reopenRegistration(
    String studentId, {
    required String reason,
    String reviewer = sampleReviewer,
  }) async {
    final record = await _studentRecord(studentId);
    final status = OfficialFaceIdStatus.fromJson(record);
    if (status.hasPendingSubmission || status.registrationOpen) return false;
    final now = _clock().toUtc();
    record['registration_reopened'] = true;
    _appendHistory(
      record,
      'registration_reopened',
      '',
      now,
      by: reviewer,
      reason: reason.trim().isEmpty ? 'reopened by staff' : reason.trim(),
    );
    await _writeJson(_studentPath(studentId), record);
    return true;
  }

  Future<bool> reject(
    String submissionId, {
    required String reason,
    String reviewer = sampleReviewer,
  }) async {
    final json = await _readJson(_submissionPath(submissionId));
    if (json == null) return false;
    final review = Map<String, Object?>.from(
      (json['review'] as Map?) ?? const <String, Object?>{},
    );
    if (review['status'] != 'pending') return false;
    final studentId = json['student_id']?.toString() ?? '';
    final now = _clock().toUtc();
    final record = await _studentRecord(studentId);
    if (record['pending_submission_id'] == submissionId) {
      record.remove('pending_submission_id');
      record.remove('pending_submitted_at');
    }
    final cleanReason = reason.trim().isEmpty
        ? 'The photos could not be approved.'
        : reason.trim();
    record['last_rejection_reason'] = cleanReason;
    record['last_rejected_at'] = now.toIso8601String();
    _appendHistory(
      record,
      'rejected',
      submissionId,
      now,
      by: reviewer,
      reason: cleanReason,
    );
    await _writeJson(_studentPath(studentId), record);
    await _setReview(submissionId, 'rejected', cleanReason, reviewer: reviewer);
    return true;
  }

  Future<List<Map<String, Object?>>> storedEvidence() async {
    final records = <Map<String, Object?>>[];
    for (final path in await _store.list('evidence')) {
      final json = await _readJson(path);
      if (json != null) records.add(json);
    }
    return records;
  }

  // ---- storage helpers ----------------------------------------------------

  Future<Map<String, Object?>> _studentRecord(String studentId) async =>
      await _readJson(_studentPath(studentId)) ??
      <String, Object?>{'student_id': studentId, 'history': <Object?>[]};

  void _appendHistory(
    Map<String, Object?> record,
    String event,
    String submissionId,
    DateTime at, {
    String? by,
    String? reason,
  }) {
    final history = List<Object?>.from(
      (record['history'] as List?) ?? const [],
    );
    history.add(<String, Object?>{
      'event': event,
      'submission_id': submissionId,
      'at': at.toIso8601String(),
      if (by != null) 'by': by,
      if (reason != null) 'reason': reason,
    });
    record['history'] = history;
  }

  Future<void> _setReview(
    String submissionId,
    String status,
    String reason, {
    String? reviewer,
  }) async {
    final json = await _readJson(_submissionPath(submissionId));
    if (json == null) return;
    json['review'] = <String, Object?>{
      'status': status,
      'reason': reason,
      'reviewed_at': _clock().toUtc().toIso8601String(),
      if (reviewer != null) 'reviewed_by': reviewer,
    };
    await _writeJson(_submissionPath(submissionId), json);
  }

  Future<_SampleSigningKey> _signingKey() async {
    var seed = await _store.read('keys/signing_seed', purpose: _purpose);
    if (seed == null || seed.length != 64) {
      seed = _randomHex(32);
      if (!await _store.write('keys/signing_seed', seed, purpose: _purpose)) {
        throw const SchoolIdentityUnavailable(
          'sample school signing key could not be stored',
        );
      }
    }
    final publicKey = sampleSchoolPublicKeyHex(signingSeedHex: seed);
    return _SampleSigningKey(
      seedHex: seed,
      publicKeyHex: publicKey,
      keyId: 'sample-school-${publicKey.substring(0, 12)}',
    );
  }

  Future<Map<String, Object?>?> _readJson(String path) async {
    final text = await _store.read(path, purpose: _purpose);
    if (text == null || text.isEmpty) return null;
    final decoded = jsonDecode(text);
    return decoded is Map ? Map<String, Object?>.from(decoded) : null;
  }

  Future<void> _writeJson(String path, Map<String, Object?> json) async {
    if (!await _store.write(path, jsonEncode(json), purpose: _purpose)) {
      throw SchoolIdentityUnavailable('could not store $path');
    }
  }

  String _studentPath(String studentId) =>
      'students/${_studentKey(studentId)}.json';

  String _templatePath(String studentId) =>
      'templates/${_studentKey(studentId)}.json';

  String _submissionPath(String submissionId) {
    if (!RegExp(r'^[A-Za-z0-9._-]+$').hasMatch(submissionId)) {
      throw ArgumentError.value(submissionId, 'submissionId', 'is not safe');
    }
    return 'submissions/$submissionId.json';
  }

  static String _studentKey(String studentId) =>
      sha256.convert(utf8.encode(studentId)).toString();

  String _randomHex(int bytes) => List<String>.generate(
    bytes,
    (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();

  static double _cosine(List<double> a, List<double> b) {
    if (a.length != b.length || a.isEmpty) return -1;
    var dot = 0.0;
    var left = 0.0;
    var right = 0.0;
    for (var index = 0; index < a.length; index++) {
      dot += a[index] * b[index];
      left += a[index] * a[index];
      right += b[index] * b[index];
    }
    if (left <= 0 || right <= 0) return -1;
    return dot / (math.sqrt(left) * math.sqrt(right));
  }
}

class _SampleSigningKey {
  const _SampleSigningKey({
    required this.seedHex,
    required this.publicKeyHex,
    required this.keyId,
  });

  final String seedHex;
  final String publicKeyHex;
  final String keyId;
}

/// Model identity the device stamps into a registration submission.
abstract final class OfficialFaceIdModel {
  static String get modelId => NativeFaceEmbeddingRuntime.modelId;
  static String get modelSha256 => NativeFaceEmbeddingRuntime.modelSha256;
  static String get preprocessingVersion =>
      NativeFaceEmbeddingRuntime.preprocessingVersion;
}

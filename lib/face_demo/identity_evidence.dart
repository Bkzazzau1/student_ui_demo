import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../rust/api/liveness_challenge.dart';
import 'face_identity_verification_service.dart';
import 'native_face_embedding_runtime.dart';
import 'protected_local_store.dart';
import 'school_identity_service.dart';

/// Why an identity check ran. Stable wire names go into evidence.
enum IdentityCheckKind {
  preExam('pre_exam'),
  inExamRandom('in_exam_random'),
  inExamFollowUp('in_exam_follow_up'),
  pauseRecheck('pause_recheck');

  const IdentityCheckKind(this.wireName);

  final String wireName;
}

/// One identity check result, before it is sealed.
class IdentityEvidenceDraft {
  const IdentityEvidenceDraft({
    required this.kind,
    required this.studentId,
    required this.outcome,
    required this.samplesAttempted,
    this.examId = '',
    this.attemptId = '',
    this.template,
    this.liveness,
    this.boundIdentityFrames = 0,
    this.reviewPhotoJpeg,
    this.policy = const <String, Object?>{},
  });

  final IdentityCheckKind kind;
  final String studentId;
  final String examId;
  final String attemptId;
  final FaceIdentityCheckOutcome outcome;
  final int samplesAttempted;
  final OfficialFaceTemplateContext? template;
  final LivenessChallengeResult? liveness;

  /// How many identity samples came from the same frames that proved
  /// liveness (see `FaceIdentityLivenessGate.runBoundBurst`).
  final int boundIdentityFrames;

  /// Only kept for a reliable "no" (mismatch or liveness failure), so an
  /// invigilator can review it. Never kept for a pass.
  final Uint8List? reviewPhotoJpeg;
  final Map<String, Object?> policy;
}

/// Seals identity results on the device and uploads them to the school.
///
/// The device decides (edge AI); the school receives the decision and its
/// context as evidence. Each record is hashed over sorted-key JSON and
/// chained to the previous record of the same student and attempt, so a
/// deleted or edited record breaks the chain the school can verify.
class IdentityEvidenceOutbox {
  IdentityEvidenceOutbox({
    required ProtectedLocalStore store,
    required this.institutionId,
    this.deviceClass = '',
    math.Random? random,
    DateTime Function()? clock,
    this.reviewPhotoRetention = const Duration(days: 30),
  }) : _store = store,
       _random = random ?? math.Random.secure(),
       _clock = clock ?? DateTime.now;

  static Future<IdentityEvidenceOutbox> openDefault({
    required String institutionId,
    String deviceClass = '',
  }) async {
    final root = await KslasPrivateDirectory.resolve('identity_evidence');
    return IdentityEvidenceOutbox(
      store: root == null
          ? InMemoryProtectedLocalStore()
          : NativeProtectedLocalStore(root),
      institutionId: institutionId,
      deviceClass: deviceClass,
    );
  }

  static const String schema = 'kslas.identity_evidence.v1';
  static const String _purpose = 'identity-evidence';
  static const String _photoField = 'review_photo_jpeg_b64';

  final ProtectedLocalStore _store;
  final math.Random _random;
  final DateTime Function() _clock;
  final String institutionId;
  final String deviceClass;
  final Duration reviewPhotoRetention;

  /// Seals and stores [draft]; returns the sealed record (including the
  /// review photo when one was kept).
  Future<Map<String, Object?>> record(IdentityEvidenceDraft draft) async {
    final now = _clock().toUtc();
    final chainPath =
        'chains/${_chainKey(draft.studentId, draft.attemptId)}.json';
    final head = await _readJson(chainPath);
    final previous = head?['record_sha256']?.toString() ?? '';
    final photo = draft.outcome.countsAsFailure ? draft.reviewPhotoJpeg : null;
    final template = draft.template;
    final liveness = draft.liveness;
    final record = <String, Object?>{
      'schema': schema,
      'record_id': 'idev-${now.millisecondsSinceEpoch}-${_randomHex(6)}',
      'created_at': now.toIso8601String(),
      'institution_id': institutionId,
      'student_id': draft.studentId,
      'exam_id': draft.examId,
      'attempt_id': draft.attemptId,
      'check_kind': draft.kind.wireName,
      'decision': draft.outcome.state.wireName,
      'reason': draft.outcome.reason,
      'similarity': _round(draft.outcome.similarity),
      'centroid_similarity': _round(draft.outcome.centroidSimilarity),
      'threshold': _round(draft.outcome.threshold),
      'matched_samples': draft.outcome.matchedSamples,
      'reliable_samples': draft.outcome.reliableSamples,
      'samples_attempted': draft.samplesAttempted,
      'liveness': liveness == null
          ? null
          : <String, Object?>{
              'challenge': liveness.challenge,
              'state': liveness.state,
              'spoof_risk_score': _round(liveness.spoofRiskScore),
              'usable_observations': liveness.usableObservations,
              'bound_identity_frames': draft.boundIdentityFrames,
            },
      'template': template == null
          ? null
          : <String, Object?>{
              'template_id': template.templateId,
              'envelope_sha256': template.envelopeSha256,
              'key_id': template.status.keyId,
              'key_environment': template.status.keyEnvironment,
            },
      'model': <String, Object?>{
        'model_id': NativeFaceEmbeddingRuntime.modelId,
        'model_sha256': NativeFaceEmbeddingRuntime.modelSha256,
        'preprocessing_version':
            NativeFaceEmbeddingRuntime.preprocessingVersion,
      },
      'device': <String, Object?>{
        'platform': Platform.operatingSystem,
        'device_class': deviceClass,
      },
      'policy': draft.policy,
      'review_photo_sha256': photo == null
          ? null
          : sha256.convert(photo).toString(),
      'previous_record_sha256': previous,
    };
    record['record_sha256'] = sealOf(record);
    final stored = <String, Object?>{
      ...record,
      if (photo != null) _photoField: base64Encode(photo),
    };
    final id = record['record_id']! as String;
    await _writeJson('outbox/$id.json', stored);
    await _writeJson(chainPath, <String, Object?>{
      'record_id': id,
      'record_sha256': record['record_sha256'],
    });
    return stored;
  }

  /// Records waiting to be uploaded, oldest first.
  Future<List<Map<String, Object?>>> pending() async {
    final records = <Map<String, Object?>>[];
    for (final path in await _store.list('outbox')) {
      final json = await _readJson(path);
      if (json != null) records.add(json);
    }
    records.sort(
      (a, b) => (a['created_at']?.toString() ?? '').compareTo(
        b['created_at']?.toString() ?? '',
      ),
    );
    return records;
  }

  /// Uploads pending records. Returns how many the school accepted. Records
  /// the school did not accept stay queued; a network failure is not an
  /// error for the exam.
  Future<int> flush(SchoolIdentityService school) async {
    await purgeExpiredReviewPhotos();
    final records = await pending();
    if (records.isEmpty) return 0;
    final List<String> accepted;
    try {
      accepted = await school.uploadIdentityEvidence(records);
    } catch (_) {
      return 0;
    }
    for (final id in accepted) {
      final record = records.firstWhere(
        (item) => item['record_id'] == id,
        orElse: () => const <String, Object?>{},
      );
      if (record.isEmpty) continue;
      await _writeJson('sent/$id.json', <String, Object?>{
        'record_id': id,
        'record_sha256': record['record_sha256'],
        'uploaded_at': _clock().toUtc().toIso8601String(),
      });
      await _store.delete('outbox/$id.json');
    }
    return accepted.length;
  }

  /// Drops review photos older than [reviewPhotoRetention] from records that
  /// are still queued. The photo hash stays, so the seal stays valid.
  Future<int> purgeExpiredReviewPhotos() async {
    final cutoff = _clock().toUtc().subtract(reviewPhotoRetention);
    var purged = 0;
    for (final path in await _store.list('outbox')) {
      final json = await _readJson(path);
      if (json == null || !json.containsKey(_photoField)) continue;
      final created = DateTime.tryParse(json['created_at']?.toString() ?? '');
      if (created == null || created.isAfter(cutoff)) continue;
      json.remove(_photoField);
      json['review_photo_purged_at'] = _clock().toUtc().toIso8601String();
      await _writeJson(path, json);
      purged++;
    }
    return purged;
  }

  /// SHA-256 over sorted-key JSON of [record], excluding the seal itself and
  /// any photo bytes or purge marker (the photo is covered by its hash).
  static String sealOf(Map<String, Object?> record) {
    final unsealed = Map<String, Object?>.from(record)
      ..remove('record_sha256')
      ..remove(_photoField)
      ..remove('review_photo_purged_at');
    return sha256.convert(utf8.encode(canonicalJson(unsealed))).toString();
  }

  static bool verifySeal(Map<String, Object?> record) =>
      record['record_sha256'] == sealOf(record);

  static String canonicalJson(Object? value) {
    if (value is Map) {
      final keys = value.keys.map((key) => key.toString()).toList()..sort();
      return '{${keys.map((key) => '${jsonEncode(key)}:${canonicalJson(value[key])}').join(',')}}';
    }
    if (value is List) return '[${value.map(canonicalJson).join(',')}]';
    return jsonEncode(value);
  }

  static double _round(double value) =>
      value.isFinite ? (value * 10000).roundToDouble() / 10000 : 0;

  static String _chainKey(String studentId, String attemptId) =>
      sha256.convert(utf8.encode('$studentId|$attemptId')).toString();

  String _randomHex(int bytes) => List<String>.generate(
    bytes,
    (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();

  Future<Map<String, Object?>?> _readJson(String path) async {
    final text = await _store.read(path, purpose: _purpose);
    if (text == null || text.isEmpty) return null;
    final decoded = jsonDecode(text);
    return decoded is Map ? Map<String, Object?>.from(decoded) : null;
  }

  Future<void> _writeJson(String path, Map<String, Object?> json) async {
    if (!await _store.write(path, jsonEncode(json), purpose: _purpose)) {
      throw StateError('identity evidence could not be stored securely');
    }
  }
}

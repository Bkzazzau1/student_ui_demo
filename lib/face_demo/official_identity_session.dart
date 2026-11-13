import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import 'face_identity_verification_service.dart';
import 'identity_evidence.dart';
import 'local_sample_school_identity_service.dart';
import 'official_face_id_models.dart';
import 'protected_local_store.dart';
import 'school_identity_service.dart';

/// Which template signers this build accepts.
abstract final class IdentityTrustPolicy {
  /// Keys of the real school system, pinned into the app at build time.
  /// Empty until the university system is connected.
  static const String productionTrustedKeysJson = '[]';

  /// The local sample school is for testing. Release builds only accept it
  /// when built with `--dart-define=KSLAS_ALLOW_SAMPLE_SCHOOL=true`, and a
  /// production release must not set that flag.
  static bool get allowSampleSchool =>
      !kReleaseMode || const bool.fromEnvironment('KSLAS_ALLOW_SAMPLE_SCHOOL');

  static Future<String> trustedKeysJson(SchoolIdentityService school) async {
    final keys = <Object?>[
      ...(jsonDecode(productionTrustedKeysJson) as List),
      if (school.isSample && allowSampleSchool)
        ...(jsonDecode(await school.trustedTemplateKeysJson()) as List),
    ];
    return jsonEncode(keys);
  }
}

/// Single place the app gets its school connection and evidence outbox from.
class SchoolIdentityServices {
  SchoolIdentityServices._();

  static SchoolIdentityServices instance = SchoolIdentityServices._();

  Future<SchoolIdentityService>? _school;
  Future<IdentityEvidenceOutbox>? _outbox;

  Future<SchoolIdentityService> school() => _school ??= _openSchool();

  Future<IdentityEvidenceOutbox> outbox() => _outbox ??= () async {
    final school = await this.school();
    return IdentityEvidenceOutbox.openDefault(
      institutionId: school.institutionId,
    );
  }();

  /// The local sample school, when that is the configured school.
  Future<LocalSampleSchoolIdentityService?> sampleSchool() async {
    final school = await this.school();
    return school is LocalSampleSchoolIdentityService ? school : null;
  }

  @visibleForTesting
  void override({
    required SchoolIdentityService school,
    required IdentityEvidenceOutbox outbox,
  }) {
    _school = Future<SchoolIdentityService>.value(school);
    _outbox = Future<IdentityEvidenceOutbox>.value(outbox);
  }

  Future<SchoolIdentityService> _openSchool() async {
    if (!IdentityTrustPolicy.allowSampleSchool) {
      throw const SchoolIdentityUnavailable(
        'No school identity system is configured for this build.',
      );
    }
    return LocalSampleSchoolIdentityService.openDefault();
  }
}

enum OfficialIdentityProblem {
  none,
  notSubmitted,
  pendingApproval,
  rejected,
  schoolUnavailable,
  templateInvalid,
}

class OfficialIdentityLoadResult {
  const OfficialIdentityLoadResult({
    required this.problem,
    required this.message,
    this.status,
    this.context,
  });

  final OfficialIdentityProblem problem;
  final String message;
  final OfficialFaceIdStatus? status;
  final OfficialFaceTemplateContext? context;

  bool get ready => context != null && problem == OfficialIdentityProblem.none;
}

/// Loads the logged-in student's official template for an exam on THIS
/// device: download from the school, verify the signature and binding
/// locally, keep it in memory for the in-exam checks, and keep an encrypted
/// copy so a restarted attempt can continue without a download.
class OfficialIdentitySession {
  OfficialIdentitySession({
    SchoolIdentityServices? services,
    ProtectedLocalStore? cache,
  }) : _services = services ?? SchoolIdentityServices.instance,
       _cacheOverride = cache;

  static OfficialIdentitySession instance = OfficialIdentitySession();

  static const String _purpose = 'official-template-cache';

  final SchoolIdentityServices _services;
  final ProtectedLocalStore? _cacheOverride;
  Future<ProtectedLocalStore>? _cache;
  OfficialFaceTemplateContext? _active;

  OfficialFaceTemplateContext? get active => _active;

  /// The active template if it belongs to [studentId] and still verifies.
  OfficialFaceTemplateContext? activeFor(String studentId) {
    final active = _active;
    if (active == null || active.studentId != studentId) return null;
    final status = OfficialFaceTemplateContext.verify(
      studentId: studentId,
      envelopeJson: active.envelopeJson,
      trustedKeysJson: active.trustedKeysJson,
    );
    return status.valid ? active : null;
  }

  Future<OfficialIdentityLoadResult> loadForExam(String studentId) async {
    final SchoolIdentityService school;
    final OfficialFaceIdStatus status;
    try {
      school = await _services.school();
      status = await school.fetchStatus(studentId);
    } catch (error) {
      final cached = await restoreCached(studentId);
      if (cached != null) {
        return OfficialIdentityLoadResult(
          problem: OfficialIdentityProblem.none,
          message: 'Using your approved Face ID saved on this device.',
          context: cached,
        );
      }
      return OfficialIdentityLoadResult(
        problem: OfficialIdentityProblem.schoolUnavailable,
        message:
            'Could not reach the school to get your official Face ID. Check '
            'your internet connection and try again.',
      );
    }
    switch (status.state) {
      case OfficialFaceIdState.notSubmitted:
        return OfficialIdentityLoadResult(
          problem: OfficialIdentityProblem.notSubmitted,
          status: status,
          message:
              'You have not registered your Face ID yet. Register it so the '
              'school can approve it before your exam.',
        );
      case OfficialFaceIdState.pendingApproval:
        return OfficialIdentityLoadResult(
          problem: OfficialIdentityProblem.pendingApproval,
          status: status,
          message:
              'Your Face ID is waiting for school approval. You can write '
              'exams once it is approved.',
        );
      case OfficialFaceIdState.rejected:
        return OfficialIdentityLoadResult(
          problem: OfficialIdentityProblem.rejected,
          status: status,
          message:
              'Your Face ID was not approved: ${status.lastRejectionReason}. '
              'Please register it again.',
        );
      case OfficialFaceIdState.approved:
        break;
    }
    try {
      final envelope = await school.downloadOfficialTemplate(studentId);
      final keys = await IdentityTrustPolicy.trustedKeysJson(school);
      if (envelope == null || envelope.isEmpty) {
        return OfficialIdentityLoadResult(
          problem: OfficialIdentityProblem.templateInvalid,
          status: status,
          message:
              'Your approved Face ID could not be downloaded. Please contact '
              'the exam office.',
        );
      }
      final verified = OfficialFaceTemplateContext.verify(
        studentId: studentId,
        envelopeJson: envelope,
        trustedKeysJson: keys,
      );
      if (!verified.valid) {
        return OfficialIdentityLoadResult(
          problem: OfficialIdentityProblem.templateInvalid,
          status: status,
          message:
              'Your official Face ID could not be checked on this device '
              '(${verified.reason}). Please contact the exam office.',
        );
      }
      final context = OfficialFaceTemplateContext(
        studentId: studentId,
        envelopeJson: envelope,
        trustedKeysJson: keys,
        status: verified,
      );
      _active = context;
      await _writeCache(context);
      return OfficialIdentityLoadResult(
        problem: OfficialIdentityProblem.none,
        status: status,
        context: context,
        message: 'Official Face ID ready.',
      );
    } catch (_) {
      return OfficialIdentityLoadResult(
        problem: OfficialIdentityProblem.schoolUnavailable,
        status: status,
        message:
            'Could not download your official Face ID. Check your internet '
            'connection and try again.',
      );
    }
  }

  /// Re-opens the encrypted on-device copy, if it still verifies.
  Future<OfficialFaceTemplateContext?> restoreCached(String studentId) async {
    final store = await _cacheStore();
    final text = await store.read(_cachePath(studentId), purpose: _purpose);
    if (text == null || text.isEmpty) return null;
    final json = jsonDecode(text);
    if (json is! Map) return null;
    final envelope = json['envelope']?.toString() ?? '';
    final keys = json['trusted_keys']?.toString() ?? '[]';
    final verified = OfficialFaceTemplateContext.verify(
      studentId: studentId,
      envelopeJson: envelope,
      trustedKeysJson: keys,
    );
    if (!verified.valid) return null;
    final context = OfficialFaceTemplateContext(
      studentId: studentId,
      envelopeJson: envelope,
      trustedKeysJson: keys,
      status: verified,
    );
    _active = context;
    return context;
  }

  void clearActive() => _active = null;

  Future<void> _writeCache(OfficialFaceTemplateContext context) async {
    final store = await _cacheStore();
    await store.write(
      _cachePath(context.studentId),
      jsonEncode(<String, Object?>{
        'envelope': context.envelopeJson,
        'trusted_keys': context.trustedKeysJson,
        'cached_at': DateTime.now().toUtc().toIso8601String(),
      }),
      purpose: _purpose,
    );
  }

  Future<ProtectedLocalStore> _cacheStore() => _cache ??= () async {
    final override = _cacheOverride;
    if (override != null) return override;
    final root = await KslasPrivateDirectory.resolve('identity');
    return root == null
        ? InMemoryProtectedLocalStore()
        : NativeProtectedLocalStore(root);
  }();

  static String _cachePath(String studentId) =>
      'official/${sha256.convert(utf8.encode(studentId))}.json';
}

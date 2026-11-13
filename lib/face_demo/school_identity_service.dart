import 'official_face_id_models.dart';

/// The school system that owns official Face IDs.
///
/// The app is edge AI: it never sends live exam faces to the school for
/// matching. It talks to the school only to
///
/// 1. submit registration photos for staff approval,
/// 2. read the student's Face ID status,
/// 3. download the signed official template for on-device 1:1 matching, and
/// 4. upload identity check results as evidence.
///
/// [LocalSampleSchoolIdentityService] implements this on the device for
/// testing until the university's system is connected.
abstract class SchoolIdentityService {
  /// Identifies the school that signs templates (recorded in evidence).
  String get institutionId;

  /// Whether this is the local testing stand-in rather than the real school.
  bool get isSample;

  /// JSON list of `{key_id, public_key_hex, environment}` the device accepts
  /// as signers of official templates.
  Future<String> trustedTemplateKeysJson();

  Future<OfficialFaceIdStatus> fetchStatus(String studentId);

  /// Sends a registration for staff review and returns the submission id. A
  /// newer submission replaces an older one that is still waiting for
  /// review; an approved Face ID stays active until a replacement is approved.
  Future<String> submitRegistration(OfficialFaceIdSubmission submission);

  /// The signed official template (envelope JSON) for an approved student,
  /// or null when the student has no approved Face ID.
  Future<String?> downloadOfficialTemplate(String studentId);

  /// Accepts sealed identity evidence records (see `IdentityEvidenceOutbox`).
  /// Returns the ids the school stored.
  Future<List<String>> uploadIdentityEvidence(
    List<Map<String, Object?>> records,
  );
}

/// Thrown when the school cannot be reached or refuses a request. Callers
/// treat it as "try again", never as an identity decision.
class SchoolIdentityUnavailable implements Exception {
  const SchoolIdentityUnavailable(this.message);

  final String message;

  @override
  String toString() => 'SchoolIdentityUnavailable: $message';
}

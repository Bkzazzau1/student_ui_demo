import 'dart:convert';
import 'dart:typed_data';

/// Where a student's official Face ID stands in the school's records.
///
/// "Official" means approved by school staff. Only an approved Face ID can be
/// used to open an exam; a pending or rejected submission never can.
enum OfficialFaceIdState { notSubmitted, pendingApproval, approved, rejected }

/// One guided registration photo, as captured on the student's device.
class OfficialFaceIdPhoto {
  const OfficialFaceIdPhoto({
    required this.poseCode,
    required this.title,
    required this.jpegBytes,
    required this.qualityScore,
    required this.deviceEmbedding,
  });

  factory OfficialFaceIdPhoto.fromJson(Map<String, Object?> json) =>
      OfficialFaceIdPhoto(
        poseCode: json['pose_code']?.toString() ?? '',
        title: json['title']?.toString() ?? '',
        jpegBytes: base64Decode(json['jpeg_b64']?.toString() ?? ''),
        qualityScore: (json['quality_score'] as num?)?.toDouble() ?? 0,
        deviceEmbedding: ((json['device_embedding'] as List?) ?? const [])
            .map((value) => (value as num).toDouble())
            .toList(growable: false),
      );

  final String poseCode;
  final String title;
  final Uint8List jpegBytes;
  final double qualityScore;

  /// The embedding the registration device computed. The school does not
  /// trust it to build the official template (it rebuilds from the photo);
  /// it is used to detect a submission whose photos and embeddings disagree.
  final List<double> deviceEmbedding;

  Map<String, Object?> toJson() => <String, Object?>{
    'pose_code': poseCode,
    'title': title,
    'jpeg_b64': base64Encode(jpegBytes),
    'quality_score': qualityScore,
    'device_embedding': deviceEmbedding,
  };
}

/// Everything a student sends to the school when registering a Face ID.
class OfficialFaceIdSubmission {
  const OfficialFaceIdSubmission({
    required this.submissionId,
    required this.studentId,
    required this.submittedAt,
    required this.consentVersion,
    required this.consentAcceptedAt,
    required this.modelId,
    required this.modelSha256,
    required this.preprocessingVersion,
    required this.capturePlatform,
    required this.captureDeviceClass,
    required this.poseOrder,
    required this.photos,
  });

  factory OfficialFaceIdSubmission.fromJson(
    Map<String, Object?> json,
  ) => OfficialFaceIdSubmission(
    submissionId: json['submission_id']?.toString() ?? '',
    studentId: json['student_id']?.toString() ?? '',
    submittedAt: DateTime.parse(json['submitted_at']!.toString()),
    consentVersion: json['consent_version']?.toString() ?? '',
    consentAcceptedAt: DateTime.parse(json['consent_accepted_at']!.toString()),
    modelId: json['model_id']?.toString() ?? '',
    modelSha256: json['model_sha256']?.toString() ?? '',
    preprocessingVersion: json['preprocessing_version']?.toString() ?? '',
    capturePlatform: json['capture_platform']?.toString() ?? '',
    captureDeviceClass: json['capture_device_class']?.toString() ?? '',
    poseOrder: ((json['pose_order'] as List?) ?? const [])
        .map((value) => value.toString())
        .toList(growable: false),
    photos: ((json['photos'] as List?) ?? const [])
        .whereType<Map>()
        .map(
          (photo) =>
              OfficialFaceIdPhoto.fromJson(Map<String, Object?>.from(photo)),
        )
        .toList(growable: false),
  );

  final String submissionId;
  final String studentId;
  final DateTime submittedAt;
  final String consentVersion;
  final DateTime consentAcceptedAt;
  final String modelId;
  final String modelSha256;
  final String preprocessingVersion;
  final String capturePlatform;
  final String captureDeviceClass;

  /// The randomized order the poses were requested in. A fixed order would
  /// let a pre-recorded video play the poses back on cue.
  final List<String> poseOrder;
  final List<OfficialFaceIdPhoto> photos;

  Map<String, Object?> toJson() => <String, Object?>{
    'schema': 'kslas.official_face_id_submission.v1',
    'submission_id': submissionId,
    'student_id': studentId,
    'submitted_at': submittedAt.toUtc().toIso8601String(),
    'consent_version': consentVersion,
    'consent_accepted_at': consentAcceptedAt.toUtc().toIso8601String(),
    'model_id': modelId,
    'model_sha256': modelSha256,
    'preprocessing_version': preprocessingVersion,
    'capture_platform': capturePlatform,
    'capture_device_class': captureDeviceClass,
    'pose_order': poseOrder,
    'photos': photos.map((photo) => photo.toJson()).toList(growable: false),
  };
}

/// The school's answer to "what is this student's Face ID status?".
class OfficialFaceIdStatus {
  const OfficialFaceIdStatus({
    required this.studentId,
    this.activeTemplateId,
    this.activeApprovedAt,
    this.pendingSubmissionId,
    this.pendingSubmittedAt,
    this.lastRejectionReason,
    this.lastRejectedAt,
  });

  factory OfficialFaceIdStatus.fromJson(Map<String, Object?> json) {
    DateTime? date(String key) {
      final value = json[key]?.toString();
      return value == null || value.isEmpty ? null : DateTime.tryParse(value);
    }

    String? text(String key) {
      final value = json[key]?.toString();
      return value == null || value.isEmpty ? null : value;
    }

    return OfficialFaceIdStatus(
      studentId: json['student_id']?.toString() ?? '',
      activeTemplateId: text('active_template_id'),
      activeApprovedAt: date('active_approved_at'),
      pendingSubmissionId: text('pending_submission_id'),
      pendingSubmittedAt: date('pending_submitted_at'),
      lastRejectionReason: text('last_rejection_reason'),
      lastRejectedAt: date('last_rejected_at'),
    );
  }

  final String studentId;
  final String? activeTemplateId;
  final DateTime? activeApprovedAt;
  final String? pendingSubmissionId;
  final DateTime? pendingSubmittedAt;
  final String? lastRejectionReason;
  final DateTime? lastRejectedAt;

  bool get hasApprovedFaceId => activeTemplateId != null;
  bool get hasPendingSubmission => pendingSubmissionId != null;

  /// An approved Face ID stays active while a replacement waits for review,
  /// so the overall state is "approved" whenever one is active.
  OfficialFaceIdState get state {
    if (hasApprovedFaceId) return OfficialFaceIdState.approved;
    if (hasPendingSubmission) return OfficialFaceIdState.pendingApproval;
    if (lastRejectionReason != null) return OfficialFaceIdState.rejected;
    return OfficialFaceIdState.notSubmitted;
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'student_id': studentId,
    'active_template_id': activeTemplateId,
    'active_approved_at': activeApprovedAt?.toUtc().toIso8601String(),
    'pending_submission_id': pendingSubmissionId,
    'pending_submitted_at': pendingSubmittedAt?.toUtc().toIso8601String(),
    'last_rejection_reason': lastRejectionReason,
    'last_rejected_at': lastRejectedAt?.toUtc().toIso8601String(),
  };
}

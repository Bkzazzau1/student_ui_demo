import 'face_identity_landmark_matrix.dart';
import 'face_identity_person_gate.dart';

enum FaceIdentityQualityLevel { excellent, good, acceptable, retry }

/// Deterministic quality gate thresholds.
///
/// None of these numbers are claimed to be final, scientifically validated
/// production thresholds. They are a technically sound starting gate meant
/// to be recalibrated once a real held-out dataset is available, so every
/// value is a constructor parameter rather than a hardcoded literal.
class FaceIdentityQualityThresholds {
  const FaceIdentityQualityThresholds({
    this.minFaceConfidence = 0.72,
    this.minFaceCoverage = 0.24,
    this.minPersonConfidence = 0.5,
    this.maxNeutralYaw = 0.6,
    this.maxNeutralPitch = 0.6,
    this.minAlignmentQuality = 0.35,
    this.excellentScore = 0.85,
    this.goodScore = 0.70,
    this.acceptableScore = 0.55,
  });

  final double minFaceConfidence;
  final double minFaceCoverage;
  final double minPersonConfidence;
  final double maxNeutralYaw;
  final double maxNeutralPitch;
  final double minAlignmentQuality;
  final double excellentScore;
  final double goodScore;
  final double acceptableScore;
}

class FaceIdentityQualityGrade {
  const FaceIdentityQualityGrade({
    required this.overallScore,
    required this.level,
    required this.personPresent,
    required this.singlePerson,
    required this.facePresent,
    required this.landmarksComplete,
    required this.eyesVisible,
    required this.noseVisible,
    required this.mouthVisible,
    required this.faceCentered,
    required this.faceCoverage,
    required this.poseAcceptable,
    required this.alignmentAcceptable,
    required this.faceConfidence,
    required this.personConfidence,
    required this.yaw,
    required this.pitch,
    required this.roll,
    required this.failureReasons,
  });

  final double overallScore;
  final FaceIdentityQualityLevel level;
  final bool personPresent;
  final bool singlePerson;
  final bool facePresent;
  final bool landmarksComplete;
  final bool eyesVisible;
  final bool noseVisible;
  final bool mouthVisible;
  final bool faceCentered;
  final double faceCoverage;
  final bool poseAcceptable;
  final bool alignmentAcceptable;
  final double faceConfidence;
  final double personConfidence;
  final double yaw;
  final double pitch;
  final double roll;
  final List<String> failureReasons;

  bool get accepted => level != FaceIdentityQualityLevel.retry;
}

/// Combines the YOLO person gate, the facial landmark matrix, and the raw
/// face-detector confidence into one structured, explainable quality grade.
///
/// This never touches the SFace embedding: it only decides whether a sample
/// is good enough to be handed to the embedder at all.
class FaceIdentityQualityGrader {
  const FaceIdentityQualityGrader({
    this.thresholds = const FaceIdentityQualityThresholds(),
  });

  final FaceIdentityQualityThresholds thresholds;

  FaceIdentityQualityGrade grade({
    required FaceIdentityPersonGateResult personGate,
    required double faceConfidence,
    required FaceLandmarkMatrix landmarks,
  }) {
    final reasons = <String>[];

    final personPresent =
        personGate.state != FaceIdentityPersonGateState.noPersonDetected;
    final singlePerson =
        personGate.state != FaceIdentityPersonGateState.multiplePeopleDetected;
    if (!personPresent) {
      reasons.add('Only one person should be visible.');
    }
    if (!singlePerson) {
      reasons.add('Only one person should be visible.');
    }

    final facePresent =
        landmarks.eyesVisible && landmarks.noseVisible && landmarks.mouthVisible;
    if (!landmarks.eyesVisible || !landmarks.noseVisible || !landmarks.mouthVisible) {
      reasons.add('Keep your eyes, nose, and mouth clearly visible.');
    }
    if (!landmarks.landmarksComplete) {
      reasons.add('Your full face must be visible.');
    }
    if (!landmarks.faceCentered) {
      reasons.add('Move closer and center your face.');
    }
    if (landmarks.faceCoverage < thresholds.minFaceCoverage) {
      reasons.add('Move closer to the camera.');
    }
    if (faceConfidence < thresholds.minFaceConfidence) {
      reasons.add('Look directly at the camera.');
    }

    final poseAcceptable =
        landmarks.yaw.abs() <= thresholds.maxNeutralYaw &&
        landmarks.pitch.abs() <= thresholds.maxNeutralPitch;
    if (!poseAcceptable) {
      reasons.add('Look directly at the camera.');
    }

    final alignmentAcceptable =
        landmarks.alignmentQuality >= thresholds.minAlignmentQuality;
    if (!alignmentAcceptable) {
      reasons.add('Improve the lighting and hold your face steady.');
    }

    if (personGate.state == FaceIdentityPersonGateState.runtimeUnavailable) {
      reasons.add(
        'Person-presence check is unavailable on this device; face checks only.',
      );
    }

    final score = _score(
      personGate: personGate,
      faceConfidence: faceConfidence,
      landmarks: landmarks,
      poseAcceptable: poseAcceptable,
      alignmentAcceptable: alignmentAcceptable,
    );

    // Every boolean gate is a hard requirement, not just a scoring input:
    // an image that fails any one of them must retry, never be accepted at
    // a merely lower tier. The score only ranks samples that already
    // cleared every gate.
    final hardBlock = !personPresent ||
        !singlePerson ||
        !facePresent ||
        !landmarks.landmarksComplete ||
        !landmarks.faceCentered ||
        !poseAcceptable ||
        !alignmentAcceptable ||
        faceConfidence < thresholds.minFaceConfidence ||
        landmarks.faceCoverage < thresholds.minFaceCoverage;

    final level = hardBlock
        ? FaceIdentityQualityLevel.retry
        : _levelForScore(score);

    return FaceIdentityQualityGrade(
      overallScore: score,
      level: level,
      personPresent: personPresent,
      singlePerson: singlePerson,
      facePresent: facePresent,
      landmarksComplete: landmarks.landmarksComplete,
      eyesVisible: landmarks.eyesVisible,
      noseVisible: landmarks.noseVisible,
      mouthVisible: landmarks.mouthVisible,
      faceCentered: landmarks.faceCentered,
      faceCoverage: landmarks.faceCoverage,
      poseAcceptable: poseAcceptable,
      alignmentAcceptable: alignmentAcceptable,
      faceConfidence: faceConfidence,
      personConfidence: personGate.personConfidence,
      yaw: landmarks.yaw,
      pitch: landmarks.pitch,
      roll: landmarks.roll,
      failureReasons: List.unmodifiable(reasons.toSet()),
    );
  }

  double _score({
    required FaceIdentityPersonGateResult personGate,
    required double faceConfidence,
    required FaceLandmarkMatrix landmarks,
    required bool poseAcceptable,
    required bool alignmentAcceptable,
  }) {
    if (personGate.blocking) return 0.0;
    if (!landmarks.eyesVisible || !landmarks.noseVisible || !landmarks.mouthVisible) {
      return 0.0;
    }
    if (!landmarks.landmarksComplete || !landmarks.faceCentered) return 0.0;

    var score = faceConfidence.clamp(0.0, 1.0) * 0.45 +
        landmarks.faceCoverage.clamp(0.0, 1.0) * 0.2 +
        landmarks.alignmentQuality.clamp(0.0, 1.0) * 0.2;
    score += poseAcceptable ? 0.1 : 0.0;
    score += alignmentAcceptable ? 0.05 : 0.0;
    return score.clamp(0.0, 1.0).toDouble();
  }

  FaceIdentityQualityLevel _levelForScore(double score) {
    if (score >= thresholds.excellentScore) {
      return FaceIdentityQualityLevel.excellent;
    }
    if (score >= thresholds.goodScore) return FaceIdentityQualityLevel.good;
    if (score >= thresholds.acceptableScore) {
      return FaceIdentityQualityLevel.acceptable;
    }
    return FaceIdentityQualityLevel.retry;
  }
}

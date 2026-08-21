import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:students_ui_demo/face_demo/face_identity_landmark_matrix.dart';
import 'package:students_ui_demo/face_demo/face_identity_person_gate.dart';
import 'package:students_ui_demo/face_demo/face_identity_quality.dart';

FaceIdentityPersonGateResult _singlePerson() =>
    const FaceIdentityPersonGateResult(
      state: FaceIdentityPersonGateState.accepted,
      personCount: 1,
      personConfidence: 0.95,
      reason: 'ok',
    );

Map<int, math.Point<double>> _goodFacePoints() {
  final points = <int, math.Point<double>>{};
  for (var i = 0; i < 468; i++) {
    points[i] = const math.Point<double>(200, 200);
  }
  points[33] = const math.Point<double>(160, 190);
  points[133] = const math.Point<double>(185, 190);
  points[159] = const math.Point<double>(172, 183);
  points[145] = const math.Point<double>(172, 197);
  points[362] = const math.Point<double>(215, 190);
  points[263] = const math.Point<double>(240, 190);
  points[386] = const math.Point<double>(228, 183);
  points[374] = const math.Point<double>(228, 197);
  points[1] = const math.Point<double>(200, 212);
  points[61] = const math.Point<double>(175, 270);
  points[291] = const math.Point<double>(225, 270);
  var i = 500;
  for (final corner in const [
    math.Point<double>(140, 120),
    math.Point<double>(260, 120),
    math.Point<double>(140, 340),
    math.Point<double>(260, 340),
  ]) {
    points[i++] = corner;
  }
  return points;
}

void main() {
  const grader = FaceIdentityQualityGrader();

  test('a good sample earns an acceptable-or-better grade with no blocking reasons', () {
    final matrix = FaceLandmarkMatrix.fromPoints(_goodFacePoints(), 400, 400);

    final grade = grader.grade(
      personGate: _singlePerson(),
      faceConfidence: 0.9,
      landmarks: matrix,
    );

    expect(grade.accepted, isTrue);
    expect(
      grade.level,
      anyOf(
        FaceIdentityQualityLevel.acceptable,
        FaceIdentityQualityLevel.good,
        FaceIdentityQualityLevel.excellent,
      ),
    );
    expect(grade.personPresent, isTrue);
    expect(grade.singlePerson, isTrue);
    expect(grade.facePresent, isTrue);
  });

  test(
    'a landmarker-confirmed good face is still accepted even when the '
    'coarser YOLO detector alone reports no person (regression: this used '
    'to block capture on a well-framed, close-up enrollment photo)',
    () {
      final matrix = FaceLandmarkMatrix.fromPoints(_goodFacePoints(), 400, 400);

      final grade = grader.grade(
        personGate: const FaceIdentityPersonGateResult(
          state: FaceIdentityPersonGateState.noPersonDetected,
          personCount: 0,
          personConfidence: 0,
          reason: 'no person',
        ),
        faceConfidence: 0.9,
        landmarks: matrix,
      );

      expect(grade.personPresent, isFalse);
      expect(grade.accepted, isTrue);
      expect(grade.level, isNot(FaceIdentityQualityLevel.retry));
    },
  );

  test('multiple detected people still blocks even with a perfect face match', () {
    final matrix = FaceLandmarkMatrix.fromPoints(_goodFacePoints(), 400, 400);

    final grade = grader.grade(
      personGate: const FaceIdentityPersonGateResult(
        state: FaceIdentityPersonGateState.multiplePeopleDetected,
        personCount: 2,
        personConfidence: 0.9,
        reason: 'two people',
      ),
      faceConfidence: 0.9,
      landmarks: matrix,
    );

    expect(grade.accepted, isFalse);
    expect(grade.level, FaceIdentityQualityLevel.retry);
  });

  test('a low-confidence face detection is sent to retry, not rejected as a mismatch', () {
    final matrix = FaceLandmarkMatrix.fromPoints(_goodFacePoints(), 400, 400);

    final grade = grader.grade(
      personGate: _singlePerson(),
      faceConfidence: 0.1,
      landmarks: matrix,
    );

    expect(grade.level, FaceIdentityQualityLevel.retry);
    expect(grade.failureReasons, isNotEmpty);
  });

  test('an extreme, non-neutral pose is flagged and sent to retry', () {
    final matrix = FaceLandmarkMatrix.fromPoints(_goodFacePoints(), 400, 400);
    // Same geometry, but simulate an extreme pose reading directly.
    final grade = grader.grade(
      personGate: _singlePerson(),
      faceConfidence: 0.9,
      landmarks: FaceLandmarkMatrix(
        landmarkCount: matrix.landmarkCount,
        eyesVisible: matrix.eyesVisible,
        noseVisible: matrix.noseVisible,
        mouthVisible: matrix.mouthVisible,
        landmarksComplete: matrix.landmarksComplete,
        leftEye: matrix.leftEye,
        rightEye: matrix.rightEye,
        nose: matrix.nose,
        mouthLeft: matrix.mouthLeft,
        mouthRight: matrix.mouthRight,
        faceWidth: matrix.faceWidth,
        faceHeight: matrix.faceHeight,
        faceCenterX: matrix.faceCenterX,
        faceCenterY: matrix.faceCenterY,
        eyeDistance: matrix.eyeDistance,
        faceCoverage: matrix.faceCoverage,
        faceCentered: matrix.faceCentered,
        yaw: 0.95,
        pitch: 0.9,
        roll: matrix.roll,
        eyeOpenness: matrix.eyeOpenness,
        mouthOpenness: matrix.mouthOpenness,
        smileWidth: matrix.smileWidth,
        alignmentQuality: matrix.alignmentQuality,
      ),
    );

    expect(grade.poseAcceptable, isFalse);
    expect(grade.level, FaceIdentityQualityLevel.retry);
    expect(grade.failureReasons, contains('Look directly at the camera.'));
  });

  test('quality grade never claims person-present when the gate is blocking', () {
    final matrix = FaceLandmarkMatrix.fromPoints(_goodFacePoints(), 400, 400);

    final grade = grader.grade(
      personGate: const FaceIdentityPersonGateResult(
        state: FaceIdentityPersonGateState.multiplePeopleDetected,
        personCount: 2,
        personConfidence: 0.9,
        reason: 'two people',
      ),
      faceConfidence: 0.9,
      landmarks: matrix,
    );

    expect(grade.singlePerson, isFalse);
    expect(grade.level, FaceIdentityQualityLevel.retry);
    expect(grade.overallScore, 0.0);
  });

  test('an incomplete landmark mesh is sent to retry with a specific reason', () {
    final grade = grader.grade(
      personGate: _singlePerson(),
      faceConfidence: 0.9,
      landmarks: FaceLandmarkMatrix.empty(),
    );

    expect(grade.level, FaceIdentityQualityLevel.retry);
    expect(grade.landmarksComplete, isFalse);
    expect(grade.failureReasons, isNotEmpty);
  });
}

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:students_ui_demo/face_demo/face_identity_landmark_matrix.dart';

Map<int, math.Point<double>> _goodFacePoints() {
  final points = <int, math.Point<double>>{};
  // Fill a dense mesh so `landmarksComplete` is satisfied.
  for (var i = 0; i < 468; i++) {
    points[i] = const math.Point<double>(200, 200);
  }
  points[33] = const math.Point<double>(160, 190); // left eye outer
  points[133] = const math.Point<double>(185, 190); // left eye inner
  points[159] = const math.Point<double>(172, 183); // left eyelid upper
  points[145] = const math.Point<double>(172, 197); // left eyelid lower
  points[362] = const math.Point<double>(215, 190); // right eye inner
  points[263] = const math.Point<double>(240, 190); // right eye outer
  points[386] = const math.Point<double>(228, 183); // right eyelid upper
  points[374] = const math.Point<double>(228, 197); // right eyelid lower
  points[1] = const math.Point<double>(200, 212); // nose
  points[61] = const math.Point<double>(175, 270); // mouth left
  points[291] = const math.Point<double>(225, 270); // mouth right
  points[13] = const math.Point<double>(200, 265); // mouth upper aperture
  points[14] = const math.Point<double>(200, 275); // mouth lower aperture

  // Spread the remaining mesh across a plausible face bounding box so the
  // width/height/aspect/centering checks pass.
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
  group('FaceLandmarkMatrix.fromPoints', () {
    test('a well-framed face reports every region visible and usable', () {
      final matrix = FaceLandmarkMatrix.fromPoints(
        _goodFacePoints(),
        400,
        400,
      );

      expect(matrix.eyesVisible, isTrue);
      expect(matrix.noseVisible, isTrue);
      expect(matrix.mouthVisible, isTrue);
      expect(matrix.landmarksComplete, isTrue);
      expect(matrix.faceCentered, isTrue);
      expect(matrix.isGeometryUsable, isTrue);
      expect(matrix.leftEye, isNotNull);
      expect(matrix.rightEye, isNotNull);
      expect(matrix.eyeDistance, greaterThan(0));
      expect(matrix.mouthOpenness, greaterThan(0));
    });

    test('a missing nose landmark is rejected without crashing', () {
      final points = _goodFacePoints()..remove(1);

      final matrix = FaceLandmarkMatrix.fromPoints(points, 400, 400);

      expect(matrix.noseVisible, isFalse);
      expect(matrix.isGeometryUsable, isFalse);
    });

    test('missing eye landmarks are rejected', () {
      final points = _goodFacePoints()
        ..remove(33)
        ..remove(133);

      final matrix = FaceLandmarkMatrix.fromPoints(points, 400, 400);

      expect(matrix.eyesVisible, isFalse);
      expect(matrix.isGeometryUsable, isFalse);
    });

    test('missing mouth landmarks are rejected', () {
      final points = _goodFacePoints()
        ..remove(61)
        ..remove(291);

      final matrix = FaceLandmarkMatrix.fromPoints(points, 400, 400);

      expect(matrix.mouthVisible, isFalse);
      expect(matrix.isGeometryUsable, isFalse);
    });

    test('a sparse mesh is reported as incomplete', () {
      final points = <int, math.Point<double>>{
        33: const math.Point<double>(160, 190),
        133: const math.Point<double>(185, 190),
        159: const math.Point<double>(172, 183),
        145: const math.Point<double>(172, 197),
        362: const math.Point<double>(215, 190),
        263: const math.Point<double>(240, 190),
        386: const math.Point<double>(228, 183),
        374: const math.Point<double>(228, 197),
        1: const math.Point<double>(200, 230),
        61: const math.Point<double>(175, 270),
        291: const math.Point<double>(225, 270),
      };

      final matrix = FaceLandmarkMatrix.fromPoints(points, 400, 400);

      expect(matrix.landmarksComplete, isFalse);
      expect(matrix.isGeometryUsable, isFalse);
    });

    test('a face pushed into a corner fails centering', () {
      final points = <int, math.Point<double>>{};
      for (var i = 0; i < 468; i++) {
        points[i] = const math.Point<double>(20, 20);
      }
      points[33] = const math.Point<double>(6, 16);
      points[133] = const math.Point<double>(12, 16);
      points[159] = const math.Point<double>(9, 13);
      points[145] = const math.Point<double>(9, 19);
      points[362] = const math.Point<double>(18, 16);
      points[263] = const math.Point<double>(24, 16);
      points[386] = const math.Point<double>(21, 13);
      points[374] = const math.Point<double>(21, 19);
      points[1] = const math.Point<double>(15, 23);
      points[61] = const math.Point<double>(10, 27);
      points[291] = const math.Point<double>(20, 27);

      final matrix = FaceLandmarkMatrix.fromPoints(points, 400, 400);

      expect(matrix.eyesVisible, isTrue);
      expect(matrix.faceCentered, isFalse);
      expect(matrix.isGeometryUsable, isFalse);
    });

    test('empty() is always a rejection, never a passing result', () {
      final matrix = FaceLandmarkMatrix.empty();

      expect(matrix.isGeometryUsable, isFalse);
      expect(matrix.eyesVisible, isFalse);
      expect(matrix.noseVisible, isFalse);
      expect(matrix.mouthVisible, isFalse);
    });
  });
}

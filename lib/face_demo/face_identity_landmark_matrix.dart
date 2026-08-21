import 'dart:math' as math;

/// Required MediaPipe-style landmark indexes for each facial region.
///
/// These are the same indexes the enrollment/verification pipeline has
/// always used; this file only gives the geometry a single, testable home
/// instead of re-deriving it inline for every caller.
const List<int> kLeftEyeLandmarkIndexes = <int>[33, 133, 159, 145];
const List<int> kRightEyeLandmarkIndexes = <int>[362, 263, 386, 374];
const List<int> kNoseLandmarkIndexes = <int>[1];
const List<int> kMouthLandmarkIndexes = <int>[61, 291];
const List<int> kMouthApertureLandmarkIndexes = <int>[13, 14];

/// A structured, deterministic snapshot of one face's landmark geometry.
///
/// This is deliberately NOT the facial identity representation. It exists to
/// validate capture quality, drive alignment, support liveness/pose checks,
/// and explain to the student why a sample was rejected. The SFace embedding
/// remains the only signal used for identity matching.
class FaceLandmarkMatrix {
  const FaceLandmarkMatrix({
    required this.landmarkCount,
    required this.eyesVisible,
    required this.noseVisible,
    required this.mouthVisible,
    required this.landmarksComplete,
    required this.leftEye,
    required this.rightEye,
    required this.nose,
    required this.mouthLeft,
    required this.mouthRight,
    required this.faceWidth,
    required this.faceHeight,
    required this.faceCenterX,
    required this.faceCenterY,
    required this.eyeDistance,
    required this.faceCoverage,
    required this.faceCentered,
    required this.yaw,
    required this.pitch,
    required this.roll,
    required this.eyeOpenness,
    required this.mouthOpenness,
    required this.smileWidth,
    required this.alignmentQuality,
  });

  /// A geometry snapshot for the "no usable landmarks at all" case. Callers
  /// must treat this as a rejection, never as a passing result.
  factory FaceLandmarkMatrix.empty() => const FaceLandmarkMatrix(
    landmarkCount: 0,
    eyesVisible: false,
    noseVisible: false,
    mouthVisible: false,
    landmarksComplete: false,
    leftEye: null,
    rightEye: null,
    nose: null,
    mouthLeft: null,
    mouthRight: null,
    faceWidth: 0,
    faceHeight: 0,
    faceCenterX: 0,
    faceCenterY: 0,
    eyeDistance: 0,
    faceCoverage: 0,
    faceCentered: false,
    yaw: 0,
    pitch: 0,
    roll: 0,
    eyeOpenness: 0,
    mouthOpenness: 0,
    smileWidth: 0,
    alignmentQuality: 0,
  );

  /// Builds the matrix from raw normalized landmark points (as produced by
  /// [analyseRgbRaw]-style native payloads) plus the source image size.
  factory FaceLandmarkMatrix.fromPoints(
    Map<int, math.Point<double>> points,
    int width,
    int height,
  ) {
    final eyesVisible = kLeftEyeLandmarkIndexes.every(points.containsKey) &&
        kRightEyeLandmarkIndexes.every(points.containsKey);
    final noseVisible = kNoseLandmarkIndexes.every(points.containsKey);
    final mouthVisible = kMouthLandmarkIndexes.every(points.containsKey);
    // Requiring ~400 of the 468 MediaPipe mesh points keeps partial/occluded
    // detections from being treated as a complete face.
    final landmarksComplete = points.length >= 400;

    if (!eyesVisible || !noseVisible || !mouthVisible || width <= 0 || height <= 0) {
      return FaceLandmarkMatrix(
        landmarkCount: points.length,
        eyesVisible: eyesVisible,
        noseVisible: noseVisible,
        mouthVisible: mouthVisible,
        landmarksComplete: landmarksComplete,
        leftEye: null,
        rightEye: null,
        nose: points[1],
        mouthLeft: points[61],
        mouthRight: points[291],
        faceWidth: 0,
        faceHeight: 0,
        faceCenterX: 0,
        faceCenterY: 0,
        eyeDistance: 0,
        faceCoverage: 0,
        faceCentered: false,
        yaw: 0,
        pitch: 0,
        roll: 0,
        eyeOpenness: 0,
        mouthOpenness: 0,
        smileWidth: 0,
        alignmentQuality: 0,
      );
    }

    final leftEye = _average(points[33]!, points[133]!);
    final rightEye = _average(points[362]!, points[263]!);
    final nose = points[1]!;
    final mouthLeft = points[61]!;
    final mouthRight = points[291]!;
    final eyeDistance = _distance(leftEye, rightEye);

    final xs = points.values.map((point) => point.x);
    final ys = points.values.map((point) => point.y);
    final minX = xs.reduce(math.min);
    final maxX = xs.reduce(math.max);
    final minY = ys.reduce(math.min);
    final maxY = ys.reduce(math.max);
    final faceWidth = maxX - minX;
    final faceHeight = maxY - minY;
    final faceCenterX = (minX + maxX) / 2;
    final faceCenterY = (minY + maxY) / 2;

    final faceCoverage = eyeDistance <= 0
        ? 0.0
        : (eyeDistance / width * 4.0).clamp(0.0, 1.0).toDouble();

    final faceCentered = _isCentered(
      points: points,
      leftEye: leftEye,
      rightEye: rightEye,
      nose: nose,
      mouthLeft: mouthLeft,
      mouthRight: mouthRight,
      faceWidth: faceWidth,
      faceHeight: faceHeight,
      minX: minX,
      maxX: maxX,
      minY: minY,
      maxY: maxY,
      width: width,
      height: height,
      eyeDistance: eyeDistance,
    );

    final yaw = eyeDistance <= 0
        ? 0.0
        : (nose.x - (leftEye.x + rightEye.x) / 2) / eyeDistance;
    final pitch = eyeDistance <= 0
        ? 0.0
        : (nose.y - (leftEye.y + rightEye.y) / 2) / eyeDistance;
    final roll = math.atan2(rightEye.y - leftEye.y, rightEye.x - leftEye.x) /
        (math.pi / 4);

    final eyeOpenness = eyeDistance <= 0
        ? 0.0
        : (_distance(points[159]!, points[145]!) +
                  _distance(points[386]!, points[374]!)) /
              (2 * eyeDistance);
    final smileWidth =
        eyeDistance <= 0 ? 0.0 : _distance(mouthLeft, mouthRight) / eyeDistance;
    final mouthOpenness =
        eyeDistance > 0 && points.containsKey(13) && points.containsKey(14)
        ? _distance(points[13]!, points[14]!) / eyeDistance
        : 0.0;

    final levelness = 1.0 - (roll.abs()).clamp(0.0, 1.0);
    final alignmentQuality = landmarksComplete
        ? ((faceCentered ? 1.0 : 0.4) * 0.6 + levelness * 0.4)
              .clamp(0.0, 1.0)
              .toDouble()
        : 0.0;

    return FaceLandmarkMatrix(
      landmarkCount: points.length,
      eyesVisible: eyesVisible,
      noseVisible: noseVisible,
      mouthVisible: mouthVisible,
      landmarksComplete: landmarksComplete,
      leftEye: leftEye,
      rightEye: rightEye,
      nose: nose,
      mouthLeft: mouthLeft,
      mouthRight: mouthRight,
      faceWidth: faceWidth,
      faceHeight: faceHeight,
      faceCenterX: faceCenterX,
      faceCenterY: faceCenterY,
      eyeDistance: eyeDistance,
      faceCoverage: faceCoverage,
      faceCentered: faceCentered,
      yaw: yaw,
      pitch: pitch,
      roll: roll,
      eyeOpenness: eyeOpenness,
      mouthOpenness: mouthOpenness,
      smileWidth: smileWidth,
      alignmentQuality: alignmentQuality,
    );
  }

  final int landmarkCount;
  final bool eyesVisible;
  final bool noseVisible;
  final bool mouthVisible;
  final bool landmarksComplete;
  final math.Point<double>? leftEye;
  final math.Point<double>? rightEye;
  final math.Point<double>? nose;
  final math.Point<double>? mouthLeft;
  final math.Point<double>? mouthRight;
  final double faceWidth;
  final double faceHeight;
  final double faceCenterX;
  final double faceCenterY;
  final double eyeDistance;
  final double faceCoverage;
  final bool faceCentered;
  final double yaw;
  final double pitch;
  final double roll;
  final double eyeOpenness;
  final double mouthOpenness;
  final double smileWidth;
  final double alignmentQuality;

  /// A face is only usable for enrollment/verification once every required
  /// region is visible, the mesh is complete, and it sits inside the guide.
  bool get isGeometryUsable =>
      eyesVisible &&
      noseVisible &&
      mouthVisible &&
      landmarksComplete &&
      faceCentered;

  static bool _isCentered({
    required Map<int, math.Point<double>> points,
    required math.Point<double> leftEye,
    required math.Point<double> rightEye,
    required math.Point<double> nose,
    required math.Point<double> mouthLeft,
    required math.Point<double> mouthRight,
    required double faceWidth,
    required double faceHeight,
    required double minX,
    required double maxX,
    required double minY,
    required double maxY,
    required int width,
    required int height,
    required double eyeDistance,
  }) {
    if (faceWidth / width < 0.22 || faceWidth / width > 0.78) return false;
    if (faceHeight / height < 0.28 || faceHeight / height > 0.90) return false;
    final aspect = faceWidth / faceHeight;
    if (aspect < 0.52 || aspect > 1.15) return false;
    final centerX = (minX + maxX) / (2 * width);
    final centerY = (minY + maxY) / (2 * height);
    if (centerX < 0.27 || centerX > 0.73) return false;
    if (centerY < 0.24 || centerY > 0.76) return false;

    final eyeRatio = eyeDistance / faceWidth;
    if (eyeRatio < 0.24 || eyeRatio > 0.58) return false;
    if ((leftEye.y - rightEye.y).abs() / eyeDistance > 0.28) return false;
    final eyeY = (leftEye.y + rightEye.y) / 2;
    final mouthY = (mouthLeft.y + mouthRight.y) / 2;
    if (nose.y <= eyeY || mouthY <= nose.y) return false;
    return nose.x >= minX && nose.x <= maxX;
  }

  static math.Point<double> _average(
    math.Point<double> first,
    math.Point<double> second,
  ) => math.Point<double>((first.x + second.x) / 2, (first.y + second.y) / 2);

  static double _distance(math.Point<double> a, math.Point<double> b) =>
      math.sqrt(math.pow(a.x - b.x, 2) + math.pow(a.y - b.y, 2));
}

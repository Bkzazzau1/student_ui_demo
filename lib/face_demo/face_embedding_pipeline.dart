import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../proctoring_demo/native_face_landmarker_runtime.dart';
import 'face_identity_landmark_matrix.dart';
import 'face_identity_person_gate.dart';
import 'face_identity_quality.dart';
import 'native_face_embedding_runtime.dart';

class FaceEmbeddingPipelineResult {
  const FaceEmbeddingPipelineResult({
    required this.embedding,
    required this.quality,
    required this.faceConfidence,
    required this.alignedRgb,
    required this.yaw,
    required this.pitch,
    required this.eyeOpenness,
    required this.smileWidth,
    required this.mouthOpenness,
    required this.landmarks,
    required this.personGate,
    required this.qualityGrade,
  });

  final List<double> embedding;
  final double quality;
  final double faceConfidence;
  final Uint8List alignedRgb;
  final double yaw;
  final double pitch;
  final double eyeOpenness;
  final double smileWidth;
  final double mouthOpenness;

  /// The full facial landmark matrix behind this sample. Capture validation,
  /// alignment, pose, and liveness support all read from this; identity
  /// matching never does.
  final FaceLandmarkMatrix landmarks;

  /// What the YOLO person gate saw for this frame.
  final FaceIdentityPersonGateResult personGate;

  /// The structured quality assessment this sample was graded with.
  final FaceIdentityQualityGrade qualityGrade;
}

class FaceEmbeddingPipeline {
  FaceEmbeddingPipeline({
    NativeFaceLandmarkerRuntime? landmarker,
    NativeFaceEmbeddingRuntime? embedder,
    FaceIdentityPersonGate? personGate,
    FaceIdentityQualityGrader? qualityGrader,
  }) : _landmarker = landmarker ?? NativeFaceLandmarkerRuntime(),
       _embedder = embedder ?? NativeFaceEmbeddingRuntime(),
       _personGate = personGate ?? FaceIdentityPersonGate(),
       _qualityGrader = qualityGrader ?? const FaceIdentityQualityGrader();

  final NativeFaceLandmarkerRuntime _landmarker;
  final NativeFaceEmbeddingRuntime _embedder;
  final FaceIdentityPersonGate _personGate;
  final FaceIdentityQualityGrader _qualityGrader;
  bool _ready = false;
  String lastFailureReason = '';

  Future<bool> initialize() async {
    if (_ready) return true;
    final results = await Future.wait<bool>([
      _landmarker.initialize(),
      _embedder.initialize(),
    ]);
    _ready = results.every((ready) => ready);
    return _ready;
  }

  /// CAMERA FRAME -> YOLO person gate -> face landmarker -> facial matrix ->
  /// quality grade -> alignment -> SFace embedding -> L2-normalized result.
  ///
  /// The landmark matrix and quality grade are always produced (even on
  /// rejection) so callers can show a specific, calm correction message
  /// instead of a generic failure.
  Future<FaceEmbeddingPipelineResult?> processEncodedImage(
    Uint8List encoded,
  ) async {
    lastFailureReason = '';
    if (!_ready && !await initialize()) {
      lastFailureReason = 'Face AI could not initialize.';
      return null;
    }
    final decoded = img.decodeImage(encoded);
    if (decoded == null || decoded.width < 112 || decoded.height < 112) {
      lastFailureReason = 'The camera image is not usable.';
      return null;
    }
    // `getBytes` does one bulk conversion instead of allocating a `Pixel`
    // object per call site via `getPixel`; on a full camera-resolution
    // frame (hundreds of thousands of pixels, done on every single capture
    // attempt) that per-pixel overhead was a measurable, needless slowdown.
    final rgb = decoded.getBytes(order: img.ChannelOrder.rgb);

    final personGateResult = await _personGate.analyzeRgb(
      rgbBytes: rgb,
      width: decoded.width,
      height: decoded.height,
    );

    final landmarksPayload = await _landmarker.analyseRgbRaw(
      rgbBytes: rgb,
      width: decoded.width,
      height: decoded.height,
    );
    final confidence = _number(landmarksPayload?['confidence']);
    final points = _points(
      landmarksPayload?['landmarks'],
      decoded.width,
      decoded.height,
    );
    final matrix = landmarksPayload == null
        ? FaceLandmarkMatrix.empty()
        : FaceLandmarkMatrix.fromPoints(points, decoded.width, decoded.height);

    final grade = _qualityGrader.grade(
      personGate: personGateResult,
      faceConfidence: confidence,
      landmarks: matrix,
    );

    if (!grade.accepted) {
      lastFailureReason = grade.failureReasons.isEmpty
          ? 'No reliable face was detected.'
          : grade.failureReasons.first;
      return null;
    }

    final leftEye = matrix.leftEye!;
    final rightEye = matrix.rightEye!;
    final aligned = _align(decoded, leftEye, rightEye);
    final sample = await _embedder.embedAlignedRgb(aligned);
    if (sample == null || sample.embedding.length != 128) {
      lastFailureReason = 'The face identity sample was not reliable.';
      return null;
    }
    return FaceEmbeddingPipelineResult(
      embedding: sample.embedding,
      quality: grade.overallScore,
      faceConfidence: confidence,
      alignedRgb: aligned,
      yaw: matrix.yaw,
      pitch: matrix.pitch,
      eyeOpenness: matrix.eyeOpenness,
      smileWidth: matrix.smileWidth,
      mouthOpenness: matrix.mouthOpenness,
      landmarks: matrix,
      personGate: personGateResult,
      qualityGrade: grade,
    );
  }

  Map<int, math.Point<double>> _points(Object? raw, int width, int height) {
    if (raw is! Iterable) return const {};
    final result = <int, math.Point<double>>{};
    for (final value in raw.whereType<Map>()) {
      final point = Map<String, Object?>.from(value);
      final index = (point['index'] as num?)?.toInt();
      if (index == null) continue;
      result[index] = math.Point<double>(
        _number(point['x']) * width,
        _number(point['y']) * height,
      );
    }
    return result;
  }

  Uint8List _align(
    img.Image source,
    math.Point<double> leftEye,
    math.Point<double> rightEye,
  ) {
    const targetLeft = math.Point<double>(38.2946, 51.6963);
    const targetRight = math.Point<double>(73.5318, 51.5014);
    final sourceAngle = math.atan2(
      rightEye.y - leftEye.y,
      rightEye.x - leftEye.x,
    );
    final targetAngle = math.atan2(
      targetRight.y - targetLeft.y,
      targetRight.x - targetLeft.x,
    );
    final scale =
        _distance(leftEye, rightEye) / _distance(targetLeft, targetRight);
    final cosine = math.cos(sourceAngle - targetAngle);
    final sine = math.sin(sourceAngle - targetAngle);
    final output = Uint8List(112 * 112 * 3);
    var offset = 0;
    for (var y = 0; y < 112; y++) {
      for (var x = 0; x < 112; x++) {
        final dx = x - targetLeft.x;
        final dy = y - targetLeft.y;
        final sx = leftEye.x + scale * (cosine * dx - sine * dy);
        final sy = leftEye.y + scale * (sine * dx + cosine * dy);
        final ix = sx.round().clamp(0, source.width - 1);
        final iy = sy.round().clamp(0, source.height - 1);
        final pixel = source.getPixel(ix, iy);
        output[offset++] = pixel.r.toInt();
        output[offset++] = pixel.g.toInt();
        output[offset++] = pixel.b.toInt();
      }
    }
    return output;
  }

  double _distance(math.Point<double> a, math.Point<double> b) =>
      math.sqrt(math.pow(a.x - b.x, 2) + math.pow(a.y - b.y, 2));

  double _number(Object? value) =>
      value is num ? value.toDouble() : double.tryParse('$value') ?? 0.0;
}

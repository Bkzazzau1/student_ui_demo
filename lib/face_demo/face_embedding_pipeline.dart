import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../proctoring_demo/native_face_landmarker_runtime.dart';
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
}

class FaceEmbeddingPipeline {
  FaceEmbeddingPipeline({
    NativeFaceLandmarkerRuntime? landmarker,
    NativeFaceEmbeddingRuntime? embedder,
  }) : _landmarker = landmarker ?? NativeFaceLandmarkerRuntime(),
       _embedder = embedder ?? NativeFaceEmbeddingRuntime();

  final NativeFaceLandmarkerRuntime _landmarker;
  final NativeFaceEmbeddingRuntime _embedder;
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
    final rgb = Uint8List(decoded.width * decoded.height * 3);
    var offset = 0;
    for (var y = 0; y < decoded.height; y++) {
      for (var x = 0; x < decoded.width; x++) {
        final pixel = decoded.getPixel(x, y);
        rgb[offset++] = pixel.r.toInt();
        rgb[offset++] = pixel.g.toInt();
        rgb[offset++] = pixel.b.toInt();
      }
    }
    final landmarks = await _landmarker.analyseRgbRaw(
      rgbBytes: rgb,
      width: decoded.width,
      height: decoded.height,
    );
    if (landmarks == null) {
      lastFailureReason = 'No face was detected.';
      return null;
    }
    final confidence = _number(landmarks['confidence']);
    if (confidence < 0.72) {
      lastFailureReason = 'Face confidence is too low.';
      return null;
    }
    final points = _points(
      landmarks['landmarks'],
      decoded.width,
      decoded.height,
    );
    if (![
      33,
      133,
      362,
      263,
      1,
      61,
      291,
      159,
      145,
      386,
      374,
    ].every(points.containsKey)) {
      lastFailureReason = 'Eyes, nose, or mouth are not fully visible.';
      return null;
    }
    if (!_hasPlausibleCenteredFace(points, decoded.width, decoded.height)) {
      lastFailureReason =
          'Move closer and center your full face inside the green guide.';
      return null;
    }
    final leftEye = _average(points[33]!, points[133]!);
    final rightEye = _average(points[362]!, points[263]!);
    final eyeDistance = _distance(leftEye, rightEye);
    final faceCoverage = (eyeDistance / decoded.width * 4.0).clamp(0.0, 1.0);
    if (faceCoverage < 0.24) {
      lastFailureReason = 'Move closer to the camera.';
      return null;
    }

    final aligned = _align(decoded, leftEye, rightEye);
    final sample = await _embedder.embedAlignedRgb(aligned);
    if (sample == null || sample.embedding.length != 128) {
      lastFailureReason = 'The face identity sample was not reliable.';
      return null;
    }
    final quality = (confidence * 0.7 + faceCoverage * 0.3).clamp(0.0, 1.0);
    return FaceEmbeddingPipelineResult(
      embedding: sample.embedding,
      quality: quality,
      faceConfidence: confidence,
      alignedRgb: aligned,
      yaw: (points[1]!.x - (leftEye.x + rightEye.x) / 2) / eyeDistance,
      pitch: (points[1]!.y - (leftEye.y + rightEye.y) / 2) / eyeDistance,
      eyeOpenness:
          (_distance(points[159]!, points[145]!) +
              _distance(points[386]!, points[374]!)) /
          (2 * eyeDistance),
      smileWidth: _distance(points[61]!, points[291]!) / eyeDistance,
      mouthOpenness: points.containsKey(13) && points.containsKey(14)
          ? _distance(points[13]!, points[14]!) / eyeDistance
          : 0.0,
    );
  }

  bool _hasPlausibleCenteredFace(
    Map<int, math.Point<double>> points,
    int width,
    int height,
  ) {
    if (points.length < 400) return false;
    final xs = points.values.map((point) => point.x);
    final ys = points.values.map((point) => point.y);
    final minX = xs.reduce(math.min);
    final maxX = xs.reduce(math.max);
    final minY = ys.reduce(math.min);
    final maxY = ys.reduce(math.max);
    final faceWidth = maxX - minX;
    final faceHeight = maxY - minY;
    if (faceWidth / width < 0.22 || faceWidth / width > 0.78) return false;
    if (faceHeight / height < 0.28 || faceHeight / height > 0.90) return false;
    final aspect = faceWidth / faceHeight;
    if (aspect < 0.52 || aspect > 1.15) return false;
    final centerX = (minX + maxX) / (2 * width);
    final centerY = (minY + maxY) / (2 * height);
    if (centerX < 0.27 || centerX > 0.73) return false;
    if (centerY < 0.24 || centerY > 0.76) return false;

    final leftEye = _average(points[33]!, points[133]!);
    final rightEye = _average(points[362]!, points[263]!);
    final eyeDistance = _distance(leftEye, rightEye);
    final eyeRatio = eyeDistance / faceWidth;
    if (eyeRatio < 0.24 || eyeRatio > 0.58) return false;
    if ((leftEye.y - rightEye.y).abs() / eyeDistance > 0.28) return false;
    final eyeY = (leftEye.y + rightEye.y) / 2;
    final nose = points[1]!;
    final mouthY = (points[61]!.y + points[291]!.y) / 2;
    if (nose.y <= eyeY || mouthY <= nose.y) return false;
    return nose.x >= minX && nose.x <= maxX;
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

  math.Point<double> _average(
    math.Point<double> first,
    math.Point<double> second,
  ) => math.Point<double>((first.x + second.x) / 2, (first.y + second.y) / 2);

  double _distance(math.Point<double> a, math.Point<double> b) =>
      math.sqrt(math.pow(a.x - b.x, 2) + math.pow(a.y - b.y, 2));

  double _number(Object? value) =>
      value is num ? value.toDouble() : double.tryParse('$value') ?? 0.0;
}

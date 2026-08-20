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
  });

  final List<double> embedding;
  final double quality;
  final double faceConfidence;
  final Uint8List alignedRgb;
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
    if (!_ready && !await initialize()) return null;
    final decoded = img.decodeImage(encoded);
    if (decoded == null || decoded.width < 112 || decoded.height < 112) {
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
    if (landmarks == null) return null;
    final confidence = _number(landmarks['confidence']);
    if (confidence < 0.65) return null;
    final points = _points(
      landmarks['landmarks'],
      decoded.width,
      decoded.height,
    );
    if (![33, 133, 362, 263, 1, 61, 291].every(points.containsKey)) {
      return null;
    }
    final leftEye = _average(points[33]!, points[133]!);
    final rightEye = _average(points[362]!, points[263]!);
    final eyeDistance = _distance(leftEye, rightEye);
    final faceCoverage = (eyeDistance / decoded.width * 4.0).clamp(0.0, 1.0);
    if (faceCoverage < 0.28) return null;

    final aligned = _align(decoded, leftEye, rightEye);
    final sample = await _embedder.embedAlignedRgb(aligned);
    if (sample == null || sample.embedding.length != 128) return null;
    final quality = (confidence * 0.7 + faceCoverage * 0.3).clamp(0.0, 1.0);
    return FaceEmbeddingPipelineResult(
      embedding: sample.embedding,
      quality: quality,
      faceConfidence: confidence,
      alignedRgb: aligned,
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

  math.Point<double> _average(
    math.Point<double> first,
    math.Point<double> second,
  ) => math.Point<double>((first.x + second.x) / 2, (first.y + second.y) / 2);

  double _distance(math.Point<double> a, math.Point<double> b) =>
      math.sqrt(math.pow(a.x - b.x, 2) + math.pow(a.y - b.y, 2));

  double _number(Object? value) =>
      value is num ? value.toDouble() : double.tryParse('$value') ?? 0.0;
}

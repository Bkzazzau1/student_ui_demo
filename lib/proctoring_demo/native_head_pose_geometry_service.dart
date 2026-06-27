import 'native_vision_bridge.dart';

typedef LandmarkPoint = Map<String, Object?>;

class NativeHeadPoseGeometryService {
  const NativeHeadPoseGeometryService({
    NativeVisionBridge? nativeVision,
  }) : _nativeVision = nativeVision ?? const GeneratedNativeVisionBridge();

  final NativeVisionBridge _nativeVision;

  NativeHeadPoseReviewSnapshot? analyzeLandmarks({
    required List<LandmarkPoint> landmarks,
    required double imageWidth,
    required double imageHeight,
  }) {
    if (landmarks.isEmpty || imageWidth <= 0 || imageHeight <= 0) return null;

    final leftEye = _averageNamed(
      landmarks,
      const <String>{'left_eye', 'leftEye', 'LEFT_EYE'},
      fallbackIndices: const <int>[33, 133, 159, 145],
      imageWidth: imageWidth,
      imageHeight: imageHeight,
    );
    final rightEye = _averageNamed(
      landmarks,
      const <String>{'right_eye', 'rightEye', 'RIGHT_EYE'},
      fallbackIndices: const <int>[362, 263, 386, 374],
      imageWidth: imageWidth,
      imageHeight: imageHeight,
    );
    final nose = _firstNamed(
      landmarks,
      const <String>{'nose', 'nose_tip', 'noseTip', 'NOSE_TIP'},
      fallbackIndices: const <int>[1, 4],
      imageWidth: imageWidth,
      imageHeight: imageHeight,
    );
    final mouth = _averageNamed(
      landmarks,
      const <String>{'mouth', 'mouth_center', 'mouthCenter', 'MOUTH_CENTER'},
      fallbackIndices: const <int>[13, 14, 61, 291],
      imageWidth: imageWidth,
      imageHeight: imageHeight,
    );

    if (leftEye == null || rightEye == null || nose == null || mouth == null) {
      return null;
    }

    final faceBox = _faceBox(landmarks, imageWidth, imageHeight);
    if (faceBox == null) return null;

    return _nativeVision.analyzeHeadPoseGeometry(
      leftEyeX: leftEye.x,
      leftEyeY: leftEye.y,
      rightEyeX: rightEye.x,
      rightEyeY: rightEye.y,
      noseX: nose.x,
      noseY: nose.y,
      mouthX: mouth.x,
      mouthY: mouth.y,
      faceWidth: faceBox.width,
      faceHeight: faceBox.height,
    );
  }

  _Point? _firstNamed(
    List<LandmarkPoint> landmarks,
    Set<String> names, {
    required List<int> fallbackIndices,
    required double imageWidth,
    required double imageHeight,
  }) {
    for (final item in landmarks) {
      final name = '${item['name'] ?? item['label'] ?? item['type'] ?? ''}';
      if (names.contains(name)) {
        final point = _pointFromMap(item, imageWidth, imageHeight);
        if (point != null) return point;
      }
    }

    for (final index in fallbackIndices) {
      if (index < 0 || index >= landmarks.length) continue;
      final point = _pointFromMap(landmarks[index], imageWidth, imageHeight);
      if (point != null) return point;
    }
    return null;
  }

  _Point? _averageNamed(
    List<LandmarkPoint> landmarks,
    Set<String> names, {
    required List<int> fallbackIndices,
    required double imageWidth,
    required double imageHeight,
  }) {
    final points = <_Point>[];
    for (final item in landmarks) {
      final name = '${item['name'] ?? item['label'] ?? item['type'] ?? ''}';
      if (names.contains(name)) {
        final point = _pointFromMap(item, imageWidth, imageHeight);
        if (point != null) points.add(point);
      }
    }

    if (points.isEmpty) {
      for (final index in fallbackIndices) {
        if (index < 0 || index >= landmarks.length) continue;
        final point = _pointFromMap(landmarks[index], imageWidth, imageHeight);
        if (point != null) points.add(point);
      }
    }

    if (points.isEmpty) return null;
    final x = points.fold<double>(0, (sum, item) => sum + item.x) / points.length;
    final y = points.fold<double>(0, (sum, item) => sum + item.y) / points.length;
    return _Point(x, y);
  }

  _FaceBox? _faceBox(
    List<LandmarkPoint> landmarks,
    double imageWidth,
    double imageHeight,
  ) {
    final points = landmarks
        .map((item) => _pointFromMap(item, imageWidth, imageHeight))
        .whereType<_Point>()
        .toList();
    if (points.length < 4) return null;

    var minX = points.first.x;
    var maxX = points.first.x;
    var minY = points.first.y;
    var maxY = points.first.y;
    for (final point in points.skip(1)) {
      if (point.x < minX) minX = point.x;
      if (point.x > maxX) maxX = point.x;
      if (point.y < minY) minY = point.y;
      if (point.y > maxY) maxY = point.y;
    }

    final width = (maxX - minX).abs();
    final height = (maxY - minY).abs();
    if (width <= 1 || height <= 1) return null;
    return _FaceBox(width, height);
  }

  _Point? _pointFromMap(
    LandmarkPoint item,
    double imageWidth,
    double imageHeight,
  ) {
    final x = _readDouble(item['x'] ?? item['X'] ?? item['px']);
    final y = _readDouble(item['y'] ?? item['Y'] ?? item['py']);
    if (x == null || y == null) return null;

    final normalized = x >= 0 && x <= 1.5 && y >= 0 && y <= 1.5;
    return _Point(
      normalized ? x * imageWidth : x,
      normalized ? y * imageHeight : y,
    );
  }

  double? _readDouble(Object? value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '');
  }
}

class _Point {
  const _Point(this.x, this.y);

  final double x;
  final double y;
}

class _FaceBox {
  const _FaceBox(this.width, this.height);

  final double width;
  final double height;
}

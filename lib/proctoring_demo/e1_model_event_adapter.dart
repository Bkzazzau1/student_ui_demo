import 'model_event_v1.dart';
import 'native_vision_bridge.dart';

class E1FrameInferenceContext {
  const E1FrameInferenceContext({
    required this.sessionId,
    required this.sourceFrameId,
    required this.captureTimestampNs,
    required this.inferenceTimestampNs,
    required this.modelId,
    required this.modelVersion,
    required this.imageWidth,
    required this.imageHeight,
    this.quality,
    this.backend,
    this.precision,
  });

  final String sessionId;
  final int? sourceFrameId;
  final int captureTimestampNs;
  final int inferenceTimestampNs;
  final String modelId;
  final String modelVersion;
  final int imageWidth;
  final int imageHeight;
  final double? quality;
  final String? backend;
  final String? precision;
}

/// Converts E1 detector outputs into the frozen Stage 3 observation envelope.
///
/// Persistent tracking is deliberately not invented here. Until E1 tracking is
/// implemented, `track_id` remains null even for person detections.
class E1ModelEventAdapter {
  const E1ModelEventAdapter();

  List<ModelEventV1Payload> fromNativeReview({
    required NativeObjectReviewSnapshot review,
    required E1FrameInferenceContext context,
  }) {
    _validateContext(context);

    final output = <ModelEventV1Payload>[];
    for (var index = 0; index < review.detections.length; index++) {
      final detection = review.detections[index];
      final classId = _normalizeClassId(detection.label);
      if (classId.isEmpty) continue;

      output.add(
        _buildEvent(
          context: context,
          detectionIndex: index,
          classId: classId,
          confidence: detection.confidence,
          rawClassId: detection.classId,
          rawLabel: detection.label,
          boundingBox: _normalizedBoundingBox(detection, context),
          regionId: _regionForPixelDetection(detection, context),
          sourceRepresentation: 'rust_yolo_review',
        ),
      );
    }
    return List<ModelEventV1Payload>.unmodifiable(output);
  }

  /// Adapts the Windows ONNX runtime's already-decoded object list.
  ///
  /// `optimized_vision_runtime_engine.cpp` emits bounding boxes in normalized
  /// frame coordinates (`x1`, `y1`, `x2`, `y2`). Treating those values as
  /// pixels would corrupt geometry, so this path intentionally remains
  /// separate from [fromNativeReview].
  List<ModelEventV1Payload> fromNormalizedObjects({
    required Iterable<Map<String, Object?>> objects,
    required E1FrameInferenceContext context,
  }) {
    _validateContext(context);

    final output = <ModelEventV1Payload>[];
    var detectionIndex = 0;
    for (final object in objects) {
      final rawLabel = _readLabel(object);
      final classId = _normalizeClassId(rawLabel);
      if (classId.isEmpty) {
        detectionIndex++;
        continue;
      }

      final confidence = _readDouble(object['confidence']);
      final rawClassId = _readInt(object['class_id']);
      final normalizedBox = _readNormalizedBox(object['box']);

      output.add(
        _buildEvent(
          context: context,
          detectionIndex: detectionIndex,
          classId: classId,
          confidence: confidence,
          rawClassId: rawClassId,
          rawLabel: rawLabel,
          boundingBox: normalizedBox,
          regionId: _regionForNormalizedBox(normalizedBox),
          sourceRepresentation: 'windows_onnx_normalized_objects',
        ),
      );
      detectionIndex++;
    }

    return List<ModelEventV1Payload>.unmodifiable(output);
  }

  ModelEventV1Payload _buildEvent({
    required E1FrameInferenceContext context,
    required int detectionIndex,
    required String classId,
    required double? confidence,
    required Object? rawClassId,
    required String rawLabel,
    required Map<String, Object?>? boundingBox,
    required String? regionId,
    required String sourceRepresentation,
  }) {
    return ModelEventV1Payload(
      sessionId: context.sessionId,
      eventId: _eventId(
        context: context,
        classId: classId,
        detectionIndex: detectionIndex,
      ),
      sourceFrameId: context.sourceFrameId,
      captureTimestampNs: context.captureTimestampNs,
      inferenceTimestampNs: context.inferenceTimestampNs,
      modelId: context.modelId,
      modelVersion: context.modelVersion,
      trackId: null,
      classId: classId,
      confidence: confidence?.clamp(0.0, 1.0),
      quality: context.quality,
      geometry: ModelEventGeometryV1(
        coordinateSpace: 'normalized_frame',
        boundingBox: boundingBox,
        regionId: regionId,
      ),
      validityInterval: ModelEventValidityIntervalV1(
        startTimestampNs: context.captureTimestampNs,
        endTimestampNs: context.captureTimestampNs,
      ),
      metadata: <String, Object?>{
        'modality': 'vision',
        'producer': 'e1_person_object_ai',
        'raw_class_id': rawClassId,
        'raw_label': rawLabel,
        'backend': context.backend,
        'precision': context.precision,
        'source_representation': sourceRepresentation,
        'persistent_tracking_available': false,
        'observable_behaviour_only': true,
      },
    );
  }

  void _validateContext(E1FrameInferenceContext context) {
    if (context.imageWidth <= 0 || context.imageHeight <= 0) {
      throw const FormatException('E1 frame dimensions must be positive');
    }
  }

  Map<String, Object?> _normalizedBoundingBox(
    NativeVisionDetectionSnapshot detection,
    E1FrameInferenceContext context,
  ) {
    final width = context.imageWidth.toDouble();
    final height = context.imageHeight.toDouble();

    // Native decoder coordinates are pixel coordinates. Clamp before
    // normalizing so malformed model output cannot escape the frame space.
    final x = (detection.xMin / width).clamp(0.0, 1.0);
    final y = (detection.yMin / height).clamp(0.0, 1.0);
    final boxWidth = ((detection.xMax - detection.xMin) / width).clamp(
      0.0,
      1.0,
    );
    final boxHeight = ((detection.yMax - detection.yMin) / height).clamp(
      0.0,
      1.0,
    );

    return <String, Object?>{
      'x': x,
      'y': y,
      'width': boxWidth,
      'height': boxHeight,
    };
  }

  Map<String, Object?>? _readNormalizedBox(Object? value) {
    if (value is! Map) return null;
    final box = Map<Object?, Object?>.from(value);
    final x1 = _readDouble(box['x1']);
    final y1 = _readDouble(box['y1']);
    final x2 = _readDouble(box['x2']);
    final y2 = _readDouble(box['y2']);
    if (x1 == null || y1 == null || x2 == null || y2 == null) return null;

    final left = mathMin(x1, x2).clamp(0.0, 1.0);
    final top = mathMin(y1, y2).clamp(0.0, 1.0);
    final right = mathMax(x1, x2).clamp(0.0, 1.0);
    final bottom = mathMax(y1, y2).clamp(0.0, 1.0);
    return <String, Object?>{
      'x': left,
      'y': top,
      'width': (right - left).clamp(0.0, 1.0),
      'height': (bottom - top).clamp(0.0, 1.0),
    };
  }

  String _regionForPixelDetection(
    NativeVisionDetectionSnapshot detection,
    E1FrameInferenceContext context,
  ) {
    final normalizedX = detection.xCenter / context.imageWidth;
    final normalizedY = detection.yCenter / context.imageHeight;
    return _regionForPoint(normalizedX, normalizedY);
  }

  String? _regionForNormalizedBox(Map<String, Object?>? box) {
    if (box == null) return null;
    final x = _readDouble(box['x']);
    final y = _readDouble(box['y']);
    final width = _readDouble(box['width']);
    final height = _readDouble(box['height']);
    if (x == null || y == null || width == null || height == null) return null;
    return _regionForPoint(x + width / 2.0, y + height / 2.0);
  }

  String _regionForPoint(double normalizedX, double normalizedY) {
    final vertical = normalizedY < 0.33
        ? 'upper'
        : normalizedY > 0.67
        ? 'lower'
        : 'middle';
    final horizontal = normalizedX < 0.33
        ? 'left'
        : normalizedX > 0.67
        ? 'right'
        : 'center';
    return '${vertical}_$horizontal';
  }

  String _eventId({
    required E1FrameInferenceContext context,
    required String classId,
    required int detectionIndex,
  }) {
    final source = context.sourceFrameId?.toString() ?? 'no-frame';
    return '${context.sessionId}:e1:$source:${context.captureTimestampNs}:$classId:$detectionIndex';
  }

  String _readLabel(Map<String, Object?> object) {
    for (final key in const <String>['label', 'class', 'name', 'category']) {
      final value = object[key]?.toString().trim() ?? '';
      if (value.isNotEmpty) return value;
    }
    return '';
  }

  int? _readInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.round();
    return int.tryParse(value?.toString() ?? '');
  }

  double? _readDouble(Object? value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '');
  }

  String _normalizeClassId(String label) {
    return label
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
  }
}

double mathMin(double left, double right) => left < right ? left : right;
double mathMax(double left, double right) => left > right ? left : right;

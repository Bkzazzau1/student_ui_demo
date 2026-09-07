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
    if (context.imageWidth <= 0 || context.imageHeight <= 0) {
      throw const FormatException('E1 frame dimensions must be positive');
    }

    final output = <ModelEventV1Payload>[];
    for (var index = 0; index < review.detections.length; index++) {
      final detection = review.detections[index];
      final classId = _normalizeClassId(detection.label);
      if (classId.isEmpty) continue;

      final boundingBox = _normalizedBoundingBox(detection, context);
      final eventId = _eventId(
        context: context,
        classId: classId,
        detectionIndex: index,
      );

      output.add(
        ModelEventV1Payload(
          sessionId: context.sessionId,
          eventId: eventId,
          sourceFrameId: context.sourceFrameId,
          captureTimestampNs: context.captureTimestampNs,
          inferenceTimestampNs: context.inferenceTimestampNs,
          modelId: context.modelId,
          modelVersion: context.modelVersion,
          trackId: null,
          classId: classId,
          confidence: detection.confidence.clamp(0.0, 1.0),
          quality: context.quality,
          geometry: ModelEventGeometryV1(
            coordinateSpace: 'normalized_frame',
            boundingBox: boundingBox,
            regionId: _regionFor(detection, context),
          ),
          validityInterval: ModelEventValidityIntervalV1(
            startTimestampNs: context.captureTimestampNs,
            endTimestampNs: context.captureTimestampNs,
          ),
          metadata: <String, Object?>{
            'modality': 'vision',
            'producer': 'e1_person_object_ai',
            'raw_class_id': detection.classId,
            'raw_label': detection.label,
            'backend': context.backend,
            'precision': context.precision,
            'persistent_tracking_available': false,
            'observable_behaviour_only': true,
          },
        ),
      );
    }
    return List<ModelEventV1Payload>.unmodifiable(output);
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

  String _regionFor(
    NativeVisionDetectionSnapshot detection,
    E1FrameInferenceContext context,
  ) {
    final normalizedX = detection.xCenter / context.imageWidth;
    final normalizedY = detection.yCenter / context.imageHeight;
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

  String _normalizeClassId(String label) {
    return label
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
  }
}

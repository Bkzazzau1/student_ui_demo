import 'e1_exam_object_taxonomy.dart';
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
/// The adapter emits observable detector classes only. Contextual states such
/// as `additional_person` are deliberately not inferred here. Person track IDs
/// also remain null at this boundary and are assigned conservatively by the
/// Rust-owned person tracker before events enter spatiotemporal memory.
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
      final classId = E1ExamObjectTaxonomy.canonicalizeDetectorLabel(
        detection.label,
      );
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
            'canonical_taxonomy_id': E1ExamObjectTaxonomy.taxonomyId,
            'canonical_taxonomy_version': E1ExamObjectTaxonomy.taxonomyVersion,
            'taxonomy_known_class':
                E1ExamObjectTaxonomy.isKnownCanonicalClass(classId),
            'required_detector_class':
                E1ExamObjectTaxonomy.isRequiredDetectorClass(classId),
            'backend': context.backend,
            'precision': context.precision,
            'tracking_assignment_stage': classId == 'person'
                ? 'rust_memory_ingress'
                : 'not_applicable',
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
}

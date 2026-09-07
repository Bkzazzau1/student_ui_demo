import 'e1_object_taxonomy.dart';
import 'e1_small_object_specialist.dart';
import 'model_event_v1.dart';

/// Converts validated local small-object specialist observations into the same
/// frozen ModelEventV1 envelope used by base E1 detections.
class E1SpecialistModelEventAdapter {
  const E1SpecialistModelEventAdapter();

  ModelEventV1Payload? fromObservation({
    required String sessionId,
    required E1SmallObjectSpecialistObservation observation,
    double? quality,
    int observationIndex = 0,
  }) {
    if (sessionId.trim().isEmpty || !observation.isValid) return null;

    final canonicalId = observation.canonicalObjectId;
    if (!E1ObjectTaxonomyV1.specialistCanonicalIds.contains(canonicalId)) {
      return null;
    }

    return ModelEventV1Payload(
      sessionId: sessionId,
      eventId: _eventId(
        sessionId: sessionId,
        observation: observation,
        observationIndex: observationIndex,
      ),
      sourceFrameId: observation.sourceFrameId,
      captureTimestampNs: observation.captureTimestampNs,
      inferenceTimestampNs: observation.inferenceTimestampNs,
      modelId: observation.modelId,
      modelVersion: observation.modelVersion,
      trackId: null,
      classId: canonicalId,
      confidence: observation.confidence,
      quality: quality,
      geometry: ModelEventGeometryV1(
        coordinateSpace: 'normalized_frame',
        boundingBox: <String, Object?>{
          'x': observation.boundingBox['x']!,
          'y': observation.boundingBox['y']!,
          'width': observation.boundingBox['width']!,
          'height': observation.boundingBox['height']!,
        },
        regionId: _regionFor(observation.boundingBox),
      ),
      validityInterval: ModelEventValidityIntervalV1(
        startTimestampNs: observation.captureTimestampNs,
        endTimestampNs: observation.captureTimestampNs,
      ),
      metadata: <String, Object?>{
        'modality': 'vision',
        'producer': 'e1_small_object_specialist',
        'taxonomy_version': E1ObjectTaxonomyV1.version,
        'canonical_object_id': canonicalId,
        'object_group': _groupFor(canonicalId),
        'object_coverage': E1ObjectCoverage.specialistRequired.wireValue,
        'specialist_observation': true,
        'persistent_tracking_available': false,
        'observable_behaviour_only': true,
      },
    );
  }

  String _eventId({
    required String sessionId,
    required E1SmallObjectSpecialistObservation observation,
    required int observationIndex,
  }) {
    final source = observation.sourceFrameId?.toString() ?? 'no-frame';
    return '$sessionId:e1-specialist:$source:${observation.captureTimestampNs}:${observation.canonicalObjectId}:$observationIndex';
  }

  String _regionFor(Map<String, double> box) {
    final centerX = box['x']! + box['width']! * 0.5;
    final centerY = box['y']! + box['height']! * 0.5;
    final vertical = centerY < 0.33
        ? 'upper'
        : centerY > 0.67
        ? 'lower'
        : 'middle';
    final horizontal = centerX < 0.33
        ? 'left'
        : centerX > 0.67
        ? 'right'
        : 'center';
    return '${vertical}_$horizontal';
  }

  String _groupFor(String canonicalId) {
    switch (canonicalId) {
      case 'smartwatch':
        return 'wearable_screen';
      case 'earbud':
        return 'wearable_audio';
      case 'tablet':
        return 'extra_screen';
      case 'paper_note':
        return 'reference_material';
      case 'calculator':
        return 'calculation_device';
      default:
        return 'unknown';
    }
  }
}

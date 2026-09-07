import 'package:flutter_test/flutter_test.dart';
import 'package:students_ui_demo/proctoring_demo/e1_small_object_specialist.dart';
import 'package:students_ui_demo/proctoring_demo/e1_specialist_model_event_adapter.dart';

void main() {
  const adapter = E1SpecialistModelEventAdapter();

  test('preserves specialist provenance in canonical ModelEventV1', () {
    const observation = E1SmallObjectSpecialistObservation(
      canonicalObjectId: 'smartwatch',
      confidence: 0.87,
      boundingBox: <String, double>{
        'x': 0.20,
        'y': 0.30,
        'width': 0.10,
        'height': 0.12,
      },
      modelId: 'e1-wearable-specialist',
      modelVersion: 'candidate-1',
      sourceFrameId: 42,
      captureTimestampNs: 1_000,
      inferenceTimestampNs: 1_140,
    );

    final event = adapter.fromObservation(
      sessionId: 'attempt-001',
      observation: observation,
      quality: 0.8,
    );

    expect(event, isNotNull);
    expect(event!.classId, 'smartwatch');
    expect(event.trackId, isNull);
    expect(event.sourceFrameId, 42);
    expect(event.captureTimestampNs, 1_000);
    expect(event.inferenceTimestampNs, 1_140);
    expect(event.modelId, 'e1-wearable-specialist');
    expect(event.modelVersion, 'candidate-1');
    expect(event.metadata['canonical_object_id'], 'smartwatch');
    expect(event.metadata['object_group'], 'wearable_screen');
    expect(event.metadata['object_coverage'], 'specialist_required');
    expect(event.metadata['specialist_observation'], isTrue);
    expect(event.geometry!.coordinateSpace, 'normalized_frame');
  });

  test('drops invalid or non-specialist observations', () {
    const invalidGeometry = E1SmallObjectSpecialistObservation(
      canonicalObjectId: 'earbud',
      confidence: 0.9,
      boundingBox: <String, double>{
        'x': 0.95,
        'y': 0.20,
        'width': 0.20,
        'height': 0.10,
      },
      modelId: 'e1-wearable-specialist',
      modelVersion: 'candidate-1',
      sourceFrameId: 1,
      captureTimestampNs: 10,
      inferenceTimestampNs: 11,
    );
    const baseClass = E1SmallObjectSpecialistObservation(
      canonicalObjectId: 'phone',
      confidence: 0.9,
      boundingBox: <String, double>{
        'x': 0.10,
        'y': 0.20,
        'width': 0.20,
        'height': 0.10,
      },
      modelId: 'specialist',
      modelVersion: '1',
      sourceFrameId: 1,
      captureTimestampNs: 10,
      inferenceTimestampNs: 11,
    );

    expect(
      adapter.fromObservation(
        sessionId: 'attempt-001',
        observation: invalidGeometry,
      ),
      isNull,
    );
    expect(
      adapter.fromObservation(
        sessionId: 'attempt-001',
        observation: baseClass,
      ),
      isNull,
    );
    expect(
      adapter.fromObservation(sessionId: '', observation: invalidGeometry),
      isNull,
    );
  });
}

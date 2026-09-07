import 'package:flutter_test/flutter_test.dart';
import 'package:students_ui_demo/proctoring_demo/e1_model_event_memory_coordinator.dart';
import 'package:students_ui_demo/proctoring_demo/e1_small_object_specialist.dart';
import 'package:students_ui_demo/proctoring_demo/model_event_v1.dart';

class _RecordingSink implements ModelEventMemorySink {
  final List<ModelEventV1Payload> events = <ModelEventV1Payload>[];

  @override
  Future<void> ingest(ModelEventV1Payload event) async {
    events.add(event);
  }

  @override
  Future<void> clearSession(String sessionId) async {}
}

void main() {
  test('ingests only validated specialist observations through shared sink', () async {
    final sink = _RecordingSink();
    final coordinator = E1ModelEventMemoryCoordinator(sink: sink);

    const valid = E1SmallObjectSpecialistObservation(
      canonicalObjectId: 'calculator',
      confidence: 0.84,
      boundingBox: <String, double>{
        'x': 0.25,
        'y': 0.55,
        'width': 0.15,
        'height': 0.12,
      },
      modelId: 'e1-desk-small-object-specialist',
      modelVersion: 'candidate-1',
      sourceFrameId: 7,
      captureTimestampNs: 700,
      inferenceTimestampNs: 760,
    );
    const invalid = E1SmallObjectSpecialistObservation(
      canonicalObjectId: 'earbud',
      confidence: 1.4,
      boundingBox: <String, double>{
        'x': 0.20,
        'y': 0.20,
        'width': 0.10,
        'height': 0.10,
      },
      modelId: 'e1-wearable-specialist',
      modelVersion: 'candidate-1',
      sourceFrameId: 7,
      captureTimestampNs: 700,
      inferenceTimestampNs: 760,
    );

    final summary = await coordinator.ingestSpecialistObservations(
      sessionId: 'attempt-001',
      observations: const <E1SmallObjectSpecialistObservation>[valid, invalid],
    );

    expect(summary.produced, 1);
    expect(summary.ingested, 1);
    expect(summary.failed, 0);
    expect(sink.events, hasLength(1));
    expect(sink.events.single.classId, 'calculator');
    expect(sink.events.single.metadata['specialist_observation'], isTrue);
  });

  test('empty session cannot write specialist evidence', () async {
    final sink = _RecordingSink();
    final coordinator = E1ModelEventMemoryCoordinator(sink: sink);

    const valid = E1SmallObjectSpecialistObservation(
      canonicalObjectId: 'tablet',
      confidence: 0.80,
      boundingBox: <String, double>{
        'x': 0.10,
        'y': 0.10,
        'width': 0.20,
        'height': 0.20,
      },
      modelId: 'e1-desk-small-object-specialist',
      modelVersion: 'candidate-1',
      sourceFrameId: 1,
      captureTimestampNs: 10,
      inferenceTimestampNs: 20,
    );

    final summary = await coordinator.ingestSpecialistObservations(
      sessionId: '   ',
      observations: const <E1SmallObjectSpecialistObservation>[valid],
    );

    expect(summary.produced, 0);
    expect(sink.events, isEmpty);
  });
}

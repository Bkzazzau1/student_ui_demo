import 'package:flutter_test/flutter_test.dart';
import 'package:students_ui_demo/proctoring_demo/e1_model_event_memory_coordinator.dart';
import 'package:students_ui_demo/proctoring_demo/model_event_v1.dart';
import 'package:students_ui_demo/proctoring_demo/optimized_vision_object_event_adapter.dart';
import 'package:students_ui_demo/proctoring_demo/optimized_vision_runtime_bridge.dart';

class _FakeAdapter extends OptimizedVisionObjectEventAdapter {
  const _FakeAdapter(this.events);

  final List<ModelEventV1Payload> events;

  @override
  List<ModelEventV1Payload> mapModelEvents(
    OptimizedVisionRuntimeResult result, {
    required String sessionId,
    double? quality,
  }) => events;
}

class _FakeSink implements ModelEventMemorySink {
  _FakeSink({this.failEventId});

  final String? failEventId;
  final List<ModelEventV1Payload> stored = <ModelEventV1Payload>[];
  final List<String> cleared = <String>[];

  @override
  Future<void> ingest(ModelEventV1Payload event) async {
    if (event.eventId == failEventId) {
      throw StateError('simulated native memory failure');
    }
    stored.add(event);
  }

  @override
  Future<void> clearSession(String sessionId) async {
    cleared.add(sessionId);
  }
}

ModelEventV1Payload _event(String eventId, String classId) {
  return ModelEventV1Payload(
    sessionId: 'attempt-001',
    eventId: eventId,
    sourceFrameId: 1,
    captureTimestampNs: 100,
    inferenceTimestampNs: 110,
    modelId: 'e1-yolo-exam-review',
    modelVersion: 'development-baseline-1',
    trackId: null,
    classId: classId,
    confidence: classId == 'person_count' ? null : 0.9,
    quality: 0.8,
    geometry: null,
    validityInterval: const ModelEventValidityIntervalV1(
      startTimestampNs: 100,
      endTimestampNs: 100,
    ),
    metadata: const <String, Object?>{'modality': 'vision'},
  );
}

const _runtime = OptimizedVisionRuntimeResult(
  available: true,
  backend: 'onnxRuntimeDirectML',
  precision: 'fp16',
  inferenceMs: 7.5,
  outputs: <String, Object?>{},
  sourceFrameId: 1,
  captureTimestampNs: 100,
  inferenceTimestampNs: 110,
  modelId: 'e1-yolo-exam-review',
  modelVersion: 'development-baseline-1',
  imageWidth: 640,
  imageHeight: 480,
);

void main() {
  test('ingests every formal observation without calculating policy', () async {
    final sink = _FakeSink();
    final coordinator = E1ModelEventMemoryCoordinator(
      sink: sink,
      adapter: _FakeAdapter(<ModelEventV1Payload>[
        _event('person-1', 'person'),
        _event('count-1', 'person_count'),
      ]),
    );

    final summary = await coordinator.ingestVisionResult(
      result: _runtime,
      sessionId: 'attempt-001',
    );

    expect(summary.produced, 2);
    expect(summary.ingested, 2);
    expect(summary.failed, 0);
    expect(summary.allStored, isTrue);
    expect(sink.stored.map((event) => event.classId), <String>[
      'person',
      'person_count',
    ]);
  });

  test('contains one failed native write and continues remaining events', () async {
    final sink = _FakeSink(failEventId: 'person-1');
    final coordinator = E1ModelEventMemoryCoordinator(
      sink: sink,
      adapter: _FakeAdapter(<ModelEventV1Payload>[
        _event('person-1', 'person'),
        _event('count-1', 'person_count'),
      ]),
    );

    final summary = await coordinator.ingestVisionResult(
      result: _runtime,
      sessionId: 'attempt-001',
    );

    expect(summary.produced, 2);
    expect(summary.ingested, 1);
    expect(summary.failed, 1);
    expect(sink.stored.single.eventId, 'count-1');
  });

  test('does not touch native memory when no formal events are produced', () async {
    final sink = _FakeSink();
    final coordinator = E1ModelEventMemoryCoordinator(
      sink: sink,
      adapter: const _FakeAdapter(<ModelEventV1Payload>[]),
    );

    final summary = await coordinator.ingestVisionResult(
      result: _runtime,
      sessionId: 'attempt-001',
    );

    expect(summary.produced, 0);
    expect(summary.ingested, 0);
    expect(summary.failed, 0);
    expect(sink.stored, isEmpty);
  });

  test('clears only a non-empty session and contains clear failures', () async {
    final sink = _FakeSink();
    final coordinator = E1ModelEventMemoryCoordinator(
      sink: sink,
      adapter: const _FakeAdapter(<ModelEventV1Payload>[]),
    );

    expect(await coordinator.clearSession('   '), isFalse);
    expect(await coordinator.clearSession('attempt-001'), isTrue);
    expect(sink.cleared, <String>['attempt-001']);
  });
}

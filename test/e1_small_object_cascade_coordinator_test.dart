import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:students_ui_demo/proctoring_demo/e1_small_object_cascade_coordinator.dart';
import 'package:students_ui_demo/proctoring_demo/e1_small_object_specialist.dart';
import 'package:students_ui_demo/proctoring_demo/e1_small_object_specialist_runtime.dart';
import 'package:students_ui_demo/proctoring_demo/e1_specialist_frame.dart';
import 'package:students_ui_demo/proctoring_demo/optimized_vision_runtime_bridge.dart';

class _FakeSpecialistRuntime implements E1SmallObjectSpecialistRuntime {
  int calls = 0;

  @override
  Future<List<E1SmallObjectSpecialistObservation>> infer({
    required E1SmallObjectSpecialistRequest request,
    required E1SpecialistFrameInput frame,
  }) async {
    calls++;
    if (request.targets.contains(E1SmallObjectTarget.smartwatch)) {
      return <E1SmallObjectSpecialistObservation>[
        E1SmallObjectSpecialistObservation(
          canonicalObjectId: 'smartwatch',
          confidence: 0.88,
          boundingBox: const <String, double>{
            'x': 0.1,
            'y': 0.1,
            'width': 0.2,
            'height': 0.2,
          },
          modelId: 'specialist-test',
          modelVersion: '1',
          sourceFrameId: request.sourceFrameId,
          captureTimestampNs: request.captureTimestampNs,
          inferenceTimestampNs: request.captureTimestampNs + 10,
        ),
        // Valid on its own, but intentionally detached from this request. The
        // cascade must drop it before evidence ingestion.
        E1SmallObjectSpecialistObservation(
          canonicalObjectId: 'earbud',
          confidence: 0.9,
          boundingBox: const <String, double>{
            'x': 0.2,
            'y': 0.2,
            'width': 0.1,
            'height': 0.1,
          },
          modelId: 'specialist-test',
          modelVersion: '1',
          sourceFrameId: 999,
          captureTimestampNs: request.captureTimestampNs,
          inferenceTimestampNs: request.captureTimestampNs + 10,
        ),
      ];
    }
    if (request.targets.contains(E1SmallObjectTarget.calculator)) {
      return <E1SmallObjectSpecialistObservation>[
        E1SmallObjectSpecialistObservation(
          canonicalObjectId: 'calculator',
          confidence: 0.82,
          boundingBox: const <String, double>{
            'x': 0.5,
            'y': 0.5,
            'width': 0.2,
            'height': 0.2,
          },
          modelId: 'specialist-test',
          modelVersion: '1',
          sourceFrameId: request.sourceFrameId,
          captureTimestampNs: request.captureTimestampNs,
          inferenceTimestampNs: request.captureTimestampNs + 12,
        ),
      ];
    }
    return const <E1SmallObjectSpecialistObservation>[];
  }
}

E1SpecialistFrameInput _frame({
  int sourceFrameId = 7,
  int captureTimestampNs = 1000,
}) {
  return E1SpecialistFrameInput(
    format: 'rgb888',
    width: 4,
    height: 4,
    sourceFrameId: sourceFrameId,
    captureTimestampNs: captureTimestampNs,
    planes: <E1SpecialistFramePlane>[
      E1SpecialistFramePlane(
        bytes: Uint8List(4 * 4 * 3),
        bytesPerRow: 12,
        bytesPerPixel: 3,
        width: 4,
        height: 4,
      ),
    ],
  );
}

OptimizedVisionRuntimeResult _baseResult({
  int sourceFrameId = 7,
  int captureTimestampNs = 1000,
}) {
  return OptimizedVisionRuntimeResult(
    available: true,
    backend: 'onnxRuntimeCpu',
    precision: 'int8',
    inferenceMs: 4.0,
    outputs: <String, Object?>{
      'objects': <Map<String, Object?>>[
        <String, Object?>{'label': 'person', 'confidence': 0.9},
        <String, Object?>{'label': 'book', 'confidence': 0.8},
      ],
    },
    sourceFrameId: sourceFrameId,
    captureTimestampNs: captureTimestampNs,
    inferenceTimestampNs: captureTimestampNs + 20,
    modelId: 'base-e1',
    modelVersion: '1',
    imageWidth: 4,
    imageHeight: 4,
  );
}

void main() {
  test(
    'planner requests are not evidence; only matching observations ingest',
    () async {
      final runtime = _FakeSpecialistRuntime();
      final ingested = <E1SmallObjectSpecialistObservation>[];
      final cascade = E1SmallObjectCascadeCoordinator(
        runtime: runtime,
        ingestObservations: (observations) async {
          final accepted = observations.toList(growable: false);
          ingested.addAll(accepted);
          return (ingested: accepted.length, failed: 0);
        },
      );

      final summary = await cascade.run(
        sessionId: 'attempt-1',
        baseResult: _baseResult(),
        frame: _frame(),
      );

      expect(summary.requestsPlanned, 2);
      expect(summary.requestsExecuted, 2);
      expect(runtime.calls, 2);
      expect(summary.observationsAccepted, 2);
      expect(summary.eventsIngested, 2);
      expect(summary.ingestFailures, 0);
      expect(
        ingested.map((item) => item.canonicalObjectId).toSet(),
        equals(<String>{'smartwatch', 'calculator'}),
      );
      expect(ingested.every((item) => item.sourceFrameId == 7), isTrue);
    },
  );

  test(
    'base/frame provenance mismatch prevents specialist execution',
    () async {
      final runtime = _FakeSpecialistRuntime();
      var ingestorCalls = 0;
      final cascade = E1SmallObjectCascadeCoordinator(
        runtime: runtime,
        ingestObservations: (observations) async {
          ingestorCalls++;
          return (ingested: observations.length, failed: 0);
        },
      );

      final summary = await cascade.run(
        sessionId: 'attempt-1',
        baseResult: _baseResult(),
        frame: _frame(sourceFrameId: 8),
      );

      expect(summary.requestsPlanned, 0);
      expect(summary.requestsExecuted, 0);
      expect(summary.observationsAccepted, 0);
      expect(runtime.calls, 0);
      expect(ingestorCalls, 0);
    },
  );

  test('empty specialist output cannot become evidence', () async {
    final runtime = const UnavailableE1SmallObjectSpecialistRuntime();
    var ingestorCalls = 0;
    final cascade = E1SmallObjectCascadeCoordinator(
      runtime: runtime,
      ingestObservations: (observations) async {
        ingestorCalls++;
        return (ingested: observations.length, failed: 0);
      },
    );

    final summary = await cascade.run(
      sessionId: 'attempt-1',
      baseResult: _baseResult(),
      frame: _frame(),
    );

    expect(summary.requestsPlanned, 2);
    expect(summary.requestsExecuted, 2);
    expect(summary.observationsAccepted, 0);
    expect(summary.eventsIngested, 0);
    expect(ingestorCalls, 0);
  });
}

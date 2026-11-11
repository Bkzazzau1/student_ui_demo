import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:students_ui_demo/proctoring_demo/e1_small_object_cascade_coordinator.dart';
import 'package:students_ui_demo/proctoring_demo/e1_small_object_specialist.dart';
import 'package:students_ui_demo/proctoring_demo/e1_small_object_specialist_runtime.dart';
import 'package:students_ui_demo/proctoring_demo/e1_specialist_execution_budget.dart';
import 'package:students_ui_demo/proctoring_demo/e1_specialist_frame.dart';
import 'package:students_ui_demo/proctoring_demo/model_event_v1.dart';
import 'package:students_ui_demo/proctoring_demo/optimized_vision_runtime_bridge.dart';

class _FakeSpecialistRuntime implements E1SmallObjectSpecialistRuntime {
  int calls = 0;

  @override
  Future<List<E1SmallObjectSpecialistObservation>> infer({
    required E1SmallObjectSpecialistRequest request,
    required E1SpecialistFrameInput frame,
  }) async {
    calls++;
    if (request.targets.contains(E1SmallObjectTarget.wristDevice)) {
      return <E1SmallObjectSpecialistObservation>[
        E1SmallObjectSpecialistObservation(
          canonicalObjectId: 'wrist_device',
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

E1SpecialistExecutionBudget _unthrottledBudget() => E1SpecialistExecutionBudget(
  minCaptureIntervalNs: 0,
  maxRequestsPerFrame: 3,
);

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
    outputs: const <String, Object?>{},
    sourceFrameId: sourceFrameId,
    captureTimestampNs: captureTimestampNs,
    inferenceTimestampNs: captureTimestampNs + 20,
    modelId: 'base-e1',
    modelVersion: '1',
    imageWidth: 4,
    imageHeight: 4,
  );
}

ModelEventV1Payload _baseEvent({
  required String canonicalObjectId,
  required Map<String, Object?> box,
  int sourceFrameId = 7,
  int captureTimestampNs = 1000,
}) {
  return ModelEventV1Payload(
    sessionId: 'attempt-1',
    eventId: 'attempt-1:$canonicalObjectId:$sourceFrameId',
    sourceFrameId: sourceFrameId,
    captureTimestampNs: captureTimestampNs,
    inferenceTimestampNs: captureTimestampNs + 20,
    modelId: 'base-e1',
    modelVersion: '1',
    trackId: null,
    classId: canonicalObjectId,
    confidence: 0.9,
    quality: null,
    geometry: ModelEventGeometryV1(
      coordinateSpace: 'normalized_frame',
      boundingBox: box,
    ),
    validityInterval: ModelEventValidityIntervalV1(
      startTimestampNs: captureTimestampNs,
      endTimestampNs: captureTimestampNs,
    ),
    metadata: <String, Object?>{
      'canonical_object_id': canonicalObjectId,
      'modality': 'vision',
    },
  );
}

List<ModelEventV1Payload> _baseEvents() {
  return <ModelEventV1Payload>[
    _baseEvent(
      canonicalObjectId: 'person',
      box: const <String, Object?>{
        'x': 0.2,
        'y': 0.05,
        'width': 0.5,
        'height': 0.9,
      },
    ),
    _baseEvent(
      canonicalObjectId: 'book',
      box: const <String, Object?>{
        'x': 0.25,
        'y': 0.65,
        'width': 0.25,
        'height': 0.2,
      },
    ),
  ];
}

void main() {
  test(
    'planner requests are not evidence; only matching observations ingest',
    () async {
      final runtime = _FakeSpecialistRuntime();
      final ingested = <E1SmallObjectSpecialistObservation>[];
      final cascade = E1SmallObjectCascadeCoordinator(
        runtime: runtime,
        executionBudget: _unthrottledBudget(),
        ingestObservations: (observations) async {
          final accepted = observations.toList(growable: false);
          ingested.addAll(accepted);
          return (ingested: accepted.length, failed: 0);
        },
      );

      final summary = await cascade.run(
        sessionId: 'attempt-1',
        baseResult: _baseResult(),
        baseEvents: _baseEvents(),
        frame: _frame(),
      );

      expect(summary.requestsPlanned, 3);
      expect(summary.requestsScheduled, 3);
      expect(summary.requestsBudgetSkipped, 0);
      expect(summary.requestsExecuted, 3);
      expect(runtime.calls, 3);
      expect(summary.observationsAccepted, 2);
      expect(summary.eventsIngested, 2);
      expect(summary.ingestFailures, 0);
      expect(
        ingested.map((item) => item.canonicalObjectId).toSet(),
        equals(<String>{'wrist_device', 'calculator'}),
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
        executionBudget: _unthrottledBudget(),
        ingestObservations: (observations) async {
          ingestorCalls++;
          return (ingested: observations.length, failed: 0);
        },
      );

      final summary = await cascade.run(
        sessionId: 'attempt-1',
        baseResult: _baseResult(),
        baseEvents: _baseEvents(),
        frame: _frame(sourceFrameId: 8),
      );

      expect(summary.requestsPlanned, 0);
      expect(summary.requestsScheduled, 0);
      expect(summary.requestsBudgetSkipped, 0);
      expect(summary.requestsExecuted, 0);
      expect(runtime.calls, 0);
      expect(ingestorCalls, 0);
    },
  );

  test('missing formal geometry prevents specialist execution', () async {
    final runtime = _FakeSpecialistRuntime();
    var ingestorCalls = 0;
    final cascade = E1SmallObjectCascadeCoordinator(
      runtime: runtime,
      executionBudget: _unthrottledBudget(),
      ingestObservations: (observations) async {
        ingestorCalls++;
        return (ingested: observations.length, failed: 0);
      },
    );

    final summary = await cascade.run(
      sessionId: 'attempt-1',
      baseResult: _baseResult(),
      baseEvents: const <ModelEventV1Payload>[],
      frame: _frame(),
    );

    expect(summary.requestsPlanned, 0);
    expect(summary.requestsScheduled, 0);
    expect(summary.requestsExecuted, 0);
    expect(runtime.calls, 0);
    expect(ingestorCalls, 0);
  });

  test('empty specialist output cannot become evidence', () async {
    final runtime = const UnavailableE1SmallObjectSpecialistRuntime();
    var ingestorCalls = 0;
    final cascade = E1SmallObjectCascadeCoordinator(
      runtime: runtime,
      executionBudget: _unthrottledBudget(),
      ingestObservations: (observations) async {
        ingestorCalls++;
        return (ingested: observations.length, failed: 0);
      },
    );

    final summary = await cascade.run(
      sessionId: 'attempt-1',
      baseResult: _baseResult(),
      baseEvents: _baseEvents(),
      frame: _frame(),
    );

    expect(summary.requestsPlanned, 3);
    expect(summary.requestsScheduled, 3);
    expect(summary.requestsBudgetSkipped, 0);
    expect(summary.requestsExecuted, 3);
    expect(summary.observationsAccepted, 0);
    expect(summary.eventsIngested, 0);
    expect(ingestorCalls, 0);
  });

  test(
    'budget-skipped requests remain unobserved and create no evidence',
    () async {
      final runtime = _FakeSpecialistRuntime();
      var ingestorCalls = 0;
      final cascade = E1SmallObjectCascadeCoordinator(
        runtime: runtime,
        executionBudget: E1SpecialistExecutionBudget(
          minCaptureIntervalNs: 0,
          maxRequestsPerFrame: 1,
        ),
        ingestObservations: (observations) async {
          ingestorCalls++;
          return (ingested: observations.length, failed: 0);
        },
      );

      final summary = await cascade.run(
        sessionId: 'attempt-1',
        baseResult: _baseResult(),
        baseEvents: _baseEvents(),
        frame: _frame(),
      );

      expect(summary.requestsPlanned, 3);
      expect(summary.requestsScheduled, 1);
      expect(summary.requestsBudgetSkipped, 2);
      expect(summary.requestsExecuted, 1);
      expect(summary.observationsAccepted, 0);
      expect(summary.eventsIngested, 0);
      expect(runtime.calls, 1);
      expect(ingestorCalls, 0);
    },
  );
}

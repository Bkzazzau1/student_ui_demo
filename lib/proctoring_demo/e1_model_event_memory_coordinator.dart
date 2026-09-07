import 'e1_small_object_cascade_coordinator.dart';
import 'e1_small_object_specialist.dart';
import 'e1_small_object_specialist_runtime_bridge.dart';
import 'e1_specialist_frame.dart';
import 'e1_specialist_model_event_adapter.dart';
import 'live_camera_frame_bus.dart';
import 'model_event_v1.dart';
import 'optimized_vision_object_event_adapter.dart';
import 'optimized_vision_runtime_bridge.dart';

abstract interface class ModelEventMemorySink {
  Future<void> ingest(ModelEventV1Payload event);

  Future<void> clearSession(String sessionId);
}

class E1ModelEventMemoryIngestSummary {
  const E1ModelEventMemoryIngestSummary({
    required this.produced,
    required this.ingested,
    required this.failed,
  });

  final int produced;
  final int ingested;
  final int failed;

  bool get hadFormalEvents => produced > 0;
  bool get allStored => produced > 0 && failed == 0 && ingested == produced;
}

/// Sends frozen E1 observations to Rust-owned model-event memory.
///
/// This layer does not calculate risk, severity, persistence, or policy. Its
/// only job is evidence transport. Individual native-memory failures are
/// contained so an observability fault cannot crash the live exam UI.
class E1ModelEventMemoryCoordinator {
  const E1ModelEventMemoryCoordinator({
    required this.sink,
    this.adapter = const OptimizedVisionObjectEventAdapter(),
    this.specialistAdapter = const E1SpecialistModelEventAdapter(),
  });

  static final E1SmallObjectSpecialistRuntimeBridge _liveSpecialistRuntime =
      E1SmallObjectSpecialistRuntimeBridge();

  final ModelEventMemorySink sink;
  final OptimizedVisionObjectEventAdapter adapter;
  final E1SpecialistModelEventAdapter specialistAdapter;

  Future<E1ModelEventMemoryIngestSummary> ingestVisionResult({
    required OptimizedVisionRuntimeResult result,
    required String sessionId,
    double? quality,
  }) async {
    final events = adapter.mapModelEvents(
      result,
      sessionId: sessionId,
      quality: quality,
    );
    final baseSummary = await _ingestEvents(events);

    // The live specialist path is deliberately evidence-neutral when no
    // validated specialist model is installed. It may only inspect the exact
    // camera frame and formal geometry that produced this base result.
    await _runLiveSpecialistCascade(
      result: result,
      sessionId: sessionId,
      baseEvents: events,
    );

    return baseSummary;
  }

  Future<void> _runLiveSpecialistCascade({
    required OptimizedVisionRuntimeResult result,
    required String sessionId,
    required Iterable<ModelEventV1Payload> baseEvents,
  }) async {
    if (sessionId.trim().isEmpty ||
        !result.available ||
        !result.hasModelEventProvenance) {
      return;
    }

    final liveFrame = LiveCameraFrameBus.instance.frameForSequence(
      result.sourceFrameId,
    );
    if (liveFrame == null ||
        liveFrame.captureTimestampNs != result.captureTimestampNs ||
        liveFrame.width != result.imageWidth ||
        liveFrame.height != result.imageHeight) {
      return;
    }

    final image = liveFrame.image;
    final frame = E1SpecialistFrameInput(
      format: liveFrame.formatGroup,
      width: liveFrame.width,
      height: liveFrame.height,
      sourceFrameId: liveFrame.sequence,
      captureTimestampNs: liveFrame.captureTimestampNs,
      planes: image.planes
          .map(
            (plane) => E1SpecialistFramePlane(
              bytes: plane.bytes,
              bytesPerRow: plane.bytesPerRow,
              bytesPerPixel: plane.bytesPerPixel ?? 1,
              // Camera backends may omit per-plane dimensions. Keep that
              // evidence UNKNOWN by using the invalid sentinel 0; the frame
              // contract will then skip specialist inference rather than
              // substituting full-frame dimensions.
              width: plane.width ?? 0,
              height: plane.height ?? 0,
            ),
          )
          .toList(growable: false),
    );
    if (!frame.isValid) return;

    final cascade = E1SmallObjectCascadeCoordinator(
      runtime: _liveSpecialistRuntime,
      ingestObservations: (observations) async {
        final summary = await ingestSpecialistObservations(
          sessionId: sessionId,
          observations: observations,
        );
        return (ingested: summary.ingested, failed: summary.failed);
      },
    );

    try {
      await cascade.run(
        sessionId: sessionId,
        baseResult: result,
        baseEvents: baseEvents,
        frame: frame,
      );
    } catch (_) {
      // Specialist observability must never crash or block base E1 evidence.
    }
  }

  Future<E1ModelEventMemoryIngestSummary> ingestSpecialistObservations({
    required String sessionId,
    required Iterable<E1SmallObjectSpecialistObservation> observations,
    double? quality,
  }) async {
    if (sessionId.trim().isEmpty) {
      return const E1ModelEventMemoryIngestSummary(
        produced: 0,
        ingested: 0,
        failed: 0,
      );
    }

    final events = <ModelEventV1Payload>[];
    var index = 0;
    for (final observation in observations) {
      final event = specialistAdapter.fromObservation(
        sessionId: sessionId,
        observation: observation,
        quality: quality,
        observationIndex: index,
      );
      index++;
      if (event != null) events.add(event);
    }
    return _ingestEvents(events);
  }

  Future<E1ModelEventMemoryIngestSummary> _ingestEvents(
    Iterable<ModelEventV1Payload> events,
  ) async {
    final materialized = events.toList(growable: false);
    if (materialized.isEmpty) {
      return const E1ModelEventMemoryIngestSummary(
        produced: 0,
        ingested: 0,
        failed: 0,
      );
    }

    var ingested = 0;
    var failed = 0;
    for (final event in materialized) {
      try {
        await sink.ingest(event);
        ingested++;
      } catch (_) {
        failed++;
      }
    }

    return E1ModelEventMemoryIngestSummary(
      produced: materialized.length,
      ingested: ingested,
      failed: failed,
    );
  }

  Future<bool> clearSession(String sessionId) async {
    if (sessionId.trim().isEmpty) return false;
    try {
      await sink.clearSession(sessionId);
      return true;
    } catch (_) {
      return false;
    }
  }
}

import 'e1_small_object_specialist.dart';
import 'e1_small_object_specialist_runtime.dart';
import 'e1_specialist_frame.dart';
import 'optimized_vision_object_event_adapter.dart';
import 'optimized_vision_runtime_bridge.dart';

typedef E1SpecialistObservationIngestor =
    Future<({int ingested, int failed})> Function(
      Iterable<E1SmallObjectSpecialistObservation> observations,
    );

class E1SmallObjectCascadeSummary {
  const E1SmallObjectCascadeSummary({
    required this.requestsPlanned,
    required this.requestsExecuted,
    required this.observationsAccepted,
    required this.eventsIngested,
    required this.ingestFailures,
  });

  final int requestsPlanned;
  final int requestsExecuted;
  final int observationsAccepted;
  final int eventsIngested;
  final int ingestFailures;
}

/// Runs specialist inference only from real E1 frame provenance and sends only
/// validated specialist observations into the caller-owned evidence sink.
///
/// The coordinator never creates evidence from a planner request. A request is
/// merely a routing decision; only a validated local specialist observation can
/// become a ModelEventV1 downstream.
class E1SmallObjectCascadeCoordinator {
  const E1SmallObjectCascadeCoordinator({
    required this.runtime,
    required this.ingestObservations,
    this.planner = const E1SmallObjectCascadePlanner(),
    this.guard = const E1SpecialistRuntimeGuard(),
    this.baseAdapter = const OptimizedVisionObjectEventAdapter(),
  });

  final E1SmallObjectSpecialistRuntime runtime;
  final E1SpecialistObservationIngestor ingestObservations;
  final E1SmallObjectCascadePlanner planner;
  final E1SpecialistRuntimeGuard guard;
  final OptimizedVisionObjectEventAdapter baseAdapter;

  Future<E1SmallObjectCascadeSummary> run({
    required String sessionId,
    required OptimizedVisionRuntimeResult baseResult,
    required E1SpecialistFrameInput frame,
  }) async {
    if (sessionId.trim().isEmpty ||
        !baseResult.available ||
        !baseResult.hasModelEventProvenance ||
        !frame.isValid ||
        frame.sourceFrameId != baseResult.sourceFrameId ||
        frame.captureTimestampNs != baseResult.captureTimestampNs ||
        frame.width != baseResult.imageWidth ||
        frame.height != baseResult.imageHeight) {
      return const E1SmallObjectCascadeSummary(
        requestsPlanned: 0,
        requestsExecuted: 0,
        observationsAccepted: 0,
        eventsIngested: 0,
        ingestFailures: 0,
      );
    }

    final baseLabels = baseAdapter.extractObjectLabels(baseResult.outputs);
    final requests = planner.plan(
      sessionId: sessionId,
      sourceFrameId: baseResult.sourceFrameId,
      captureTimestampNs: baseResult.captureTimestampNs!,
      imageWidth: baseResult.imageWidth,
      imageHeight: baseResult.imageHeight,
      baseLabels: baseLabels,
    );

    var requestsExecuted = 0;
    var observationsAccepted = 0;
    var eventsIngested = 0;
    var ingestFailures = 0;

    for (final request in requests) {
      if (!guard.canInfer(request: request, frame: frame)) continue;
      requestsExecuted++;
      List<E1SmallObjectSpecialistObservation> raw;
      try {
        raw = await runtime.infer(request: request, frame: frame);
      } catch (_) {
        continue;
      }

      final accepted = guard
          .retainValidObservations(raw)
          .where((observation) => _matchesRequest(observation, request))
          .toList(growable: false);
      if (accepted.isEmpty) continue;
      observationsAccepted += accepted.length;

      final ingest = await ingestObservations(accepted);
      eventsIngested += ingest.ingested;
      ingestFailures += ingest.failed;
    }

    return E1SmallObjectCascadeSummary(
      requestsPlanned: requests.length,
      requestsExecuted: requestsExecuted,
      observationsAccepted: observationsAccepted,
      eventsIngested: eventsIngested,
      ingestFailures: ingestFailures,
    );
  }

  bool _matchesRequest(
    E1SmallObjectSpecialistObservation observation,
    E1SmallObjectSpecialistRequest request,
  ) {
    return observation.sourceFrameId == request.sourceFrameId &&
        observation.captureTimestampNs == request.captureTimestampNs &&
        request.targets.any(
          (target) => target.canonicalObjectId == observation.canonicalObjectId,
        );
  }
}

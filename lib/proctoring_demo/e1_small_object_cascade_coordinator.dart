import 'e1_small_object_specialist.dart';
import 'e1_small_object_specialist_runtime.dart';
import 'e1_specialist_execution_budget.dart';
import 'e1_specialist_frame.dart';
import 'model_event_v1.dart';
import 'optimized_vision_runtime_bridge.dart';

typedef E1SpecialistObservationIngestor =
    Future<({int ingested, int failed})> Function(
      Iterable<E1SmallObjectSpecialistObservation> observations,
    );

class E1SmallObjectCascadeSummary {
  const E1SmallObjectCascadeSummary({
    required this.requestsPlanned,
    required this.requestsScheduled,
    required this.requestsBudgetSkipped,
    required this.requestsExecuted,
    required this.observationsAccepted,
    required this.eventsIngested,
    required this.ingestFailures,
  });

  final int requestsPlanned;
  final int requestsScheduled;
  final int requestsBudgetSkipped;
  final int requestsExecuted;
  final int observationsAccepted;
  final int eventsIngested;
  final int ingestFailures;
}

/// Runs specialist inference only from real E1 frame provenance and formal base
/// detection geometry, then sends only validated observations into evidence.
///
/// The execution budget only controls local compute. A request that is not
/// scheduled remains unobserved/UNKNOWN and is never converted into negative
/// evidence.
class E1SmallObjectCascadeCoordinator {
  E1SmallObjectCascadeCoordinator({
    required this.runtime,
    required this.ingestObservations,
    E1SpecialistExecutionBudget? executionBudget,
    this.planner = const E1SmallObjectCascadePlanner(),
    this.guard = const E1SpecialistRuntimeGuard(),
  }) : executionBudget = executionBudget ?? E1SpecialistExecutionBudget();

  final E1SmallObjectSpecialistRuntime runtime;
  final E1SpecialistObservationIngestor ingestObservations;
  final E1SpecialistExecutionBudget executionBudget;
  final E1SmallObjectCascadePlanner planner;
  final E1SpecialistRuntimeGuard guard;

  Future<E1SmallObjectCascadeSummary> run({
    required String sessionId,
    required OptimizedVisionRuntimeResult baseResult,
    required Iterable<ModelEventV1Payload> baseEvents,
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
        requestsScheduled: 0,
        requestsBudgetSkipped: 0,
        requestsExecuted: 0,
        observationsAccepted: 0,
        eventsIngested: 0,
        ingestFailures: 0,
      );
    }

    final requests = planner.plan(
      sessionId: sessionId,
      sourceFrameId: baseResult.sourceFrameId,
      captureTimestampNs: baseResult.captureTimestampNs!,
      imageWidth: baseResult.imageWidth,
      imageHeight: baseResult.imageHeight,
      baseEvents: baseEvents,
    );
    final scheduledRequests = executionBudget.reserve(
      sessionId: sessionId,
      captureTimestampNs: baseResult.captureTimestampNs!,
      requests: requests,
    );

    var requestsExecuted = 0;
    var observationsAccepted = 0;
    var eventsIngested = 0;
    var ingestFailures = 0;

    try {
      for (final request in scheduledRequests) {
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
    } finally {
      if (scheduledRequests.isNotEmpty) {
        executionBudget.complete(
          sessionId: sessionId,
          captureTimestampNs: baseResult.captureTimestampNs!,
        );
      }
    }

    return E1SmallObjectCascadeSummary(
      requestsPlanned: requests.length,
      requestsScheduled: scheduledRequests.length,
      requestsBudgetSkipped: requests.length - scheduledRequests.length,
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

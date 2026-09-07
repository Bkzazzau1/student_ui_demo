import 'e1_small_object_specialist.dart';
import 'e1_specialist_model_event_adapter.dart';
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
    return _ingestEvents(events);
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

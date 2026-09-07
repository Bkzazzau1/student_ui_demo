import 'dart:convert';

import '../rust/api/model_event_memory.dart' as rust_memory;
import '../rust/brain_core_runtime.dart';
import 'e1_model_event_memory_coordinator.dart';
import 'model_event_v1.dart';

/// Production sink for the frozen ModelEventV1 transport contract.
///
/// Flutter owns only serialization and bridge transport. Rust owns validation,
/// duplicate rejection, persistent person tracking, and spatiotemporal memory.
class NativeModelEventMemorySink implements ModelEventMemorySink {
  const NativeModelEventMemorySink({this.requestedCapacity = 4096});

  final int requestedCapacity;

  @override
  Future<void> ingest(ModelEventV1Payload event) async {
    if (requestedCapacity <= 0) {
      throw const FormatException('requestedCapacity must be positive');
    }
    await BrainCoreRuntime.ensureInitialized();
    rust_memory.ingestModelEventV1Json(
      eventJson: jsonEncode(event.toJson()),
      requestedCapacity: BigInt.from(requestedCapacity),
    );
  }

  @override
  Future<void> clearSession(String sessionId) async {
    final normalized = sessionId.trim();
    if (normalized.isEmpty) {
      throw const FormatException('sessionId must be non-empty');
    }
    await BrainCoreRuntime.ensureInitialized();
    rust_memory.clearModelEventMemoryV1(sessionId: normalized);
  }
}

import 'dart:convert';

import '../rust/api/model_event_memory.dart' as native;
import '../rust/brain_core_runtime.dart';
import 'model_event_v1.dart';

/// Thin integration boundary into Rust-owned spatiotemporal memory.
///
/// This class deliberately does not score, reinterpret, enrich, or normalize
/// model evidence. Producers must create a valid frozen ModelEventV1 payload
/// before calling [ingest]. Rust remains the owner of bounded temporal memory.
class NativeModelEventMemoryBridge {
  Future<void>? _initialization;

  Future<void> _ensureInitialized() {
    return _initialization ??= BrainCoreRuntime.ensureInitialized();
  }

  Future<bool> ingest(ModelEventV1Payload event) async {
    try {
      await _ensureInitialized();
      native.ingestModelEventV1Json(
        eventJson: jsonEncode(event.toJson()),
        requestedCapacity: null,
      );
      return true;
    } catch (_) {
      // Live capture must remain fail-soft while native runtime recovery is
      // handled separately. Do not fabricate a successful memory write.
      return false;
    }
  }

  Future<bool> clear(String sessionId) async {
    if (sessionId.trim().isEmpty) return false;
    try {
      await _ensureInitialized();
      return native.clearModelEventMemoryV1(sessionId: sessionId);
    } catch (_) {
      return false;
    }
  }
}

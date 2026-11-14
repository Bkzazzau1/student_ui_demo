import 'frb_generated.dart';

/// Process-wide, idempotent owner of the Flutter Rust Bridge runtime.
///
/// FRB must be initialized exactly once. Every feature shares this cached
/// future so concurrent startup checks cannot initialize the native library a
/// second time.
abstract final class BrainCoreRuntime {
  static Future<void>? _initialization;
  static bool _ready = false;

  /// True once the runtime has finished initializing, for callers that must
  /// decide synchronously (per camera frame) whether Rust is usable.
  static bool get isReady => _ready;

  static Future<void> ensureInitialized() {
    return _initialization ??= BrainCoreApi.init().then((_) {
      _ready = true;
    });
  }
}

import 'frb_generated.dart';

/// Process-wide, idempotent owner of the Flutter Rust Bridge runtime.
///
/// FRB must be initialized exactly once. Every feature shares this cached
/// future so concurrent startup checks cannot initialize the native library a
/// second time.
abstract final class BrainCoreRuntime {
  static Future<void>? _initialization;

  static Future<void> ensureInitialized() {
    return _initialization ??= BrainCoreApi.init();
  }
}

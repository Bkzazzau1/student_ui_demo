# Native Attempt Recovery Migration

Working branch: `codex/onnx-directml-smoke-inference`.

## Completed

A native Rust recovery/checksum API has been added:

- `native/brain_core/src/api/attempt_recovery.rs`
- `native/brain_core/tests/attempt_recovery_tests.rs`

The module is registered in:

- `native/brain_core/src/api/mod.rs`

## Native API

The native API exposes:

- `attempt_checksum(payload_json)`
- `verify_attempt_snapshot(payload_json, checksum, recovered_from)`

## Why This Exists

The Dart autosave service now uses primary, backup, and legacy recovery records. Native checksum verification gives us a stronger foundation for later moving attempt recovery integrity checks out of Dart.

## Next Dart Step

After running flutter_rust_bridge code generation, add a Dart bridge similar to:

- `lib/proctoring_demo/native_audio_intelligence_bridge.dart`

Then update:

- `lib/exam_demo/secure_attempt_autosave_service.dart`

to try native checksum verification first and keep Dart checksum verification as fallback for one release.

## Validation

```bash
cd native/brain_core
cargo test
flutter_rust_bridge_codegen generate
flutter analyze --no-pub lib/exam_demo/secure_attempt_autosave_service.dart
```

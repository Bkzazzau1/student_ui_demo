# Native Secure Lockdown Migration

Working branch: `codex/onnx-directml-smoke-inference`.

## Goal

Move secure exam lockdown checks out of Dart shell/process code and into the existing Rust native crate:

`native/brain_core/src/api/lockdown.rs`

This is priority two because process scanning, prohibited app detection, and display counting are native security responsibilities.

## Current Native State

`native/brain_core/src/api/lockdown.rs` now defines:

- `NativeLockdownFinding`
- `NativeSecureLockdownReviewResult`
- `analyze_secure_lockdown_report`
- `collect_lockdown_process_report`
- `collect_lockdown_display_count`
- `run_secure_lockdown_review`

The native review checks:

- unsupported platform;
- prohibited remote desktop apps;
- screen recording apps;
- virtual camera apps;
- VM tools;
- messaging/collaboration apps;
- browsers and AI assistant apps;
- multiple displays.

## Module Registration

`native/brain_core/src/api/mod.rs` exports:

- `evidence_vault`
- `lockdown`
- `proctoring`
- `system_security`

## Native Tests

`native/brain_core/tests/lockdown_tests.rs` covers:

- clean lockdown report passes;
- prohibited process detection;
- multiple display blocking;
- unsupported platform rejection.

## Dart Adapter Contract

`lib/proctoring_demo/native_secure_lockdown_review_bridge.dart` defines a non-breaking adapter contract.

It intentionally does not import generated Rust bindings yet because the FRB Dart binding for `lockdown.rs` must be regenerated first.

## Next Step

Regenerate flutter_rust_bridge bindings with explicit paths, then update:

`GeneratedNativeSecureLockdownReviewBridge.check()`

to call:

```dart
final result = await native_lockdown.runSecureLockdownReview(
  platformName: 'auto',
);
```

After that, update `SecureLockdownSessionService.collectSnapshot()` to try native first and fall back to the current Dart process/display implementation for one release.

## Local Test Command

```bash
cd native/brain_core
cargo test
```

## What Remains in Dart

Flutter/Dart should keep:

- session active state;
- clipboard clearing through Flutter services;
- student-safe messages;
- UI cards and live event delivery;
- fallback implementation until native path is stable.

Rust should own:

- process report collection;
- display count collection;
- prohibited app matching;
- native lockdown findings.

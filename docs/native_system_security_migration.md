# Native System Security Migration

Working branch: `codex/onnx-directml-smoke-inference`.

## Goal

Move system/device security review out of Dart and into the existing Rust native crate:

`native/brain_core/src/api/system_security.rs`

This is priority one because system security, connected-device checks, virtualization checks, virtual-camera checks, and platform inspection are native responsibilities.

## Current State

### Native Rust Added

`native/brain_core/src/api/system_security.rs` now defines:

- `NativeSystemSecurityReviewResult`
- `analyze_system_security_report`
- `collect_system_security_report`
- `run_system_security_review`

The Rust module checks:

- Bluetooth or wireless audio
- external audio devices
- USB audio/camera/capture risk
- virtualization indicators
- Windows hypervisor warning
- container, WSL, or sandbox indicators
- virtual camera indicators
- unclear audio device state
- unsupported platforms

### Native Module Registered

`native/brain_core/src/api/mod.rs` now exports:

- `evidence_vault`
- `proctoring`
- `system_security`

### Native Tests Added

`native/brain_core/tests/system_security_tests.rs` checks:

- clean internal audio passes;
- Bluetooth and USB capture risk blocks;
- virtual machine, container, and virtual camera blocks;
- unsupported platforms are rejected.

### Dart Adapter Added

`lib/proctoring_demo/native_system_security_review_bridge.dart` maps native-style results into the current Dart `SystemSecurityReviewResult` shape.

It is intentionally non-breaking. It does not import generated Rust Dart files yet because the generated Dart bindings are not currently present in the repo.

## Important Next Step

Run flutter_rust_bridge codegen so the Dart side can call the Rust function directly.

Expected Rust function to expose:

```rust
run_system_security_review(platform_name: String) -> NativeSystemSecurityReviewResult
```

Expected Dart call after codegen:

```dart
final native = await runSystemSecurityReview(platformName: 'auto');
```

Then update `GeneratedNativeSystemSecurityReviewBridge.check()` to return a `NativeSystemSecurityReviewSnapshot` based on the generated native result.

## Final Migration Step

After bridge wiring is confirmed:

1. Update `SystemSecurityReviewService.check()` to try native Rust first.
2. Keep the existing Dart shell-command review as fallback for one release.
3. After stable testing, remove Dart shell-command logic.
4. Keep UI messages and policy decisions in Dart.
5. Keep OS/device collection, analysis, and evidence metadata in Rust.

## Local Test Command

```bash
cd native/brain_core
cargo test
```

## Why This Matters

Dart should not be responsible for deep system inspection. Rust native code gives us a stronger and more defensible examination security layer for institutional pilots.

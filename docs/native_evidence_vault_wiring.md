# Native Evidence Vault Wiring

Working branch: `codex/onnx-directml-smoke-inference`.

## Goal

Use the Rust native evidence vault first, while keeping the existing Dart file-writing implementation as fallback.

## Native API

The generated binding already exposes:

- `evidenceSha256Hex`
- `saveEvidenceBytes`
- `readEvidenceBundle`

from:

`native/brain_core/src/api/evidence_vault.rs`

## Dart Bridge

`lib/proctoring_demo/native_evidence_vault_bridge.dart` wraps the generated Rust binding and handles `BrainCoreApi.init()`.

If Rust initialization or native save/read fails, the bridge returns `null` so the Dart service can use its fallback path.

## Service Wiring

`lib/proctoring_demo/local_evidence_vault_service.dart` now:

1. tries native Rust `saveEvidenceBytes` before writing files in Dart;
2. tries native Rust `readEvidenceBundle` before reading the manifest in Dart;
3. parses both native Rust manifest fields and Dart fallback manifest fields;
4. supports Rust `created_at_ms` and Dart `created_at`;
5. supports Rust `metadata_json` and Dart `metadata`.

## Fallback Policy

The Dart vault remains active as fallback for one release. This prevents evidence loss if the native library is not packaged or initialized correctly on a particular desktop device.

## Local Validation

Recommended checks:

```bash
flutter analyze --no-pub lib/proctoring_demo/native_evidence_vault_bridge.dart lib/proctoring_demo/local_evidence_vault_service.dart
cd native/brain_core
cargo test
```

## Next Evidence Step

Attach this vault to live monitoring events so serious events create actual evidence records instead of only event metadata.

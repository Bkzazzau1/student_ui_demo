# Native Audio Intelligence Migration

Working branch: `codex/onnx-directml-smoke-inference`.

## Goal

Move the heavy PCM audio fingerprint and voice/ambient classification foundation from Dart toward Rust native code.

## Native API Added

`native/brain_core/src/api/audio_intelligence.rs` defines:

- `NativeAudioIntelligenceResult`
- `analyze_audio_pcm16`

The native result includes:

- readiness;
- label;
- RMS;
- peak;
- zero crossing rate;
- dynamic variation;
- voice confidence;
- near voice flag;
- possible far/background voice flag;
- allowed ambient flag;
- repeated fingerprint flag;
- audio fingerprint string.

## Module Registration

`native/brain_core/src/api/mod.rs` now exports:

- `audio_intelligence`
- `evidence_vault`
- `lockdown`
- `proctoring`
- `system_security`

## Native Tests

`native/brain_core/tests/audio_intelligence_tests.rs` covers:

- empty audio rejection;
- low ambient audio;
- voice-like PCM;
- repeated fingerprint detection.

## Next Dart Step

Regenerate flutter_rust_bridge bindings, then create a Dart bridge similar to:

`lib/proctoring_demo/native_evidence_vault_bridge.dart`

Expected generated function:

```dart
final result = audio_intelligence.analyzeAudioPcm16(
  bytes: chunk,
  sampleRate: 44100,
  previousFingerprint: lastFingerprint,
);
```

Then update:

`lib/proctoring_demo/audio_fingerprint_isolation_service.dart`

to try Rust first and keep Dart analysis as fallback for one release.

## Validation

```bash
cd native/brain_core
cargo test
flutter_rust_bridge_codegen generate <with explicit paths>
flutter analyze --no-pub lib/proctoring_demo/audio_fingerprint_isolation_service.dart
```

## Why This Matters

Audio analysis is called continuously during the exam. Moving this foundation into Rust reduces Dart-side CPU pressure and prepares the product for stronger local AI/audio models later.

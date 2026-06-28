# Native Audio Intelligence Migration

Working branch: `codex/onnx-directml-smoke-inference`.

## Goal

Move continuous PCM audio analysis from a smoke-test heuristic toward a native, local-first audio intelligence layer that can support Nigerian exam-room environments.

## Current Native API

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

## Upgrade Applied

The native engine no longer uses the old sample-index bucket placeholder for low/mid/high audio. It now extracts real signal features from PCM16 audio:

- RMS and peak loudness;
- zero-crossing rate;
- slope energy;
- short-window envelope variation;
- impulse ratio;
- Goertzel frequency-band energy;
- low-band/hum energy;
- speech-band energy;
- high-band energy;
- tonal score;
- stable audio fingerprint from the extracted feature set.

## Supported Labels

The native classifier can now return these labels:

- `quiet_or_low_noise`
- `fan_ambient_sound`
- `generator_or_engine_ambient`
- `vehicle_or_motorcycle_ambient`
- `near_voice`
- `far_or_background_voice`
- `whisper_or_low_voice`
- `possible_multiple_voices`
- `phone_ringtone_like_sound`
- `keyboard_or_tapping_sound`
- `unclear_environment_sound`

These labels are still rule-based DSP labels, not a final trained neural model. They are a stronger local foundation for field testing and for later supervised calibration with real KASU/K-SLAS audio samples.

## Module Registration

`native/brain_core/src/api/mod.rs` exports:

- `audio_intelligence`
- `evidence_vault`
- `lockdown`
- `proctoring`
- `system_security`

## Next Engineering Steps

1. Regenerate flutter_rust_bridge bindings if the native API shape changes.
2. Preserve the richer native labels in `lib/proctoring_demo/audio_fingerprint_isolation_service.dart` instead of flattening everything to only near/far/ambient.
3. Add an `audio_environment_noise_warning` event path for non-voice sounds such as ringtone-like sound, tapping, and loud vehicle/motorcycle ambience.
4. Add calibrated tests for synthetic fan, generator, ringtone-like tone, tapping, whisper, near voice, far voice, and repeated fingerprint.
5. Later, replace the rule-based classifier with a compact local ONNX audio model trained on Nigerian exam-room samples.

## Validation

```bash
cd native/brain_core
cargo test
flutter_rust_bridge_codegen generate <with explicit paths>
flutter analyze --no-pub lib/proctoring_demo/audio_fingerprint_isolation_service.dart
```

## Why This Matters

Audio analysis is called continuously during the exam. Moving this foundation into Rust reduces Dart-side CPU pressure and prepares the product for stronger local AI/audio models later.

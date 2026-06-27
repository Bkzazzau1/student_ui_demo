# Native Vision Priority Plan

Working branch: `codex/onnx-directml-smoke-inference`.

This plan pauses backend work and focuses on the Student UI native vision path.

## Rule

Do not fake detections. If a model is not loaded or the frame cannot be analyzed, the native layer must return an unavailable/needs-review state rather than pretending to detect objects.

## Completed in this step

Added native vision core:

- `native/brain_core/src/api/native_vision.rs`
- `native/brain_core/tests/native_vision_tests.rs`

Registered native vision in:

- `native/brain_core/src/api/mod.rs`

## Native API added

- `analyze_rgb_frame_quality(...)`
- `decode_yolo_output(...)`
- `review_object_detections(...)`
- `analyze_head_pose_geometry(...)`

## Why this comes first

YOLO/object detection and gaze/head-pose must be deterministic and testable before they are wired into Flutter live monitoring. This module gives us:

- YOLOv8 row-layout output decoding
- YOLOv8 channels-first output decoding
- YOLOv5-style objectness support
- non-max suppression
- phone/person/book/paper review policy
- frame brightness/contrast/sharpness checks
- landmark-based head-pose review geometry

## Next native work

1. Run `cargo test --test native_vision_tests`.
2. Regenerate FRB bindings.
3. Add Dart bridge for native vision.
4. Wire live camera frames to native frame quality and object review.
5. Add real YOLO model asset loading/runtime path with a manifest.
6. Replace any demo scan/object labels with native detection results only.

## Validation

```bash
cd native/brain_core
cargo test --test native_vision_tests
cargo test --test system_security_tests
cargo test --test lockdown_tests
cargo test --test evidence_vault_tests
cargo test --test attempt_recovery_tests
cargo test --test audio_intelligence_tests
```

Then regenerate:

```bash
flutter_rust_bridge_codegen generate
```

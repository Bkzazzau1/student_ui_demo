# Optimized Vision Runtime Model Contract

This folder contains optimized ONNX models used by the local proctoring runtime.

## Required files

The runtime currently looks for one of these model files based on the selected precision:

- `object_reflection_shadow_detector.int8.onnx`
- `object_reflection_shadow_detector.fp16.onnx`

For production, this model should include person detection in the same output stream, or it should be replaced with a combined proctoring detector model.

## Expected detector output layouts

The native Windows parser supports common detector layouts:

- `[N, C]`
- `[1, N, C]`
- `[1, C, N]`

Each candidate row should use one of these layouts:

- `[x, y, w, h, confidence, class_id]`
- `[x, y, w, h, objectness, class_0_score, class_1_score, ...]`

Coordinates may be normalized center-width-height or normalized corner boxes.

## Class contract

The optimized runtime now treats these labels as important:

| Class ID | Label |
| --- | --- |
| 0 | `person` |
| 1 | `phone` |
| 2 | `screen_glow` |
| 3 | `mirror_reflection` |
| 4 | `offscreen_interaction` |
| 67 | `cell_phone` |

COCO-style models work for people because class `0` is mapped to `person`.

## Runtime output contract

The native runtime returns:

```json
{
  "objects": [],
  "person_count": 0,
  "multiple_people_likely": false,
  "screen_glow": false,
  "mirror_reflection": false,
  "offscreen_interaction": false,
  "runtime": "onnxRuntimeDirectML",
  "precision": "int8",
  "inference_ms": 0.0,
  "raw_outputs": []
}
```

The Flutter monitor raises `multiple_people_detected` when `person_count >= 2` or `multiple_people_likely == true` for consecutive checks.

## Recommended production model

Use a small INT8 YOLO-style model trained or fine-tuned for exam proctoring classes:

- person
- phone
- screen glow / second screen
- mirror / reflection
- off-screen hand interaction

Keep input size near `416x416` and target 1 FPS for live monitoring to preserve CPU/GPU utilization.

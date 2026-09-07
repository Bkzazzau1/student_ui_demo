# K-SLAS Edge AI Runtime

This directory contains the local Python reasoning layer. It consumes normalized
exam events, keeps bounded attempt-level context, and returns explainable review
recommendations. It does not access cameras, microphones, files, or operating
system controls directly; Dart supplies events and Rust remains the authority
for device actions and durable evidence.

## Run

From the repository root:

```powershell
python -m ai_runtime
```

The process uses newline-delimited JSON over standard input/output. Each request
must contain `protocol_version`, `request_id`, and `type`.

```json
{"protocol_version":"1.0","request_id":"1","type":"health"}
{"protocol_version":"1.0","request_id":"2","type":"review_event","payload":{"attempt_id":"attempt-1","event_type":"gaze_head_pose_deviation","confidence":0.82,"occurred_at":"2026-08-19T12:00:00Z"}}
```

## E1 development-time training readiness

`e1_training_readiness.py` is development-time tooling, not a live exam
inference dependency. It freezes the canonical dataset/evaluation/calibration
contracts for the E1 base detector and small-object specialist while leaving
scientific thresholds unset until held-out calibration data exists.

The validator checks, among other things:

- base vs specialist canonical class boundaries;
- normalized full-image bounding boxes;
- dataset/sample/annotation identifiers;
- train/validation/test split names;
- source/capture-group leakage across splits;
- required held-out per-class metrics;
- calibration records and evidence-backed confidence thresholds.

The validator does not train a model and does not impose invented performance
pass/fail values. Training frameworks, teacher models, and annotation assistants
may be used offline during development, but live exam inference remains local on
the candidate device.

The frozen runtime/training boundary is documented in
`docs/edge_ai/e1_runtime_training_readiness.md`.

## Tests

Run all Python runtime and training-readiness contract tests with:

```powershell
python -m unittest discover -s ai_runtime/tests -v
```

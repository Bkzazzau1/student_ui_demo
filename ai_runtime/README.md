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

## E1 annotation ingest

`e1_annotation_ingest.py` converts staged annotation records into the frozen E1
dataset manifest. The collection workflow must supply `source_group_id` and a
canonical E1 class for every annotation; ingest does not guess semantic aliases
or invent leakage boundaries.

Staging annotations may provide exactly one of:

- `bbox_xyxy_pixels`;
- `bbox_xywh_pixels`;
- `bbox_xywh_normalized`.

Pixel geometry is converted into full-source-image normalized geometry. The
canonical output always uses the frozen object shape
`{"x": ..., "y": ..., "width": ..., "height": ...}` and deterministic sample
and annotation IDs. Related frames from one recording/session should share the
same `source_group_id` even when they later become separate image samples.

Convert one staged split:

```powershell
python -m ai_runtime.e1_annotation_ingest --pretty data/staging/e1_base_train.json data/e1/base/train.json
```

The tool refuses to overwrite an existing output unless `--force` is supplied,
and it never writes a canonical manifest when staging validation fails. A
synthetic staging example is available at
`docs/edge_ai/examples/e1_annotation_staging.example.json`.

## E1 dataset readiness CLI

`e1_dataset_tool.py` turns the readiness contracts into a command-line gate for
real dataset files. It emits deterministic JSON and returns a non-zero exit code
when the supplied data is invalid or leaks related capture groups across splits.

Validate one or more dataset manifests together so train/validation/test leakage
can be detected:

```powershell
python -m ai_runtime.e1_dataset_tool --pretty dataset data/e1/base/train.json data/e1/base/validation.json data/e1/base/test.json
```

Validate a held-out evaluation/calibration report:

```powershell
python -m ai_runtime.e1_dataset_tool --pretty evaluation reports/e1/base_validation.json
```

A valid evaluation report may still return `"calibration_complete": false`.
That means the report contract is sound but per-class thresholds have not yet
been selected from held-out calibration evidence. The CLI also refuses to treat
`support: 0` as real held-out class evidence.

Synthetic examples live under `docs/edge_ai/examples/`. They are marked
`example_only` and are format illustrations only; their sample IDs, metric
values, and paths are not training data, model results, or acceptance targets.

## Tests

Run all Python runtime and training-readiness contract tests with:

```powershell
python -m unittest discover -s ai_runtime/tests -v
```

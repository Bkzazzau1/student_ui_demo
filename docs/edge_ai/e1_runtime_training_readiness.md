# E1 Runtime Freeze and Training Readiness

## Status

The E1 runtime architecture is frozen for the training/calibration phase.

This does **not** mean the final E1 models are scientifically complete. The current base model is still a development baseline and the bundled small-object specialist remains unavailable until a real validated local model is packaged.

## Hard live-runtime rule

All live exam E1 inference runs locally on the candidate device. External foundation models or hosted AI services are not runtime dependencies.

External teacher models may be used only during offline development activities such as dataset annotation, consensus checking, synthetic-data review, distillation, validation, red-team analysis and training support.

## Frozen live path

The production E1 path is:

1. camera capture;
2. original source-frame ID and monotonic capture timestamp;
3. local base E1 detector;
4. canonical `ModelEventV1` observations;
5. Rust-owned person tracking and spatiotemporal memory;
6. geometry-driven ROI planning for specialist-required small objects;
7. bounded specialist execution scheduling;
8. local specialist inference when a validated specialist model is installed;
9. crop detections remapped to full-frame normalized geometry;
10. validated specialist `ModelEventV1` observations;
11. Rust-owned spatiotemporal memory for downstream temporal reasoning.

The scheduler controls compute only. A specialist request that is skipped because of cooldown, in-flight work or per-frame budget remains unobserved/UNKNOWN. It is never converted into negative evidence or object absence.

## Frozen E1 training roles

### Base detector role

The canonical trainable base classes are:

- `person`
- `phone`
- `laptop`
- `television`
- `keyboard`
- `mouse`
- `remote`
- `book`

The current COCO baseline exposes its large-screen class as `tv`. Generic `monitor` and `tv monitor` wording resolve to canonical `television`; this does not create a separate monitor detector class.

### Small-object specialist role

The canonical trainable specialist classes are:

- `wrist_device`
- `earbud`
- `tablet`
- `paper_note`
- `calculator`

Taxonomy `1.1` replaced `smartwatch` with `wrist_device` in place (same class index); `smartwatch` is retired, not an alias, and is rejected rather than silently accepted under the current taxonomy. See `docs/edge_ai/e1_object_taxonomy.md` for full `wrist_device` semantics and the exam-policy wording it supports.

Until a validated specialist model and manifest are installed, the live specialist path must emit zero specialist observations.

### Derived-only signals

The following are not detector training classes:

- `additional_person`
- `partial_person`
- `screen_signal`

They are derived from bounded downstream evidence and must not be inserted into detector datasets as direct object classes.

## Dataset contract

Development datasets should be represented using the contracts in `ai_runtime/e1_training_readiness.py`.

Each split manifest must preserve:

- schema version;
- taxonomy version;
- dataset ID and version;
- model role (`base` or `specialist`);
- split (`train`, `validation`, or `test`);
- unique sample IDs;
- source/capture group IDs;
- image dimensions and controlled image path;
- canonical class IDs;
- full-image normalized `x/y/width/height` boxes;
- optional hard-negative tags.

`source_group_id` is a leakage boundary. Closely related captures from the same recording/burst/session must not be divided across train, validation and test splits.

### Executable dataset gate

Use `ai_runtime/e1_dataset_tool.py` to apply the contracts to real JSON files before training or evaluation.

Validate dataset splits together:

```powershell
python -m ai_runtime.e1_dataset_tool --pretty dataset data/e1/base/train.json data/e1/base/validation.json data/e1/base/test.json
```

Validate a held-out evaluation/calibration report:

```powershell
python -m ai_runtime.e1_dataset_tool --pretty evaluation reports/e1/base_validation.json
```

The tool emits machine-readable JSON and exits non-zero for invalid data, malformed JSON, unsafe class/geometry contracts, or source-group leakage. It also reports dataset sample/annotation/class/hard-negative counts. Held-out class metrics with zero support are not treated as real evaluation evidence.

Files under `docs/edge_ai/examples/` are synthetic format examples only. Their paths, IDs, metrics and values are not model results, training data, or scientific acceptance targets.

## Hard negatives

Hard-negative collection is required for realistic exam deployment. Initial categories include:

- bracelet/jewelry/wristband vs wrist_device;
- earring vs earbud;
- remote control vs phone;
- hand without phone;
- printed pattern vs paper/note;
- background screen vs candidate-relevant extra screen.

These tags support evaluation; they are not automatically converted into risk evidence.

## Evaluation contract

Held-out model reports must include per-class:

- support;
- precision;
- recall;
- F1;
- AP50;
- AP50:95.

Hard-negative reports may additionally record sample counts and false-positive rates.

The contract validates metric presence and legal numeric ranges. It intentionally does **not** define scientific pass/fail values.

## Calibration rule

A class may carry `selected_confidence_threshold: null` while calibration is incomplete.

A class threshold is considered selected only when it also records:

- the chosen numeric threshold;
- the empirical selection basis;
- the calibration dataset ID.

E1 calibration is complete only when every class in the relevant model role has an evidence-backed threshold. Thresholds must come from held-out calibration work; they must not be guessed in source code.

## Remaining empirical work

The following remain open and are expected to change without altering the frozen event/runtime architecture:

1. dataset acquisition and annotation;
2. hard-negative collection;
3. final base-model architecture/weights;
4. final small-object specialist architecture/weights;
5. training hyperparameters;
6. held-out evaluation results;
7. per-class confidence calibration;
8. ONNX export and post-processing verification;
9. FP16/INT8 quantization decisions;
10. on-device latency, memory, thermal and power benchmarking;
11. offline scenario acceptance tests.

## E1 completion language

Until the empirical work above is completed, use:

> **E1 runtime architecture complete; model training and scientific calibration pending.**

After validated models, calibrated thresholds and offline device acceptance are complete, E1 may be marked production-calibrated.

# E1 Training Experiment Lock

## Purpose

`ai_runtime/e1_training_experiment.py` binds one explicit E1 training experiment
specification to one verified training-export package.

It is development-time tooling only. It does not train a model, does not download
a checkpoint, and is never part of live exam inference.

The purpose is to prevent a future result from being described only as
"we trained YOLO." A reproducible experiment must say exactly which dataset
package, framework version, architecture, initialization, seed and core training
choices were used.

## No hidden core defaults

The experiment specification must explicitly provide:

- experiment schema version;
- experiment ID;
- E1 model role (`base` or `specialist`);
- framework name and version;
- model architecture;
- initialization (`scratch` or `pretrained`);
- checkpoint path + SHA-256 when pretrained;
- random seed;
- image size;
- epoch count;
- batch size;
- optimizer name;
- learning rate;
- weight decay;
- worker count;
- precision (`fp32` or `amp` in schema v1);
- deterministic-mode choice;
- augmentation enabled/disabled;
- explicit augmentation parameter object;
- execution device.

The validator intentionally supplies none of these values. Missing fields are
errors. Framework-specific settings may be recorded as additional fields in the
specification; the lock preserves the full supplied JSON object.

This contract does not claim that two different frameworks interpret similarly
named parameters identically. Framework name and exact version are therefore
part of the lock.

## Dataset verification

Before a lock is written, the tool checks the selected E1 training export:

1. `export_manifest.json` exists;
2. `dataset.yaml` exists;
3. export schema and E1 taxonomy versions match;
4. experiment role matches export role;
5. class-map indices and canonical class order match the frozen role;
6. every exported image and label path stays inside the package;
7. every referenced exported image and label exists;
8. every copied image SHA-256 still matches the source SHA recorded at export.

It then computes SHA-256 for every package file participating in training and
builds a deterministic package fingerprint from the relative path + file hash
pairs.

The generated lock records the file list and hashes, so a later training runner
can verify that it is using the exact package that was approved for the
experiment.

## Pretrained checkpoint rule

For `initialization: "pretrained"`, the experiment must declare both:

- checkpoint path;
- exact SHA-256 of the checkpoint bytes.

The lock is refused if the file is missing or its SHA does not match.

For `initialization: "scratch"`, `checkpoint` must be `null`.

No checkpoint is downloaded automatically by this tool.

## Lock command

```powershell
python -m ai_runtime.e1_training_experiment --pretty --export work/e1/base-yolo --output experiments/e1/base-exp-001.lock.json experiments/e1/base-exp-001.json
```

The output path must not already exist. An earlier experiment lock is never
silently replaced.

## Lock contents

A successful lock contains:

- lock schema version;
- the complete experiment specification;
- dataset ID/version and model role;
- E1 taxonomy and export schema versions;
- `export_manifest.json` SHA-256;
- `dataset.yaml` SHA-256;
- overall training-package SHA-256;
- every participating relative file path + SHA-256;
- verified sample count;
- checkpoint SHA-256 when pretrained.

No wall-clock timestamp is inserted into the lock, so creating a lock from the
same specification and unchanged package does not introduce time-based noise.

## Synthetic example

`docs/edge_ai/examples/e1_training_experiment.example.json` is marked
`example_only`. Its framework name, architecture and numeric values exist only
to demonstrate the schema. They are not selected E1 hyperparameters, benchmark
results, recommendations or production settings.

## What remains empirical

This lock does not decide:

- which YOLO family/size should win;
- whether scratch or transfer learning performs better;
- augmentation policy;
- optimizer/scheduler choice;
- learning-rate schedule;
- training duration;
- model-selection criteria;
- per-class acceptance thresholds;
- confidence calibration;
- ONNX export settings;
- FP16/INT8 deployment choices.

Those decisions must be made through actual E1 experiments and held-out
evaluation. The lock simply makes each experiment auditable.

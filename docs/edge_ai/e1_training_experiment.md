# E1 Training Experiment Plan Contract

## Purpose

`ai_runtime/e1_training_experiment.py` turns an explicit E1 training experiment
specification plus a previously validated YOLO export into an auditable,
non-executing training plan.

This tool is development-time only. It does not run during an exam, does not
select model weights, does not download checkpoints, and does not execute a
trainer.

## Why this boundary exists

The E1 runtime architecture is already frozen. Training choices are empirical
research choices and must not be hidden in source-code defaults.

The experiment plan therefore requires the operator/research workflow to state
its choices explicitly before training begins.

## Required experiment identity

Every experiment specification must provide:

- `schema_version`;
- a portable `experiment_id`;
- `framework: ultralytics`;
- an explicitly pinned `framework_version`;
- `task: detect`;
- `model_role` (`base` or `specialist`);
- an explicit local `checkpoint_path`;
- a `project_dir` for future trainer output;
- an explicit non-negative random `seed`.

The checkpoint must already exist locally and be non-empty. The planning tool
never downloads a model automatically.

## Required trainer choices

`trainer_args` must explicitly include all of the following:

| Field | Requirement |
|---|---|
| `epochs` | positive integer |
| `imgsz` | positive integer |
| `batch` | positive integer |
| `workers` | non-negative integer |
| `device` | non-empty string |
| `optimizer` | non-empty string |
| `lr0` | positive finite number |
| `weight_decay` | non-negative finite number |
| `patience` | non-negative integer |
| `deterministic` | boolean |

This contract intentionally provides **no recommended numeric values**. Those
choices must come from the actual E1 experiment design and available training
hardware, not from arbitrary source-code defaults.

Additional scalar trainer arguments may be included when needed, but reserved
provenance fields such as `model`, `data`, `project`, `name`, `exist_ok`, `seed`,
`task`, and `mode` cannot be overridden through `trainer_args`.

## Augmentation policy

`augmentation_policy.mode` must be one of:

- `framework_defaults` — intentionally use the defaults of the explicitly pinned
  framework version;
- `explicit` — provide one or more augmentation arguments under
  `augmentation_policy.args`.

Using framework defaults is an explicit experiment decision, not an implicit
fallback. Pinning the framework version is therefore mandatory.

## Export-package validation

The experiment planner reads the prior training package's:

- `export_manifest.json`;
- `dataset.yaml`.

It verifies:

- training export schema version;
- frozen E1 taxonomy version;
- model role;
- exact frozen class-index mapping;
- dataset ID/version;
- non-empty train split;
- non-empty validation split.

Base and specialist experiments cannot be mixed.

## Provenance recorded in the plan

The generated plan records:

- experiment ID and schema versions;
- framework and pinned framework version;
- task and model role;
- dataset ID/version;
- full paths to `dataset.yaml` and `export_manifest.json`;
- SHA-256 of both export metadata files;
- exact class-index mapping;
- local checkpoint path, size, and SHA-256;
- random seed;
- project/run directory;
- normalized trainer arguments;
- augmentation policy;
- a deterministic `command_argv` list;
- `execution_status: not_executed`.

`command_argv` is stored as an argument vector, not a shell command string. The
planning step never invokes a shell or subprocess.

## Output safety

The future run directory `<project_dir>/<experiment_id>` must not already exist.
The plan output file must also be new. The planner refuses to overwrite either,
so prior experiment evidence is not silently replaced.

## Example command

After creating an explicit experiment specification:

```powershell
python -m ai_runtime.e1_training_experiment --pretty --spec experiments/e1/base_exp_001.json --export work/e1/base-yolo --output-plan work/e1/plans/base_exp_001.plan.json
```

A successful command writes the plan but **does not start training**.

## What remains after planning

A separate execution step must still:

1. verify the installed framework version matches the pinned plan;
2. verify the checkpoint and dataset-plan hashes before launch;
3. execute the argument vector without shell interpolation;
4. capture stdout/stderr, environment metadata, trainer outputs and final
   checkpoint hashes;
5. run held-out evaluation;
6. calibrate class thresholds from evidence;
7. export and verify ONNX;
8. benchmark the model on the target candidate device.

No performance claim or scientific threshold is created by the planning step.

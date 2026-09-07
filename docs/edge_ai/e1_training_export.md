# E1 Training Export Contract

## Purpose

`ai_runtime/e1_training_export.py` is a development-time bridge from the frozen
canonical E1 dataset manifests into a self-contained YOLO training package.

It does not run during an exam, does not change the live E1 event contract, and
does not select scientific thresholds or model weights.

## Input boundary

The exporter accepts canonical E1 manifests produced by the annotation/data
pipeline. It reuses the frozen validators before writing any training package.

One export must contain exactly one:

- `dataset_id`;
- `dataset_version`;
- taxonomy version;
- model role (`base` or `specialist`).

Base and specialist datasets are exported separately.

Train and validation manifests are required. A test manifest is optional.
Closely related captures must remain source-group-disjoint across all supplied
splits; the exporter rejects cross-split `source_group_id` leakage.

## Frozen YOLO class order

### Base detector

| YOLO index | Canonical class |
|---:|---|
| 0 | `person` |
| 1 | `phone` |
| 2 | `laptop` |
| 3 | `television` |
| 4 | `keyboard` |
| 5 | `mouse` |
| 6 | `remote` |
| 7 | `book` |

### Small-object specialist

| YOLO index | Canonical class |
|---:|---|
| 0 | `smartwatch` |
| 1 | `earbud` |
| 2 | `tablet` |
| 3 | `paper_note` |
| 4 | `calculator` |

The exporter asserts that these ordered sets still match the frozen canonical
training-role sets. A mismatch fails closed rather than silently reindexing a
model class.

## Geometry conversion

The canonical dataset stores normalized full-image boxes as top-left
`x/y/width/height`.

YOLO labels require normalized center coordinates:

```text
center_x = x + width / 2
center_y = y + height / 2
```

Each label line is:

```text
<class_index> <center_x> <center_y> <width> <height>
```

The exporter performs this conversion only after the canonical manifest
validator confirms that geometry is finite, positive, normalized and bounded
inside the full source image.

## Materialized package

A successful export has the following shape:

```text
<output>/
  dataset.yaml
  export_manifest.json
  images/
    train/
    validation/
    test/          # only when supplied
  labels/
    train/
    validation/
    test/          # only when supplied
```

Each image is copied into the package using its canonical `sample_id` as the
file stem. Each corresponding label file uses the same stem.

A canonical sample with no annotations produces an empty YOLO label file, which
is YOLO's representation of a negative/background sample. The exporter does not
invent negative tags or reinterpret annotations.

## Provenance

`export_manifest.json` records:

- export schema version;
- taxonomy version;
- dataset ID/version;
- model role;
- ordered class-index mapping;
- source manifest paths;
- per-split sample/annotation counts;
- sample ID;
- source-group ID;
- original image path;
- SHA-256 of the source image bytes;
- exported image/label paths;
- annotation count;
- hard-negative tags already present in the canonical manifest.

The SHA-256 is there to make the training input auditable. It does not replace
normal dataset versioning or controlled storage.

## Fail-closed behavior

The exporter writes through a temporary staging directory and removes that
staging area if materialization fails.

It refuses to proceed when, among other things:

- a manifest is invalid;
- train or validation is missing;
- two manifests claim the same split;
- base and specialist roles are mixed;
- dataset IDs or versions are mixed;
- taxonomy versions do not match the frozen E1 taxonomy;
- source-group leakage exists across splits;
- a referenced source image is missing or empty;
- the requested output path already exists.

There is intentionally no overwrite flag in this first export contract. A new
training package should use a new output directory so prior evidence remains
intact.

## Example command

```powershell
python -m ai_runtime.e1_training_export --pretty --output work/e1/base-yolo data/e1/base/train.json data/e1/base/validation.json data/e1/base/test.json
```

## What this does not do

This step does not:

- choose a YOLO architecture or checkpoint;
- download external models;
- run training;
- define augmentation policy;
- choose optimizer or hyperparameters;
- claim performance;
- select class confidence thresholds;
- calibrate the model;
- export ONNX;
- quantize FP16/INT8;
- change the live exam runtime.

Those remain separate, evidence-driven development steps.

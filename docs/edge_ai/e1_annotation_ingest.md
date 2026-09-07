# E1 Annotation Ingest

## Purpose

`ai_runtime/e1_annotation_ingest.py` is the development-time boundary between
raw/staged image annotations and the frozen E1 dataset manifest. It does not
train a model and it is never used during a live exam.

The tool exists so annotation exports can use convenient pixel geometry while
the training dataset always receives one canonical class vocabulary, one
full-image normalized geometry format, deterministic IDs, and explicit leakage
boundaries.

## Required staging fields

Each staging file describes exactly one model role and one dataset split:

- `ingest_schema_version`: currently `1.0`;
- `dataset_id`;
- `dataset_version`;
- `model_role`: `base` or `specialist`;
- `split`: `train`, `validation`, or `test`;
- `records`: one object per source image.

Every image record must provide:

- `source_group_id`;
- `image_path`;
- `width` and `height` of the original full image;
- `annotations`, which may be an empty list for a negative sample;
- optional `negative_tags`.

## Source-group rule

`source_group_id` is supplied by the collection workflow. Ingest deliberately
refuses to infer it.

Frames or images that are tightly related because they came from the same video,
burst, capture session, scripted scenario, or other near-duplicate source should
share one `source_group_id`. Later dataset splitting must keep that whole group
inside only one of train, validation, or test.

Example:

```text
session-004/frame-0001.jpg -> source_group_id=session-004
session-004/frame-0002.jpg -> source_group_id=session-004
session-005/frame-0001.jpg -> source_group_id=session-005
```

The dataset readiness CLI then rejects a dataset if `session-004` appears in
more than one split.

## Canonical classes only

The annotation record must provide `canonical_object_id`. Case and surrounding
whitespace are normalized, but semantic aliases are not guessed.

Examples:

- `Phone` -> `phone` is accepted as case normalization;
- `cell phone` is rejected rather than silently promoted to `phone`;
- `tv_monitor` is rejected at ingest unless the annotation workflow has already
  resolved it to canonical `television`;
- `smartwatch` cannot enter a base-detector staging file;
- `phone` cannot enter a specialist staging file.

Base trainable classes:

`person`, `phone`, `laptop`, `television`, `keyboard`, `mouse`, `remote`, `book`.

Specialist trainable classes:

`smartwatch`, `earbud`, `tablet`, `paper_note`, `calculator`.

## Geometry accepted from annotation tools

Each annotation must provide exactly one geometry representation:

- `bbox_xyxy_pixels`: `[x1, y1, x2, y2]`;
- `bbox_xywh_pixels`: `[x, y, width, height]`;
- `bbox_xywh_normalized`: `[x, y, width, height]`.

Pixel coordinates are interpreted against the declared original image width and
height. Boxes outside the source image, zero/negative size boxes, non-finite
numbers, and annotations carrying more than one geometry representation are
rejected.

The canonical manifest always stores:

```json
{
  "bbox_xywh_normalized": {
    "x": 0.10,
    "y": 0.20,
    "width": 0.15,
    "height": 0.25
  }
}
```

These coordinates refer to the original full source image, not an annotation
viewer crop or specialist ROI.

## Deterministic IDs

The ingest tool generates deterministic `sample_id` and `annotation_id` values
from stable dataset/sample/class/geometry content. Re-running the same staging
input therefore produces the same identities.

Use stable dataset-relative image paths where possible. Windows backslashes are
normalized to `/` before identity generation so the same relative path is not
treated differently only because of path separators.

Duplicate image identities or duplicate class/box annotations are rejected.

## Hard-negative samples

A record may intentionally contain no positive annotations:

```json
{
  "source_group_id": "session-negative-watch-001",
  "image_path": "images/negative-watch/frame-001.jpg",
  "width": 1920,
  "height": 1080,
  "negative_tags": ["ordinary_watch"],
  "annotations": []
}
```

Hard-negative tags are evaluation/training metadata. They are not live exam risk
evidence.

## Run ingest

From the repository root:

```powershell
python -m ai_runtime.e1_annotation_ingest --pretty data/staging/e1_base_train.json data/e1/base/train.json
```

The command returns non-zero and writes no canonical manifest when staging is
invalid. Existing outputs are protected unless `--force` is explicitly used.

After creating all splits, run the cross-split gate:

```powershell
python -m ai_runtime.e1_dataset_tool --pretty dataset data/e1/base/train.json data/e1/base/validation.json data/e1/base/test.json
```

A synthetic staging example is available at
`docs/edge_ai/examples/e1_annotation_staging.example.json`. It is format-only,
not real training evidence.

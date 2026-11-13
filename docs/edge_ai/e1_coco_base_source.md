# E1 Base Detector: COCO 2017 Open-Dataset Source

## Status

Development-time data source for the **E1 base detector only**. The live exam
architecture is unchanged:

```text
live exam inference -> local K-SLAS edge AI only
```

`ai_runtime/e1_coco_source.py` contacts no AI service and downloads nothing.

## Why COCO for the base role

COCO 2017 already contains crowd-sourced **human** bounding-box annotations for
every E1 base class. The V1 strategy (`e1_v1_nonphysical_data_strategy.md`)
permits open-source datasets whose terms allow the intended use. Re-labelling
COCO images with three AI teachers would replace human boxes with machine
votes, add API cost, and lower label quality. This source therefore keeps the
original human annotations and records them under their own evidence tier.

The small-object specialist classes (`wrist_device`, `earbud`, `tablet`,
`paper_note`, `calculator`) are **not** COCO categories and are out of scope.

## Evidence tier: `open_dataset_human`

| Tier | Meaning |
| --- | --- |
| `silver` | strict teacher-consensus training annotation |
| `teacher_consensus_eval` | held-out teacher-consensus annotation; not human ground truth |
| `open_dataset_human` | human annotation supplied by an open dataset; **not verified by K-SLAS** |
| `gold` | explicitly human-verified by K-SLAS |
| `field` | reviewed real exam evidence, curated for V2 |

`open_dataset_human` is not gold. Metrics measured on COCO held-out data are
COCO-domain metrics; they are not K-SLAS exam-room accuracy and must not be
presented as production calibration. COCO is general photography, not webcam
exam footage, so a domain gap is expected until field data exists.

## Fixed category mapping

| COCO category | E1 canonical class |
| --- | --- |
| `person` | `person` |
| `cell phone` | `phone` |
| `laptop` | `laptop` |
| `tv` | `television` (COCO `tv` covers TVs and monitors) |
| `keyboard` | `keyboard` |
| `mouse` | `mouse` |
| `remote` | `remote` |
| `book` | `book` |

The table is frozen in code and must cover exactly the frozen base classes.
No other COCO category is mapped. No aliases are guessed.

## Fail-closed image rules

An image is excluded entirely (never partially labelled) when:

- its COCO image license id is not in the explicit `allowed_license_ids`;
- any E1-target annotation is a crowd region (`iscrowd = 1`), because crowd
  regions would leave individual objects unlabelled;
- any E1-target box leaves the image by more than 1 px;
- any E1-target box is under 1 px wide/high after clipping.

Boxes that overshoot the image by at most 1 px (COCO float rounding) are
clipped and counted in the audit. Exact duplicate annotations (same class and
same normalized box, the ingest identity rule) are collapsed to one.

Background images (no E1 target) are only taken from images carrying at least
one other COCO annotation, so "no target object" is backed by an annotated
image rather than an unannotated one.

## Pretrained-checkpoint leakage rule

Public YOLO checkpoints are pretrained on COCO `train2017`. To keep held-out
metrics meaningful when fine-tuning from such a checkpoint:

```text
COCO train2017 -> E1 train only
COCO val2017   -> E1 validation + test only
```

Two selections/inventories are built, one per COCO split, with split weights
`{train: 1, validation: 0, test: 0}` and `{train: 0, validation: W, test: W}`.
Public checkpoints may have used `val2017` for their own model selection, so
COCO held-out metrics can be mildly optimistic. Record this in reports.

## Selection config

Every value is explicit; the tool supplies no defaults.

```json
{
  "selection_schema_version": "1.0",
  "dataset_id": "e1-base-coco",
  "dataset_version": "v1",
  "coco_split": "train2017",
  "image_dir": "train2017",
  "selection_seed": "<recorded seed>",
  "allowed_license_ids": [1, 2, 3, 4, 5, 6, 7, 8],
  "person_only_limit": 0,
  "background_limit": 0,
  "split_seed": "<recorded seed>",
  "split_weights": {"train": 1, "validation": 0, "test": 0}
}
```

Selection tiers:

- `non_person_target`: images containing any non-person base class. All are kept.
- `person_only`: images whose only targets are people. A seeded sample of
  `person_only_limit` is kept (COCO is person-heavy; this controls imbalance).
- `background`: annotated images with no target. A seeded sample of
  `background_limit` is kept as negatives.

Selection uses COCO labels to choose images; **split assignment stays
label-blind** because `e1_collection_split` assigns whole source groups by
seeded hash. Each COCO image is its own source group
(`coco2017:<split>:<image_id>`). Exact duplicate images across splits are
additionally rejected by the training package gate (image SHA-256).

## License

COCO annotations are published under CC BY 4.0. COCO images keep their
original Flickr licenses, recorded per image (`provenance.license`), several of
which are non-commercial. The tool records licenses; it makes no legal
determination. Narrow `allowed_license_ids` if the deployment requires it and
rebuild the dataset.

## Commands

```powershell
python -m ai_runtime.e1_coco_source inventory --instances <coco>/annotations/instances_train2017.json --selection train_selection.json --output inventory_train.json
python -m ai_runtime.e1_collection_split inventory_train.json plan_train.json
python -m ai_runtime.e1_coco_source stage --instances <coco>/annotations/instances_train2017.json --plan plan_train.json --selection train_selection.json --split train --output staging_train.json
python -m ai_runtime.e1_annotation_ingest staging_train.json train.json
```

Repeat with the `val2017` selection for `validation` and `test`, then run
`e1_dataset_tool dataset` across all three manifests and `e1_training_export`.
Image paths are dataset-relative (`train2017/<file>`), so keep manifests at the
COCO root that contains `train2017/` and `val2017/`.

Keep every staging file next to its canonical manifest. Ingest does not copy
the `open_dataset_audit` block or per-record provenance.

## Hard rules

1. Base role only; specialist classes need other sources.
2. COCO human labels are `open_dataset_human`, never called gold or teacher consensus.
3. The category table is exact and frozen; no aliases are guessed.
4. Crowd, out-of-bounds, degenerate-box and disallowed-license images are excluded whole.
5. train2017 feeds train only; val2017 feeds validation/test only.
6. Split assignment is label-blind and source-group-safe.
7. Licenses are recorded per image and never guessed.
8. Live exam AI remains local-only.

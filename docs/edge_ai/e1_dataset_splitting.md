# E1 Dataset Split Planning

## Purpose

`ai_runtime/e1_collection_split.py` creates a deterministic train/validation/test
split plan from a collected-image inventory before annotation ingestion. It is
development-time tooling only and is never used during a live exam.

The primary invariant is simple:

> Every image sharing one `source_group_id` must remain in one split.

This prevents tightly related frames from the same recording, burst, scripted
scenario, or capture session from leaking between training and held-out data.

## No default scientific split ratio

The tool does **not** choose a train/validation/test ratio. The collection
inventory must explicitly provide all three `split_weights` plus a `split_seed`.

For example:

```json
{
  "split_weights": {
    "train": 8,
    "validation": 1,
    "test": 1
  },
  "split_seed": "pilot-seed-001"
}
```

Those numbers are only an example format. They are not an E1 acceptance rule or
scientific recommendation. The project must choose split weights appropriate to
the actual collection and evaluation design.

A zero weight intentionally disables that split. Missing weights are rejected
rather than replaced with hidden defaults.

## Collection inventory

Each inventory contains:

- `collection_schema_version` (`1.0`);
- `dataset_id` and `dataset_version`;
- `model_role` (`base` or `specialist`);
- explicit `split_seed`;
- explicit `split_weights` for `train`, `validation`, and `test`;
- collected image records.

Every record must contain:

- `source_group_id`;
- dataset-relative `image_path`;
- original image `width` and `height`.

The splitter does not infer `source_group_id`. Assign it during collection based
on the real provenance boundary.

## Deterministic assignment

The splitter groups records by `source_group_id`, orders groups deterministically
using the supplied seed, and assigns whole groups while attempting to keep
record counts close to the requested weights. Group integrity always takes
priority over achieving an exact record ratio, so the actual fractions can
differ from the requested weights when group sizes are uneven.

The output records both target record counts and actual record counts/fractions.
Do not report those actual fractions as class balance: the splitter runs before
annotations and therefore does not know the class distribution.

Changing the seed can change the assignment. Keep the chosen seed in the split
plan and dataset provenance so the same plan is reproducible.

## Output split plan

The plan contains:

- dataset/model-role provenance;
- the exact split seed and supplied weights;
- source-group-to-split assignments;
- each image record with its assigned split;
- source-group and record counts per split;
- target and actual record counts/fractions.

It does not insert annotations, negative labels, class guesses, or risk evidence.
An unannotated image remains simply an unannotated collected image.

## Run

From the repository root:

```powershell
python -m ai_runtime.e1_collection_split --pretty data/collection/e1_base_inventory.json data/collection/e1_base_split_plan.json
```

The command refuses to overwrite an existing plan unless `--force` is supplied.
Malformed inventories, duplicate normalized image paths, missing source groups,
invalid dimensions, missing weights, unknown split keys, and invalid seeds are
rejected.

A synthetic format example is available at:

`docs/edge_ai/examples/e1_collection_inventory.example.json`

It is not real data and its example weights are not a scientific target.

## Position in the data workflow

```text
raw image captures
    -> collection inventory with explicit source_group_id
    -> source-group-safe split plan
    -> annotation workflow for each assigned split
    -> E1 annotation ingest
    -> canonical train/validation/test manifests
    -> E1 dataset readiness gate
    -> model training and held-out evaluation
```

After annotation, run the canonical dataset gate across the produced manifests.
That later stage checks class counts, geometry contracts, hard-negative metadata,
and cross-split source-group leakage using the actual annotated dataset.

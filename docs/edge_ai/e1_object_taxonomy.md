# E1 Canonical Object Taxonomy and Small-Object Boundary

## Purpose

E1 uses a stable exam-object taxonomy independently of the labels emitted by a particular detector. The current `e1-yolo-exam-review` development baseline is COCO-based and must not be treated as though it already detects exam-specific small-object classes that are absent from COCO.

## Coverage states

- `base_detector`: genuinely represented by the current base detector taxonomy.
- `specialist_required`: requires a separate local specialist model before live evidence may be emitted for that object.
- `derived_signal`: produced from bounded derived evidence rather than a direct object class.
- `unknown`: no supported canonical mapping; downstream code must not strengthen it into a known class.

## Current examples

Base detector coverage includes `person`, `phone` (from COCO `cell phone`), `laptop`, `television`, `keyboard`, `mouse`, `remote`, and `book`.

The current COCO baseline exposes the large-screen class as `tv`. Generic `monitor` and `tv monitor` wording resolve to canonical `television` with `base_detector` coverage; this does not claim a separate monitor detector class.

Specialist-required targets include `smartwatch`, `earbud`, `tablet`, `paper_note`, and `calculator`.

A generic `clock` is not a smartwatch observation. A `remote` is not a phone observation. Unknown labels remain unknown.

## Frozen detector-training roles

The base detector training role uses canonical classes:

- `person`
- `phone`
- `laptop`
- `television`
- `keyboard`
- `mouse`
- `remote`
- `book`

The small-object specialist training role uses canonical classes:

- `smartwatch`
- `earbud`
- `tablet`
- `paper_note`
- `calculator`

Derived signals such as `additional_person`, `partial_person`, and `screen_signal` are not direct detector training classes.

## Frozen event compatibility

The detector-derived `ModelEventV1.class_id` remains unchanged for compatibility. For example, COCO `cell phone` continues to emit `class_id: cell_phone`. Canonical identity and coverage are carried in event metadata using `canonical_object_id`, `object_group`, `object_coverage`, and `taxonomy_version`.

## Small-object specialist boundary

`E1SmallObjectSpecialist` is a runtime interface only. Production implementations must run locally on the candidate device. A specialist observation is accepted only when it:

- belongs to the declared specialist taxonomy;
- carries non-empty model ID and model version;
- preserves source-frame and capture/inference provenance;
- has valid normalized geometry and confidence;
- does not reverse capture/inference time.

The cascade planner can request specialist inference from bounded base evidence such as a person or desk anchor. A request is only a routing decision; it is never evidence that the target object exists.

The execution scheduler may defer specialist work for cooldown, concurrency, or per-frame compute budget. Deferred work remains unobserved/UNKNOWN and must not be converted into negative evidence.

## Runtime rule

No external foundation model or cloud inference service is part of this live interface. External teacher models may be used only during offline dataset construction, annotation, validation, distillation, red-team analysis, and training workflows.

See `docs/edge_ai/e1_runtime_training_readiness.md` for the runtime freeze, dataset contract, evaluation contract, and calibration boundary.

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

Specialist-required targets include `wrist_device`, `earbud`, `tablet`, `paper_note`, and `calculator`.

A generic `clock` is not a wrist_device observation. A `remote` is not a phone observation. Unknown labels remain unknown.

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

- `wrist_device`
- `earbud`
- `tablet`
- `paper_note`
- `calculator`

Derived signals such as `additional_person`, `partial_person`, and `screen_signal` are not direct detector training classes.

## Taxonomy 1.1: `wrist_device` replaces `smartwatch`

Taxonomy version `1.1` replaced the specialist class `smartwatch` with `wrist_device` in place, preserving its position so `earbud`, `tablet`, `paper_note`, and `calculator` keep the same class indices. `smartwatch` is retired, not an alias: legacy annotation, teacher-vote, or human-review payloads that still spell it `smartwatch` are rejected as non-canonical rather than silently promoted to `wrist_device`.

`wrist_device` means a visually identifiable wrist-worn timekeeping or electronic wearable that exam policy prohibits. The AI is not required to determine whether a watch is "smart" — analogue wristwatches, digital wristwatches, smartwatches, fitness trackers, and smart bands are all positive `wrist_device` examples.

Jewelry bracelets, decorative bracelets, and simple non-device wristbands are not `wrist_device` merely because they are worn on a wrist. These are hard negatives (tag: `bracelet_or_wristband`), replacing the retired `ordinary_watch` hard-negative concept, which is obsolete now that ordinary watches are valid `wrist_device` positives. When an object cannot be reliably distinguished between a wrist device and jewelry/accessory, it must be treated as UNKNOWN, routed to human review, or excluded from canonical annotation — never silently guessed.

`phone` and `tablet` remain distinct canonical classes from each other and from `wrist_device`; none of these are merged or aliased into one another. `phone` or `tablet` observations may support the derived policy concept `prohibited_personal_device_present`; `wrist_device` observations may support `prohibited_wrist_device_present`. Both are policy/review concepts, not YOLO training classes, and neither implies an automatic misconduct or punishment decision — a detection is observable evidence, not a verdict.

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

## Exam policy wording

> No wristwatch or personal electronic device may be worn, held, kept on the desk, or kept within reach during a proctored examination. This includes analogue and digital watches, smartwatches, fitness trackers or smart bands, mobile phones or smartphones, tablets, and similar personal communication or display devices.

The AI records observable objects/evidence only — a `phone`, `tablet`, or `wrist_device` detection (or the derived `prohibited_personal_device_present` / `prohibited_wrist_device_present` policy concepts built from them) is not itself a misconduct finding. Human/institutional policy determines the final disposition; detection is evidence, not a verdict.

## Runtime rule

No external foundation model or cloud inference service is part of this live interface. External teacher models may be used only during offline dataset construction, annotation, validation, distillation, red-team analysis, and training workflows.

See `docs/edge_ai/e1_runtime_training_readiness.md` for the runtime freeze, dataset contract, evaluation contract, and calibration boundary.

# E1 V1 Non-Physical Dataset Strategy

## Status

This is the authoritative data-acquisition strategy for **E1 Version 1**.

Version 1 does **not** require K-SLAS to run its own physical participant capture campaign. The existing physical-capture protocol remains useful for later field collection, controlled studies, and Version 2 improvement, but it is not the required V1 starting point.

The live architecture is unchanged:

```text
live exam inference -> local K-SLAS edge AI only
```

External/foundation models are development-time teachers only. They are not required, contacted, or trusted during a live examination.

## 1. V1 data sources

V1 may build its dataset from three source families:

1. **Synthetic images** generated during development by image-generation systems such as OpenAI/ChatGPT image generation, Gemini/Google image generation, or other suitable generators.
2. **Open-source datasets** whose terms permit the intended development/training use.
3. **Openly licensed real-world images or videos** that can be retained and processed under their actual license terms.

Project-owned physical capture is deliberately deferred from the required V1 path.

Do not treat "available on the internet" as equivalent to "licensed for training." License/provenance must be recorded for non-synthetic media. The tooling records declared provenance; it does not make or guess legal determinations.

## 2. Frozen E1 class boundary

### Base detector

- `person`
- `phone`
- `laptop`
- `television`
- `keyboard`
- `mouse`
- `remote`
- `book`

### Specialist detector

- `wrist_device`
- `earbud`
- `tablet`
- `paper_note`
- `calculator`

Derived-only evidence such as `additional_person`, `partial_person`, and `screen_signal` remains outside detector training labels.

Do not collapse visually different classes merely because exam policy prohibits several of them. In particular:

```text
remote != phone
calculator != phone
book != paper_note
bracelet/jewelry != wrist_device
```

## 3. Required provenance

Every V1 image must retain a stable `source_group_id` and explicit source provenance.

### Synthetic media

Record at least:

- `kind = synthetic`
- `source_id`
- `generator_provider`
- exact `generator_model_id`
- `generation_id`
- optional `prompt_id`

Images generated from the same prompt/seed/batch or intentionally near-duplicate scene family should share a source-group boundary when leakage would otherwise occur.

### Open-source dataset / openly licensed media

Record at least:

- `kind = open_source_dataset` or `openly_licensed_media`
- `source_id`
- `source_name`
- original `source_item_id`
- recorded `license`
- optional `source_ref`

If the source item came from a video, burst, sequence, or near-duplicate collection, preserve that grouping. Do not invent a new group per extracted frame.

## 4. Why source groups still matter

V1 may be non-physical, but leakage is still dangerous.

Examples:

- several frames extracted from the same open video;
- synthetic variants generated from one scene with tiny changes;
- duplicate images mirrored across public datasets;
- the same original image appearing at several resolutions.

Near-related material must not be split across train, validation, and test simply because filenames differ.

The invariant remains:

```text
one source_group_id -> one split only
```

## 5. Teacher workflow

The preferred V1 pipeline is:

```text
synthetic/open-source/openly licensed media
    -> provenance + source-group registration
    -> candidate / box proposal
    -> independent teacher reviews
    -> strict teacher consensus
        -> accepted V1 evidence
        -> disagreement / UNKNOWN -> quarantine
    -> canonical ingest
    -> source-group-safe train/validation/test datasets
    -> local-model training/evaluation
```

Teacher examples may include:

- OpenAI / ChatGPT
- Anthropic / Claude
- Google / Gemini
- Moonshot / Kimi
- other independent providers suitable for the task

The code does not hard-code vendor names. Independence is counted by provider identity.

## 6. Strict consensus rule

A V1 candidate is eligible only when:

- at least three distinct effective teacher providers participated;
- all effective decisions agree exactly;
- no teacher returned `unknown`;
- aliases are not guessed;
- the agreed class is canonical for the model role;
- canonical objects have one explicit geometry proposal with exact proposer provenance;
- teacher boxes are not fused or averaged;
- repeated calls from one provider do not create fake independence.

Any disagreement, UNKNOWN, insufficient independent review, missing geometry, or incomplete provenance routes the item to quarantine.

## 7. Train, validation, and test without V1 human annotation

Version 1 may run without a project-owned human annotation campaign.

However, the evidence tiers must be named correctly.

### Train

Strict teacher-consensus annotations are labeled:

```text
label_quality = silver
```

They may be used for V1 model training.

### Validation and test

Held-out validation/test material may also be labeled by the strict independent teacher-consensus process. These labels are called:

```text
label_quality = teacher_consensus_eval
```

They are **not** gold and **not** human ground truth.

Metrics measured against them are useful for provisional V1 development, regression checking, model comparison, and deciding whether the pipeline is improving. They must not be presented as final human-grounded accuracy.

A future human-verified evaluation set can upgrade the evidence quality without changing the detector taxonomy.

## 8. Synthetic data requirements

Synthetic data should deliberately cover visual diversity rather than repeatedly generating easy centered objects.

Useful dimensions include:

- lighting variation;
- camera angle and distance;
- partial occlusion;
- small-object scale;
- desk clutter;
- different skin tones and clothing;
- realistic examination rooms;
- object orientation;
- object in hand versus on desk;
- several objects in one scene;
- low-quality webcam appearance where still interpretable.

Synthetic data should also target confusion pairs and hard negatives:

- phone vs remote;
- phone vs calculator;
- wrist device vs bracelet/jewelry;
- earbud vs earring;
- loose paper vs book;
- tablet vs laptop/phone-like rectangles;
- background rectangles vs television.

Synthetic media must remain explicitly marked as synthetic. Do not describe generated examples as real captured evidence.

## 9. Open-source data requirements

Open-source/publicly available material is valuable because it supplies real visual variation that synthetic generation may miss.

Before use:

- verify and record the actual license/terms;
- retain original source identity;
- preserve near-duplicate grouping;
- avoid accidental train/test duplication across multiple datasets;
- normalize only to the frozen K-SLAS taxonomy;
- quarantine ambiguous source labels instead of guessing mappings.

An original dataset label does not automatically become a K-SLAS canonical label. Teacher review/normalization still applies.

## 10. Geometry

YOLO-style detector training requires bounding boxes.

A development-time proposal system such as Grounding DINO or another suitable vision model may propose candidate boxes. Another development-time system may check them.

The V1 resolver requires one explicit geometry proposal per accepted canonical candidate with:

- provider;
- exact model ID;
- proposal ID;
- full-image normalized `[x, y, width, height]` box.

The resolver does not invent an IoU threshold and does not automatically average/fuse teacher boxes.

## 11. Data tier and claim discipline

Use these terms consistently:

| Tier | Meaning |
| --- | --- |
| `silver` | teacher-consensus training annotation |
| `teacher_consensus_eval` | held-out validation/test annotation created by the same strict teacher methodology; not human ground truth |
| `gold` | explicitly human-verified annotation |
| `field` | real exam evidence plus invigilator review/provenance for later curation |

V1 can proceed with `silver` + `teacher_consensus_eval`.

Do not call teacher-consensus evaluation "gold accuracy," "human accuracy," or final production calibration.

## 12. V1 -> V2 learning loop

The intended progression is:

```text
V1 synthetic/open-source/openly licensed data
    -> strict multi-teacher labels
    -> train local E1 Base + Specialist models
    -> live exam uses local models only
    -> AI submits evidence/events for invigilator review
    -> confirmed / false-positive / wrong-class / uncertain feedback
    -> curated field evidence
    -> Version 2 dataset improvement
```

Invigilator review is operational human evidence, but it should still be curated before becoming V2 training truth. Preserve reviewer/provenance information and do not assume every field response is error-free.

## 13. Current executable boundary

Use:

```powershell
python -m ai_runtime.e1_v1_dataset_resolution --pretty `
  data/teacher/e1_report.json `
  data/teacher/e1_v1_request.json `
  data/staging/e1_v1_staging.json
```

The request must include the non-physical source provenance defined above.

Routes are explicit:

```text
train       -> silver_train
validation  -> teacher_consensus_validation
test        -> teacher_consensus_test
failure     -> quarantine
```

The emitted staging remains compatible with the existing annotation-ingest boundary.

## 14. What is deferred, not deleted

The existing physical E1 acquisition protocol remains useful for:

- future controlled physical studies;
- field-error reproduction;
- difficult classes underrepresented in public/synthetic sources;
- Version 2/Version 3 improvement;
- device-specific or institution-specific calibration studies.

It is simply **not a prerequisite for Version 1**.

## 15. Hard rules

1. Live exam AI remains local-only.
2. External/foundation teachers are development-time only.
3. V1 does not require project-owned physical capture.
4. Internet availability is not treated as permission; source licensing is recorded and never guessed.
5. Synthetic provenance is recorded explicitly.
6. Three distinct effective teacher providers are required for accepted V1 labels.
7. UNKNOWN and disagreement are quarantined.
8. Teacher confidence is not treated as calibrated probability.
9. Teacher geometry is not automatically fused.
10. Train silver data and teacher-consensus evaluation data remain distinct evidence tiers.
11. Teacher-consensus validation/test is not called gold or final human-grounded accuracy.
12. Source-group leakage remains forbidden.
13. No misconduct or punishment conclusion is produced by the dataset pipeline.
14. Invigilator-reviewed field evidence is reserved for curated V2 improvement.

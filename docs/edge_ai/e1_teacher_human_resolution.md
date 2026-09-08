# E1 Teacher Review -> Human Resolution -> Annotation Staging

## Purpose

This stage closes the development-time loop between external teacher models and the frozen E1 annotation-ingest contract.

The intended flow is:

```text
source image
  -> ChatGPT / Claude / Gemini / Qwen / other development-time teachers
  -> provider-neutral teacher packet
  -> e1_teacher_consensus.py
  -> human-review report
  -> explicit human resolution
  -> e1_teacher_human_resolution.py
  -> annotation staging
  -> e1_annotation_ingest.py
  -> canonical dataset manifest
```

None of these external teacher systems are part of live exam inference. All live E1 intelligence remains local on the candidate device.

## Hard rule: consensus is not ground truth

A teacher report may say `teacher_agreement`, but this tool still requires an explicit human review for every candidate.

The human reviewer may:

- approve a canonical class and draw/correct the full-image bounding box;
- decide `no_object` when no trainable object exists at the candidate location;
- `exclude_candidate` when the candidate should not contribute an annotation;
- leave a candidate `unresolved`.

If any candidate is unresolved, no annotation staging file is emitted.

The human reviewer is also allowed to correct unanimous teacher agreement. Example:

```text
ChatGPT -> phone
Claude  -> phone
Gemini  -> phone
Human   -> remote
```

The final reviewed class is `remote`, provided it belongs to the declared E1 training role and the reviewer supplies valid geometry.

## Why the tool refuses partial export

A dangerous shortcut would be:

```text
review the easy candidate
ignore the ambiguous candidate
export the rest automatically
```

That silently turns uncertainty into absence.

Instead, every candidate in the teacher report must receive one explicit human decision before the image can move forward.

`unresolved` means exactly that: the image is not ready for annotation ingest.

## Source provenance remains independent of teacher models

Teacher systems do not decide the source group.

`source_group_id` comes from the collection workflow and is supplied explicitly by the human-review resolution packet. It is never inferred from filenames, teacher answers, or model metadata.

That protects the later train/validation/test leakage boundary.

## Review schema

The human review file uses `review_schema_version: 1.0`.

Required top-level fields:

- `review_schema_version`
- `review_packet_id`: must exactly equal the teacher report `packet_id`
- `dataset_id`
- `dataset_version`
- `split`: `train`, `validation`, or `test`
- `source_group_id`
- `image`
- `candidate_reviews`
- optional `negative_tags`

The image identity must exactly match the teacher report:

```json
{
  "image_path": "images/session-001/frame-0001.jpg",
  "width": 1920,
  "height": 1080
}
```

The resolver refuses path or dimension mismatches.

## Candidate decisions

### Canonical

A canonical decision requires:

- `candidate_id`
- `reviewer_id`
- `decision: canonical`
- `canonical_object_id`
- `bbox_xywh_normalized`

Example:

```json
{
  "candidate_id": "candidate-phone-001",
  "reviewer_id": "reviewer-001",
  "decision": "canonical",
  "canonical_object_id": "phone",
  "bbox_xywh_normalized": [0.34, 0.42, 0.09, 0.16]
}
```

The box is always relative to the original full image, not an annotation crop or specialist ROI.

### No object

Use when the reviewer determines that the candidate does not correspond to a trainable object for this image.

```json
{
  "candidate_id": "candidate-phone-002",
  "reviewer_id": "reviewer-001",
  "decision": "no_object"
}
```

No class or geometry is allowed with this decision.

### Exclude candidate

Use when the candidate itself should not become an annotation, for example because the candidate region is unusable for this labeling task.

```json
{
  "candidate_id": "candidate-ambiguous-003",
  "reviewer_id": "reviewer-001",
  "decision": "exclude_candidate"
}
```

This does not invent a negative label. It simply excludes that candidate.

### Unresolved

Use when the reviewer cannot defensibly decide.

```json
{
  "candidate_id": "candidate-ambiguous-004",
  "reviewer_id": "reviewer-001",
  "decision": "unresolved"
}
```

Any unresolved candidate blocks staging output.

## Canonical vocabulary boundary

The resolver uses the same frozen E1 training roles.

Base:

- `person`
- `phone`
- `laptop`
- `television`
- `keyboard`
- `mouse`
- `remote`
- `book`

Specialist:

- `smartwatch`
- `earbud`
- `tablet`
- `paper_note`
- `calculator`

Semantic aliases are not guessed. For example, `cell phone` is not silently converted to `phone`.

## Output

A successful resolution emits a normal `e1_annotation_ingest.py` staging document containing exactly one reviewed image record.

Example shape:

```json
{
  "ingest_schema_version": "1.0",
  "dataset_id": "e1-controlled-pilot",
  "dataset_version": "2026.09.1",
  "model_role": "base",
  "split": "train",
  "records": [
    {
      "source_group_id": "session-001",
      "image_path": "images/session-001/frame-0001.jpg",
      "width": 1920,
      "height": 1080,
      "negative_tags": [],
      "annotations": [
        {
          "canonical_object_id": "phone",
          "bbox_xywh_normalized": [0.34, 0.42, 0.09, 0.16]
        }
      ]
    }
  ]
}
```

The existing annotation-ingest tool then performs its own canonical validation and deterministic ID generation.

## Commands

First evaluate imported teacher responses:

```powershell
python -m ai_runtime.e1_teacher_consensus --pretty data/teacher/packet.json data/teacher/report.json
```

Then resolve the report with a real human-review file:

```powershell
python -m ai_runtime.e1_teacher_human_resolution --pretty data/teacher/report.json data/teacher/human_review.json data/staging/reviewed_image.json
```

Finally pass the emitted staging file through the existing ingest boundary:

```powershell
python -m ai_runtime.e1_annotation_ingest --pretty data/staging/reviewed_image.json data/e1/base/reviewed_image_manifest.json
```

## Truth boundary

This workflow does not:

- call ChatGPT, Claude, Gemini, or any other external model automatically;
- treat teacher agreement as ground truth;
- use teacher confidence as calibrated probability;
- average teacher bounding boxes;
- infer source groups;
- infer split assignment;
- invent reviewer identity;
- make misconduct decisions;
- change the frozen live E1 runtime.

Its only purpose is to convert explicit, reviewed development-time evidence into a format that the existing dataset pipeline can validate.

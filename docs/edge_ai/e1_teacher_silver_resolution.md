# E1 V1 Silver Bootstrap Training Path

## Purpose

This document defines a **development-time-only** V1 bootstrap path that allows strictly agreed multi-provider teacher labels to enter the **training split as silver labels** without first converting them into human-approved ground truth.

This does **not** change the live-exam architecture:

```text
live exam inference -> local K-SLAS edge AI only
```

ChatGPT/OpenAI, Claude/Anthropic, Gemini/Google, Kimi/Moonshot, Grounding DINO, Florence-2, or any other external/foundation teacher remain development-time tools only. They are never required or contacted during a live exam.

The existing human-resolution path remains unchanged and is still the route for **gold/human-verified data**. The silver path is additive, not a replacement.

## Data tiers

K-SLAS now distinguishes three evidence tiers:

- **silver** — strict multi-provider teacher consensus used only for V1 training bootstrap;
- **gold** — explicitly human-verified annotations used for validation/test and other ground-truth evaluation needs;
- **field** — invigilator-reviewed real exam events collected after deployment and considered for later V2 dataset construction.

Silver is never described as ground truth.

## Strict silver eligibility

A candidate can enter silver training only when all of the following are true:

1. the teacher consensus report is valid;
2. the candidate is already `teacher_agreement`;
3. at least **three distinct effective providers** supplied decisions;
4. all effective decisions agree exactly;
5. no teacher returned `unknown`;
6. aliases are not guessed — the agreed class must already be canonical for the model role;
7. the teacher report's effective-provider count and suggested decision remain internally consistent;
8. a canonical candidate has one explicit geometry proposal with exact proposer provenance;
9. the output split is `train` only.

Repeated calls from the same provider do not count as independent providers.

Examples of independent providers may include OpenAI, Anthropic, Google, and Moonshot/Kimi. The code does not hard-code vendor names; it checks distinct provider identities and exact model provenance supplied in the teacher report.

## UNKNOWN and disagreement

UNKNOWN remains UNKNOWN.

If any teacher returns `unknown`, if effective teachers disagree, if there are fewer than three effective providers, or if required geometry/provenance is missing, the silver resolver fails closed and returns:

```text
route = quarantine
```

No staging file is emitted for that image.

This is deliberate. The bootstrap path does not force majority labels and does not repair uncertainty by guessing.

## Geometry rule

The silver path does **not** average, fuse, rank, or auto-select teacher bounding boxes.

For each canonical candidate, the silver request must provide exactly one explicit full-image normalized geometry proposal:

```text
bbox_xywh_normalized = [x, y, width, height]
```

and exact proposer provenance:

- `provider`
- `model_id`
- `proposal_id`

A practical development workflow may use Grounding DINO as a candidate/box proposer and another development-time vision system such as Florence-2 as a checker, but this module does not call either model. It only validates already-collected proposal metadata.

No IoU threshold is invented and no teacher geometry fusion is performed.

## Train-only boundary

Silver annotations are allowed only in:

```text
split = train
```

The module rejects `validation` and `test` silver requests.

Validation/test data should remain human-verified/gold so V1 performance is not measured against labels created by the same teacher process used to bootstrap training.

## Negative examples

A `no_object` teacher agreement is candidate-level, not automatically an image-level negative label.

If an image produces no canonical silver annotations, the request must carry explicit `negative_tags` before an empty training record can be emitted. This prevents the system from inventing a whole-image negative meaning from candidate-level no-object votes.

## Audit metadata

Successful staging includes a `silver_audit` block that records:

- `label_quality = silver`;
- `human_verified = false`;
- teacher packet identity;
- the minimum effective-provider rule;
- accepted teacher provider/model provenance;
- geometry proposer provenance;
- the fact that teacher consensus is not ground truth;
- the fact that live external AI is forbidden.

The staging remains compatible with `e1_annotation_ingest.py`. The archived staging/audit file is the development-time provenance record for the silver decision.

## CLI

```powershell
python -m ai_runtime.e1_teacher_silver_resolution --pretty `
  data/teacher/e1_report.json `
  data/teacher/e1_silver_request.json `
  data/staging/e1_silver_staging.json
```

Inputs:

1. the output of `e1_teacher_consensus`;
2. a silver request containing dataset/split/source-group/image identity and geometry proposals.

Output:

- success: `route = silver_train` plus ingest-compatible staging;
- failure: `route = quarantine` and no staging output.

## Relationship to the existing human path

`e1_teacher_human_resolution.py` is intentionally preserved.

Use it when creating human-approved/gold annotations. It continues to require explicit human decisions for every candidate and is not weakened by the silver-bootstrap feature.

The earlier teacher-consensus rule that teacher agreement is **not ground truth** remains fully true. V1 silver is a separately marked bootstrap label tier, not human-approved ground truth.

## V1 -> V2 learning loop

The intended progression is:

```text
physical capture
    -> candidate/geometry proposal
    -> OpenAI / Anthropic / Google / Moonshot-Kimi / other teacher review
    -> strict silver resolver
        -> agreement: silver TRAIN data
        -> unknown/disagreement: quarantine
    -> train local E1 V1
    -> live local E1 raises evidence only
    -> invigilator reviews evidence
    -> confirmed / false-positive / wrong-class / uncertain field feedback
    -> curated human-reviewed V2 training pool
```

Invigilator feedback must not be treated as automatically clean training truth simply because it came from production. V2 curation should retain reviewer identity/provenance and quality checks.

## Hard rules

1. Live exam AI remains local-only.
2. External teachers are development-time only.
3. Silver labels are never called ground truth.
4. Silver is train-only.
5. Gold validation/test remains human-verified.
6. At least three distinct effective teacher providers are required for silver acceptance.
7. UNKNOWN and disagreement are quarantined.
8. Repeated calls from one provider do not create independence.
9. Teacher self-reported confidence is not used as calibrated probability.
10. Teacher boxes are not fused or auto-selected.
11. Canonical classes only; aliases are not guessed.
12. No misconduct/punishment conclusion is created by this workflow.
13. The existing human-resolution path remains available and unchanged.

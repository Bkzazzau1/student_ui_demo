# E1 Independent Review: Teacher Consensus -> Human Resolution -> Annotation Ingest

## Scope

This review independently audited the development-time path from external teacher-model
review through mandatory human resolution into the frozen canonical annotation-ingest
boundary:

- `docs/edge_ai/e1_object_taxonomy.md`
- `docs/edge_ai/e1_teacher_consensus.md`
- `docs/edge_ai/e1_teacher_human_resolution.md`
- `docs/edge_ai/e1_annotation_ingest.md`
- `ai_runtime/e1_teacher_consensus.py`
- `ai_runtime/e1_teacher_human_resolution.py`
- `ai_runtime/e1_annotation_ingest.py`
- `ai_runtime/tests/test_e1_teacher_consensus.py`
- `ai_runtime/tests/test_e1_teacher_human_resolution.py`
- `ai_runtime/tests/test_e1_annotation_ingest.py`

This review did not touch the frozen live E1 runtime, does not add any external API
calls, credentials, or cloud dependency, and did not change `e1_annotation_ingest.py`
(inspected and found already correct).

## VERIFIED defect (fixed)

### Single-provider repeated calls could masquerade as multi-provider `teacher_agreement`

**File:** `ai_runtime/e1_teacher_consensus.py`, `_evaluate_candidate`.

The documented rule (`e1_teacher_consensus.md`, sections 8 and 18-9) is explicit:

> `teacher_agreement`: At least two independent teacher providers supplied **effective**
> decisions and all effective decisions agree, with no UNKNOWN vote.
>
> `insufficient_review`: ... Multiple model calls from the same provider do not pretend
> to be independent multi-provider consensus.

The implementation instead gated the "at least two providers" check on `provider_count`,
which was computed from **all** votes on the candidate, including `abstain`/`unknown`
votes. This let a candidate reach `teacher_agreement` when only one provider actually
rendered an effective judgment, as long as some other provider was represented at all
(even by abstaining) and the one effective provider had submitted more than one vote
(e.g. two different `teacher_id` configurations for the same provider).

**Reproduced before the fix** (see verification below): one provider abstains, a second
provider votes `canonical: phone` twice under two different `teacher_id`s ->
`status: teacher_agreement`, `suggested_decision: phone`. This is exactly the scenario
the doc says must never happen, because it would hand a human reviewer a false signal
of independent corroboration for what is actually one provider's opinion repeated.

**Fix:** added `effective_provider_count`, the number of distinct providers among votes
that are not `abstain`/`unknown`, and require it to be `>= 2` before a candidate can
reach `teacher_agreement`. If only one provider's votes are effective, the candidate now
correctly resolves to `insufficient_review`, regardless of how many total providers (or
repeat calls) are represented on the candidate. The new count is also exposed in the
report as `teacher_effective_provider_count` for auditability, since it can now diverge
from the pre-existing `teacher_provider_count` field precisely in the cases this fix
targets.

**Verification before the fix** (via `python -c`, not committed):

```
issues: ()
status: teacher_agreement
suggested_decision: {'decision': 'canonical', 'canonical_object_id': 'phone'}
provider_count: 2
```

**Regression test added:** `test_repeated_calls_from_one_effective_provider_are_not_agreement`
in `ai_runtime/tests/test_e1_teacher_consensus.py`. All 14 tests in that file pass after
the fix, and the full `ai_runtime` suite (104 tests) passes with no regressions.

## Areas inspected and found already correct (no change made)

- **UNKNOWN/disagreement preservation** — any `unknown` vote forces `needs_human_review`
  regardless of other agreement; disagreement between canonical classes is never
  collapsed to a majority vote. Confirmed by existing tests and re-verified.
- **No confidence weighting, no geometry fusion** — neither module reads or propagates a
  `confidence` field; teacher boxes are carried through unmodified per-vote, never
  averaged or selected as "best." Confirmed by code inspection and
  `test_teacher_confidence_field_is_not_used_or_propagated`.
- **Canonical vocabulary boundary** — both modules validate `canonical_object_id` against
  the exact frozen base/specialist class lists and reject any value outside them,
  including known aliases (e.g. `cell phone`); no alias is silently promoted. This
  correctly mirrors the boundary already enforced in `e1_annotation_ingest.py`.
- **Human resolution is mandatory and cannot be partially bypassed** — every
  `candidate_id` present in the teacher report must receive an explicit human decision;
  a missing or `unresolved` decision blocks staging output entirely (verified: no
  output file is written). Teacher `suggested_decision`/`status` fields are not read by
  `build_annotation_staging` at all — the human reviewer's decision is the only input
  that reaches the staging record, so a human correcting unanimous teacher agreement
  works exactly as documented.
- **Source-group provenance never inferred** — `source_group_id` is read only from the
  explicit human-review file, never from the teacher report, image path, or model
  metadata. Confirmed by code inspection and
  `test_source_group_is_required_and_never_inferred`.
- **Geometry contract** — both modules normalize and bound-check `bbox_xywh_normalized`
  identically to `e1_annotation_ingest.py`'s own geometry validator (same epsilon,
  same full-image-relative semantics), and reject geometry attached to any non-canonical
  decision (`no_object`, `exclude_candidate`, `unresolved`).
- **Fail-closed I/O** — both CLIs refuse to overwrite an existing output file without
  `--force`, and never write partial/invalid output (verified via existing tests plus a
  read of `resolve_files`/`review_teacher_file`).
- **Example fixtures** — every `docs/edge_ai/examples/*teacher*` JSON file carries
  `"example_only": true`. The one fixture the docs actually reference as a runnable
  format example (`e1_teacher_consensus.example.json`) was executed against the real
  evaluator and produces exactly the statuses the doc's own worked examples describe.

## Suggestions (not implemented; not defects)

- **Cross-candidate duplicate-object risk.** If two different `candidate_id`s in the same
  image are independently approved by a human reviewer as the same physical object with
  slightly different geometry, both become separate annotations; the exact-duplicate
  check in `e1_annotation_ingest.py` only catches identical class+box pairs, not
  near-duplicates. The teacher-consensus doc explicitly declines to invent a geometric
  matching/IoU policy at this stage ("We have not scientifically calibrated such a
  threshold yet... the current stage does not invent one"), so this is a known,
  deliberately deferred limitation rather than a defect to fix now. Flagging it here so
  it is tracked for the candidate-generation stage rather than lost.

## Remaining work requiring scientific/data validation (unchanged by this review)

Per `docs/edge_ai/e1_runtime_training_readiness.md`, this review does not, and cannot,
supply: real dataset acquisition, real teacher-model API integration, human review
throughput/quality validation, held-out evaluation, confidence calibration, or device
acceptance. All synthetic/example data referenced above remains explicitly
`example_only` and is not presented as training evidence.

## Test results

```
python -m unittest discover -s ai_runtime/tests -v
Ran 104 tests in 0.299s
OK
```

No skipped tests in this run (this branch does not include the optional numerical
tooling suite present on other E1 branches).

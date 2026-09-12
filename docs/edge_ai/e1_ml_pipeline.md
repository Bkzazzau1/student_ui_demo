# E1 development ML pipeline

E1 runtime architecture is complete. Real model training, calibration and
device acceptance remain pending. None of these tools is imported by the live
exam runtime. There are no hosted AI calls. Rust still owns tracking and
spatiotemporal memory; the Python scenario checker only inspects Rust output.

## Starting point and review

PR [#15](https://github.com/Bkzazzau1/student_ui_demo/pull/15) was already merged
when this work began, at `908ab73b96ee753935593ad58a39ed30fadd8c2a`.
Its head `9d79aef6e14a1636b89dab09bf345f0c49d1c4d0` was six commits ahead of
pre-merge main, with no commits behind. The six changed files were the dataset
CLI, its tests, README, readiness document and two explicitly synthetic examples.
Foundation run [34150661199](https://github.com/Bkzazzau1/student_ui_demo/actions/runs/34150661199)
passed Python contracts, Rust formatting and the full Rust suite on that head.

The new work starts from main `59b3643`, which also includes canonical annotation
ingestion, source-group split planning and reproducible YOLO package export.
Use those tools instead of creating a second ingestion or class-mapping system:

- [Annotation ingestion](e1_annotation_ingest.md)
- [Source-group split planning](e1_dataset_splitting.md)
- [Training package export](e1_training_export.md)

## Installation and boundaries

Use a separate development environment. Python 3.12 is the test target.

```powershell
python -m venv build/e1-ml-env
build/e1-ml-env/Scripts/python -m pip install -r ai_runtime/requirements-e1-numerical.txt
build/e1-ml-env/Scripts/python -m ai_runtime.e1_ml_pipeline --help
```

Training, checkpoint parity and export additionally require a locally installed
Ultralytics 8.x/PyTorch environment compatible with the chosen local YOLOv8-style
detect architecture. Install and lock those versions in the experiment environment;
they are deliberately not live application dependencies. The training command
records framework versions and Ultralytics also writes resolved arguments in
`fit/args.yaml`. Numerical tests use synthetic graphs and a stand-in Python
reference; they do **not** test a trained checkpoint or establish model accuracy.

No command downloads a checkpoint. Supply a local architecture YAML or trusted
local checkpoint for training, and a trained local `.pt` file for export.
Framework telemetry integrations are disabled by the adapter. For an isolated
development experiment, preinstall dependencies and run without network access.

All outputs must be new paths. Keep real images, annotations, tensors, weights,
and reports in controlled data storage or the ignored `build/` directory, outside
source control. Failed runs may leave their request/output directory for diagnosis;
use a new output path for the next run.

## Train each role

Copy `ai_runtime/configs/e1_base_training.json` or
`ai_runtime/configs/e1_specialist_training.json` into your experiment directory.
Fill `checkpoint`, `epochs`, `batch`, `imgsz`, `seed`, `device` and
`experiment_basis`. Nulls are intentional: no architecture, experimental budget,
or confidence threshold has been selected without data. `imgsz` is a positive
square input dimension. Use a local architecture/checkpoint whose exported output
is the frozen YOLOv8 `[1, 4+C, N]` tensor; newer end-to-end detector layouts are
not silently accepted.

`hyperparameters` accepts explicit numeric optimization/augmentation overrides:
`lr0`, `lrf`, `momentum`, `weight_decay`, `warmup_epochs`, `hsv_h`, `hsv_s`,
`hsv_v`, `degrees`, `translate`, `scale`, `shear`, `perspective`, `flipud`,
`fliplr`, `mosaic`, `mixup`. Other training settings use the installed framework's
recorded defaults. Extra data paths, remote integrations and resume arguments
cannot be injected through this map.

```powershell
python -m ai_runtime.e1_ml_pipeline train --config work/base-training.json --package work/base-yolo --output work/base-run-1
python -m ai_runtime.e1_ml_pipeline train --config work/specialist-training.json --package work/specialist-yolo --output work/specialist-run-1
```

The package gate verifies canonical class order, real train/validation class
support, image hashes, YOLO label geometry, split paths, duplicate sample IDs,
source-group leakage and identical-image leakage. Unlisted files in scanned
image/label directories are rejected. The request records hashes of images and
labels actually consumed. Empty labels remain negatives; hard-negative tags
remain in the export manifest. An image hash is not proof of annotation quality.

The generated absolute-path dataset YAML avoids resolving the existing package's
`path: .` against a framework-global dataset directory. Successful training writes
`training_result.json` with `trained_not_validated`, checkpoint hash and request
hash. It never changes model assets or sets `installed: true`.

## ONNX export and input preparation

```powershell
python -m ai_runtime.e1_ml_pipeline export-onnx --checkpoint work/base-run-1/fit/weights/best.pt --role base --size $InputSize --model-id e1-base --version $ExperimentVersion --output work/base.fp32.onnx
python -m ai_runtime.e1_ml_pipeline prepare-tensors --manifest data/base/validation.json --size $InputSize --preprocessing stretch_nn_rgb01 --output work/base-validation.npz
```

Export validates exact checkpoint class order and a static single input/output:
float32 NCHW `[1,3,H,W]`, pixel-center `cx,cy,w,h` followed by class probabilities
in `[1,4+C,N]`. Export disables embedded NMS, dynamic shapes and simplification.
The adjacent JSON records model ID/version, weights and ONNX hashes, tensor names,
shapes, class order and pending installation. This is an experimental candidate.

`prepare-tensors` decodes local images, checks annotation dimensions, applies
explicit nearest-neighbor floor-index stretching and RGB/255, and writes NPZ:

| Key | Content |
|---|---|
| `inputs` | float32 `[samples,3,H,W]` |
| `rois` | normalized full-frame `[x,y,width,height]` per sample |
| `sample_ids` | unique strings, exactly matching the manifest |
| `manifest_sha256` | SHA-256 of canonical sorted JSON, from `fingerprint()` |
| `image_sha256` | original image byte hashes |
| `split` | train, validation or test |
| `preprocessing` | `stretch_nn_rgb01` |

The builder emits full-frame ROIs. For specialist ROI studies, supply recorded
native crop tensors with their **actual applied** normalized ROIs and original
sample IDs in the same NPZ contract. One tensor per manifest sample is supported;
multiple crops per frame need an externally recorded aggregate prediction export.
Do not substitute an empty prediction for an unscheduled crop.

**Native acceptance blocker:** the inspected Windows
`OptimizedVisionRuntimeEngine::BuildInputTensor` currently performs RGB
normalization to `[-1,1]`. A YOLO experiment using `[0,1]` inputs does not prove
compatibility with that path. Other native paths must also be checked separately.
The Python reference uses explicit pixel coordinates and class-aware NMS; native
heuristics, top-k limits and tie handling must be compared with the reference.
This change leaves the frozen runtime untouched and manifests uninstalled.

## Prediction and held-out metrics

```powershell
python -m ai_runtime.e1_ml_pipeline predict-tensors --model work/base.fp32.onnx --metadata work/base.fp32.json --fixture work/base-validation.npz --manifest data/base/validation.json --score-floor $EvaluationScoreFloor --nms-iou $EvaluationNmsIou --provider CPUExecutionProvider --output work/base-predictions.json
python -m ai_runtime.e1_ml_pipeline evaluate --manifests data/base/train.json data/base/validation.json data/base/test.json --predictions work/base-predictions.json --operating-confidence $EvaluationOperatingPoint --output work/base-evaluation.json
```

The variables are explicit experimental parameters supplied by the investigator,
not production class thresholds. Keep score floor, NMS and operating point the
same when comparing model/precision variants. AP integrates the score-ranked
predictions that were retained above the recorded floor; a high floor can distort
AP. Report that limitation when interpreting results.

External Python/native prediction exporters may produce the same JSON contract:
`model_id`, `model_version`, `model_sha256`, ordered `class_names`, `split`,
`manifest_sha256`, `prediction_basis`, `score_floor` and `samples`.
`samples` maps **every** manifest sample ID to a list of detections, each with
`canonical_object_id`, `confidence` and normalized top-left
`bbox_xywh_normalized`. An empty list means completed inference with no detection.
Missing samples, nulls and UNKNOWN are rejected, not scored as absence.

Evaluation checks the combined train/validation/test group boundary. It exports
per-class support, precision, recall, F1, AP50 and AP50:95 plus tagged-image
false-positive rates. Predictions are greedily matched one-to-one in descending
confidence order at each IoU; duplicate detections cannot share a truth box.
Precision/recall/F1 and hard negatives use the supplied operating point at IoU .50.
AP uses 101 recall points at IoUs .50 through .95 in .05 increments, all areas,
unlimited detections, with no crowd/ignore semantics. This is an explicitly
documented evaluator, **not a claim of exact COCO evaluation equivalence**.

Hard-negative false-positive rate is the fraction of tagged images with any
unmatched prediction, across the role's classes. A tagged image may also contain
annotated permitted objects; matched predictions are not false positives.
Zero-support classes get null recall/F1/AP and `evaluation_valid: false`, with a
nonzero CLI exit after saving the diagnostic report. They never become validated.
Nonzero support establishes report eligibility, not sufficient scientific quality.

## Ingest measured calibration

Supply a JSON evidence object containing the exact `model_id`, `model_version`,
`model_sha256`, `model_role`, `split: "validation"`, validation
`manifest_sha256`, a nonempty `selection_basis` describing the actual experiment,
and `thresholds` mapping every role class to its measured selected value.

```powershell
python -m ai_runtime.e1_ml_pipeline ingest-calibration --report work/base-evaluation.json --evidence work/measured-calibration.json --manifests data/base/train.json data/base/validation.json data/base/test.json --output work/base-calibrated-report.json
```

The evidence must identify the same model and dataset collection. Each class
needs validation support. Test data cannot be used to select thresholds.
The tool validates declared provenance; it cannot establish that an investigator's
selection basis is scientifically sound. No threshold sweep is guessed here.
Ingestion preserves the original evaluation metrics and their operating point;
it does not claim those metrics were measured at the newly selected thresholds.
Retain an untouched test set for final assessment after all model/threshold choices.

## Parity and precision variants

```powershell
python -m ai_runtime.e1_ml_pipeline parity --model work/base.fp32.onnx --checkpoint work/base-run-1/fit/weights/best.pt --metadata work/base.fp32.json --fixture work/base-validation.npz --atol $MeasuredToleranceAbs --rtol $MeasuredToleranceRel --confidence $EvaluationOperatingPoint --nms-iou $EvaluationNmsIou --output work/base-parity.json
python -m ai_runtime.e1_ml_pipeline quantize --model work/base.fp32.onnx --metadata work/base.fp32.json --precision fp16 --output work/base.fp16.onnx
python -m ai_runtime.e1_ml_pipeline quantize --model work/base.fp32.onnx --metadata work/base.fp32.json --precision int8 --fixture work/representative-train.npz --output work/base.int8.onnx
python -m ai_runtime.e1_ml_pipeline benchmark --model work/base.fp32.onnx --fixture work/base-validation.npz --provider CPUExecutionProvider --warmup $WarmupRuns --repeats $MeasuredRepeats --output work/base-fp32-benchmark.json
```

Parity runs checkpoint and ORT CPU inference on the same recorded tensors, checks
raw shape/value agreement, then checks class identities, confidence, NMS boxes
and ROI remapping using the Python reference. Tolerances and operating points
must be explicitly provided and retained with the result. This does not validate
camera YUV/BGRA conversion, native resize/normalization, native decoder/NMS,
tracking or native ROI crop rounding. Record native outputs for those checks.

FP16 conversion keeps float32 external I/O. INT8 uses static QDQ quantization and
requires representative **training-split** tensors, distinct from scientific
confidence calibration. Each variant inherits the source contract, gets a new
model hash, remains uninstalled and records its source hash. Run `predict-tensors`
and `evaluate` again with its adjacent metadata against the exact same held-out
set. Compare every class, particularly earbuds and watches. Quantization is never
accepted based only on speed. Provider support and allowable accuracy loss remain
empirical decisions. Repeat parity with variant metadata and explicitly reviewed
tolerances if the checkpoint reference is applicable.

Benchmark outputs measured inference latency mean/p50/p95/max, provider list,
iteration counts, model/fixture hashes and host/runtime identity. ORT graph
partitioning may still place unsupported operations on CPU even when another
provider is requested. This is an inference microbenchmark, not effective camera
FPS or a complete GPU/NPU device benchmark. Record CPU/RAM, accelerator utilization,
temperature, dropped frames, power and long-exam stability separately on hardware.

## Candidate manifest and offline scenario harness

```powershell
python -m ai_runtime.e1_ml_pipeline manifest --metadata work/base.fp32.json --evaluation work/base-calibrated-report.json --parity work/base-parity.json --output work/base-candidate-manifest.json
python -m ai_runtime.e1_ml_pipeline scenarios --spec work/acceptance-scenarios.json --trace work/native-trace.json --output work/scenario-check.json
```

Candidate manifests require matching model identities/hashes, nonzero held-out
support and passing recorded-tensor parity. They always contain `installed: false`
and pending acceptance items. They are review artifacts, not runtime activation
instructions, and never modify the bundled specialist manifest. Per-class
calibration is preserved; no global fallback threshold is invented.

The offline harness consumes a real native trace, not fabricated Python tracks.
The specification contains `cases`, each with a unique `case_id` and nonempty
`assertions`. Supported assertions:

| `kind` | Required fields and check |
|---|---|
| `event` | `event_id`, `class_id`; optionally exact `session_id`, `source_frame_id`, `capture_timestamp_ns` |
| `same_track` | two or more distinct `event_ids`; non-null Rust tracks must be identical within one session |
| `distinct_tracks` | distinct `event_ids`; each must have a different non-null track within the session |
| `unknown` | `session_id`, `source_frame_id`; explicit UNKNOWN and no specialist events |
| `no_event` | `session_id`, `source_frame_id`, `class_id`; requires completed specialist inference |

The trace contains `scenario_sha256`, `tracker_owner: "rust"`, `native_build_id`,
`frames` (session ID, source frame ID and original monotonic capture timestamp),
`events` (unmodified `ModelEventV1` objects) and `specialist_outcomes` (session/frame,
status, evidence and event IDs). Status is `completed`, `skipped`, `unavailable`
or `failed`; every non-completed status requires `evidence: "UNKNOWN"` and an
empty event ID list. Specialist events marked by the frozen producer metadata
must be accounted for by their frame's outcome. All events are checked against
the original capture record; arrival order may differ from capture order.

Capture candidate alone/second-person entry, exit/reappearance, partial and
simultaneous people; obvious/small/hidden/brief phone and empty hand; smartwatch
vs watch, earbud vs earring, calculator/tablet/paper; laptop/monitor/book/TV;
late frames, moving-phone capture provenance and skipped specialist scenarios.
Use assertions tied to independently reviewed recorded ground truth. Include
short-disappearance same-track and second-person distinct-track cases.

The trace checker does not launch the camera application, implement Rust tracking,
prove network isolation, or manufacture recordings. Physically disconnect the
candidate workstation, run the full native pipeline, record build/model IDs and
operator evidence, then run the trace assertions. A passing JSON trace remains
`offline_device_acceptance: "pending_operator_evidence"`; no cloud service is
needed for these checks. Complete offline acceptance requires that real run.

## Verification

```powershell
python -m unittest discover -s ai_runtime/tests -v
build/e1-ml-env/Scripts/python -m unittest ai_runtime.tests.test_e1_ml_numerical -v
```

The normal Foundation suite stays dependency-light; numerical tests skip when
their optional dependencies are absent. The dedicated Foundation numerical job
installs the pinned numerical requirements and runs those tests. Fixtures are
explicitly synthetic unit tests. No dataset, model metric, calibration threshold
or device acceptance result is included as production evidence.

API references used for the development adapters:
[Ultralytics training/configuration](https://docs.ultralytics.com/usage/cfg/),
[ONNX export](https://docs.ultralytics.com/modes/export/), and
[ONNX Runtime quantization](https://onnxruntime.ai/docs/performance/model-optimizations/quantization.html).

"""Held-out detection metrics and evidence-bound calibration ingestion.

AP uses 101 recall points and IoUs 0.50:0.05:0.95, with all-area, unlimited
detections and no crowd/ignore semantics. It is not the COCO evaluator.
"""

from collections import defaultdict
from copy import deepcopy
import hashlib
import json

from .e1_ml_common import number, required
from .e1_training_export import class_order_for_role
from .e1_training_readiness import validate_dataset_manifest, validate_split_disjointness


def fingerprint(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, separators=(",", ":"),
                                     allow_nan=False).encode()).hexdigest()


def box(value):
    if not isinstance(value, dict) or set(value) != {"x", "y", "width", "height"}:
        raise ValueError("Expected normalized top-left xywh box")
    x, y, w, h = (number(value[k], k) for k in ("x", "y", "width", "height"))
    if w <= 0 or h <= 0 or x + w > 1.00000001 or y + h > 1.00000001:
        raise ValueError("Box outside image or empty")
    return x, y, w, h


def iou(a, b):
    ax, ay, aw, ah = box(a)
    bx, by, bw, bh = box(b)
    overlap = max(0, min(ax + aw, bx + bw) - max(ax, bx)) * max(
        0, min(ay + ah, by + bh) - max(ay, by))
    return overlap / (aw * ah + bw * bh - overlap)


def validate_collection(manifests):
    if not manifests or any(m.get("example_only") for m in manifests):
        raise ValueError("Real, non-example manifests are required")
    issues = [i for m in manifests for i in validate_dataset_manifest(m)]
    issues += list(validate_split_disjointness(manifests))
    if issues:
        raise ValueError("; ".join(f"{i.path}: {i.message}" for i in issues))
    for key in ("dataset_id", "dataset_version", "model_role", "taxonomy_version"):
        if len({m[key] for m in manifests}) != 1:
            raise ValueError(f"Mixed {key}")
    splits = [m["split"] for m in manifests]
    if len(set(splits)) != len(splits) or "train" not in splits:
        raise ValueError("Unique split manifests including train are required")
    ids = [s["sample_id"] for m in manifests for s in m["samples"]]
    if len(ids) != len(set(ids)):
        raise ValueError("sample_id must be unique across splits")


def _matches(predictions, truths, overlap):
    used = defaultdict(set)
    flags = []
    for sample_id, detection in predictions:
        candidates = [(iou(detection["bbox_xywh_normalized"], target), index)
                      for index, target in enumerate(truths.get(sample_id, []))
                      if index not in used[sample_id]]
        best = max(candidates, default=(0, -1))
        matched = best[0] >= overlap and best[1] >= 0
        if matched:
            used[sample_id].add(best[1])
        flags.append(matched)
    return flags


def _ap(flags, support):
    if not support:
        return None
    tp = 0
    curve = []
    for rank, hit in enumerate(flags, 1):
        tp += hit
        curve.append((tp / support, tp / rank))
    return sum(max((p for r, p in curve if r >= point / 100), default=0)
               for point in range(101)) / 101


def evaluate(manifests, predictions, operating_confidence):
    """Predictions must contain an explicit (possibly empty) list for EVERY image."""
    validate_collection(manifests)
    number(operating_confidence, "evaluation operating confidence")
    split = predictions.get("split")
    if split not in {"validation", "test"}:
        raise ValueError("Evaluation requires validation or test")
    selected = [m for m in manifests if m["split"] == split]
    if len(selected) != 1:
        raise ValueError("Missing evaluation split")
    manifest = selected[0]
    if predictions.get("manifest_sha256") != fingerprint(manifest):
        raise ValueError("Predictions do not identify the exact held-out manifest")
    for key in ("model_id", "model_version", "model_sha256", "prediction_basis"):
        required(predictions.get(key), key)
    floor = number(predictions.get("score_floor"), "prediction score floor")
    if floor > operating_confidence:
        raise ValueError("Prediction floor exceeds evaluation operating confidence")
    classes = class_order_for_role(manifest["model_role"])
    if predictions.get("class_names") != list(classes):
        raise ValueError("Prediction class order differs from frozen class map")
    samples = {s["sample_id"]: s for s in manifest["samples"]}
    records = predictions.get("samples")
    if not isinstance(records, dict) or set(records) != set(samples):
        raise ValueError("Missing or extra prediction samples; skipped inference is UNKNOWN")
    ranked = defaultdict(list)
    for sample_id in sorted(records):
        detections = records[sample_id]
        if not isinstance(detections, list):
            raise ValueError("Incomplete/UNKNOWN inference cannot be scored as absence")
        for detection in detections:
            if not isinstance(detection, dict) or detection.get("canonical_object_id") not in classes:
                raise ValueError("Invalid prediction class")
            score = number(detection.get("confidence"), "confidence", floor)
            box(detection.get("bbox_xywh_normalized"))
            ranked[detection["canonical_object_id"]].append((sample_id, detection))
    metrics, false_positive_samples = {}, set()
    for canonical in classes:
        truths = {sid: [a["bbox_xywh_normalized"] for a in s.get("annotations", [])
                        if a["canonical_object_id"] == canonical] for sid, s in samples.items()}
        support = sum(map(len, truths.values()))
        ordered = sorted(ranked[canonical], key=lambda p: -p[1]["confidence"])
        flags = _matches(ordered, truths, 0.5)
        operating = [(p, hit) for p, hit in zip(ordered, flags)
                     if p[1]["confidence"] >= operating_confidence]
        tp = sum(hit for _, hit in operating)
        precision = tp / len(operating) if operating else 0.0
        recall = tp / support if support else None
        aps = [_ap(_matches(ordered, truths, 0.5 + index * 0.05), support)
               for index in range(10)]
        metrics[canonical] = {
            "support": support, "precision": precision, "recall": recall,
            "f1": 2 * precision * recall / (precision + recall)
            if recall is not None and precision + recall else (0.0 if support else None),
            "ap50": aps[0], "ap50_95": sum(aps) / 10 if support else None,
        }
        false_positive_samples.update(p[0] for p, hit in operating if not hit)
    tags = defaultdict(set)
    for sid, sample in samples.items():
        for tag in sample.get("negative_tags", []):
            tags[tag].add(sid)
    return {
        "schema_version": "1.0", "taxonomy_version": "1.0",
        **{k: predictions[k] for k in ("model_id", "model_version", "model_sha256")},
        "model_role": manifest["model_role"], "evaluation_dataset_id": manifest["dataset_id"],
        "evaluation_dataset_version": manifest["dataset_version"], "evaluation_split": split,
        "manifest_sha256": fingerprint(manifest), "predictions_sha256": fingerprint(predictions),
        "collection_sha256": fingerprint(manifests),
        "metric_protocol": "101-point AP; IoU .50:.05:.95; all-area; unlimited; no ignore/crowd",
        "operating_confidence": operating_confidence, "prediction_score_floor": floor,
        "class_metrics": metrics,
        "hard_negative_metrics": {tag: {"sample_count": len(ids),
            "false_positive_rate": len(ids & false_positive_samples) / len(ids)}
            for tag, ids in sorted(tags.items())},
        "hard_negative_definition": "fraction of tagged images with any unmatched detection at IoU .50",
        "calibration": {c: {"selected_confidence_threshold": None} for c in classes},
        "evaluation_valid": all(m["support"] > 0 for m in metrics.values()),
        "production_accepted": False,
    }


def ingest_calibration(report, evidence, manifests):
    """Ingest externally selected values; never choose a threshold here."""
    validate_collection(manifests)
    for key in ("model_id", "model_version", "model_sha256", "model_role"):
        if evidence.get(key) != report.get(key):
            raise ValueError(f"Calibration {key} mismatch")
    calibration_split = next((m for m in manifests if m["split"] == "validation"), None)
    if (calibration_split is None or evidence.get("manifest_sha256") != fingerprint(calibration_split)
            or evidence.get("split") != "validation"):
        raise ValueError("Calibration must identify the disjoint validation manifest, never test")
    if (report.get("collection_sha256") != fingerprint(manifests)
            or not report.get("evaluation_valid")):
        raise ValueError("Calibration requires valid held-out support and the same dataset collection")
    required(evidence.get("selection_basis"), "selection_basis")
    thresholds = evidence.get("thresholds", {})
    classes = class_order_for_role(report["model_role"])
    if set(thresholds) != set(classes):
        raise ValueError("Calibration must cover exactly the role's classes")
    support = defaultdict(int)
    for sample in calibration_split["samples"]:
        for annotation in sample.get("annotations", []):
            support[annotation["canonical_object_id"]] += 1
    if any(not support[c] for c in classes):
        raise ValueError("Zero validation support cannot calibrate a class")
    result = deepcopy(report)
    result["calibration"] = {c: {
        "selected_confidence_threshold": number(thresholds[c], c),
        "selection_basis": evidence["selection_basis"],
        "calibration_dataset_id": calibration_split["dataset_id"],
        "calibration_manifest_sha256": fingerprint(calibration_split),
        "calibration_evidence_sha256": fingerprint(evidence),
    } for c in classes}
    return result

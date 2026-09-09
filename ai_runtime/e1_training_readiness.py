"""E1 dataset, evaluation, and calibration readiness contracts.

This module is development-time tooling only. It is not imported by the live
exam runtime and it does not perform live inference. The contracts deliberately
avoid inventing scientific acceptance thresholds: class confidence thresholds
remain unset until they are selected from held-out calibration data.
"""

from __future__ import annotations

from dataclasses import dataclass
import math
from typing import Any, Iterable, Mapping, Sequence


E1_TAXONOMY_VERSION = "1.1"
E1_TRAINING_SCHEMA_VERSION = "1.0"

BASE_TRAINABLE_CLASSES = frozenset(
    {
        "person",
        "phone",
        "laptop",
        "television",
        "keyboard",
        "mouse",
        "remote",
        "book",
    }
)

SPECIALIST_TRAINABLE_CLASSES = frozenset(
    {
        "wrist_device",
        "earbud",
        "tablet",
        "paper_note",
        "calculator",
    }
)

DERIVED_ONLY_CLASSES = frozenset(
    {
        "additional_person",
        "partial_person",
        "screen_signal",
    }
)

RECOMMENDED_HARD_NEGATIVE_TAGS = frozenset(
    {
        "bracelet_or_wristband",
        "earring",
        "remote_control",
        "hand_without_phone",
        "printed_pattern",
        "background_screen",
    }
)

_ALLOWED_ROLES = frozenset({"base", "specialist"})
_ALLOWED_SPLITS = frozenset({"train", "validation", "test"})
_EVALUATION_SPLITS = frozenset({"validation", "test"})
_REQUIRED_CLASS_METRICS = (
    "precision",
    "recall",
    "f1",
    "ap50",
    "ap50_95",
)


@dataclass(frozen=True, slots=True)
class ValidationIssue:
    code: str
    path: str
    message: str


def expected_classes_for_role(role: str) -> frozenset[str]:
    normalized = role.strip().lower()
    if normalized == "base":
        return BASE_TRAINABLE_CLASSES
    if normalized == "specialist":
        return SPECIALIST_TRAINABLE_CLASSES
    return frozenset()


def validate_dataset_manifest(manifest: Mapping[str, Any]) -> tuple[ValidationIssue, ...]:
    """Validate one E1 dataset split manifest.

    The manifest is intentionally storage-agnostic. ``image_path`` may point to
    local or controlled training storage, but each annotation must already use
    the frozen canonical E1 class identity and normalized full-image geometry.
    """

    issues: list[ValidationIssue] = []
    _require_equal(
        issues,
        manifest.get("schema_version"),
        E1_TRAINING_SCHEMA_VERSION,
        "schema_version",
        "schema_version",
    )
    _require_equal(
        issues,
        manifest.get("taxonomy_version"),
        E1_TAXONOMY_VERSION,
        "taxonomy_version",
        "taxonomy_version",
    )
    _require_non_empty_string(issues, manifest.get("dataset_id"), "dataset_id")
    _require_non_empty_string(
        issues, manifest.get("dataset_version"), "dataset_version"
    )

    role = _read_string(manifest.get("model_role"))
    if role not in _ALLOWED_ROLES:
        issues.append(
            ValidationIssue(
                "invalid_model_role",
                "model_role",
                "model_role must be 'base' or 'specialist'.",
            )
        )
    expected_classes = expected_classes_for_role(role)

    split = _read_string(manifest.get("split"))
    if split not in _ALLOWED_SPLITS:
        issues.append(
            ValidationIssue(
                "invalid_split",
                "split",
                "split must be train, validation, or test.",
            )
        )

    samples = manifest.get("samples")
    if not isinstance(samples, Sequence) or isinstance(samples, (str, bytes)):
        issues.append(
            ValidationIssue("invalid_samples", "samples", "samples must be a list.")
        )
        return tuple(issues)
    if not samples:
        issues.append(
            ValidationIssue(
                "empty_dataset_split",
                "samples",
                "A readiness manifest must contain at least one sample.",
            )
        )
        return tuple(issues)

    seen_sample_ids: set[str] = set()
    for sample_index, raw_sample in enumerate(samples):
        sample_path = f"samples[{sample_index}]"
        if not isinstance(raw_sample, Mapping):
            issues.append(
                ValidationIssue(
                    "invalid_sample", sample_path, "Each sample must be an object."
                )
            )
            continue

        sample_id = _read_string(raw_sample.get("sample_id"))
        if not sample_id:
            issues.append(
                ValidationIssue(
                    "missing_sample_id",
                    f"{sample_path}.sample_id",
                    "sample_id is required.",
                )
            )
        elif sample_id in seen_sample_ids:
            issues.append(
                ValidationIssue(
                    "duplicate_sample_id",
                    f"{sample_path}.sample_id",
                    f"Duplicate sample_id: {sample_id}.",
                )
            )
        else:
            seen_sample_ids.add(sample_id)

        _require_non_empty_string(
            issues, raw_sample.get("source_group_id"), f"{sample_path}.source_group_id"
        )
        _require_non_empty_string(
            issues, raw_sample.get("image_path"), f"{sample_path}.image_path"
        )
        _require_positive_int(issues, raw_sample.get("width"), f"{sample_path}.width")
        _require_positive_int(
            issues, raw_sample.get("height"), f"{sample_path}.height"
        )

        negative_tags = raw_sample.get("negative_tags", [])
        if not _is_string_sequence(negative_tags):
            issues.append(
                ValidationIssue(
                    "invalid_negative_tags",
                    f"{sample_path}.negative_tags",
                    "negative_tags must be a list of non-empty strings when present.",
                )
            )

        annotations = raw_sample.get("annotations", [])
        if not isinstance(annotations, Sequence) or isinstance(
            annotations, (str, bytes)
        ):
            issues.append(
                ValidationIssue(
                    "invalid_annotations",
                    f"{sample_path}.annotations",
                    "annotations must be a list.",
                )
            )
            continue

        seen_annotation_ids: set[str] = set()
        for annotation_index, raw_annotation in enumerate(annotations):
            annotation_path = f"{sample_path}.annotations[{annotation_index}]"
            if not isinstance(raw_annotation, Mapping):
                issues.append(
                    ValidationIssue(
                        "invalid_annotation",
                        annotation_path,
                        "Each annotation must be an object.",
                    )
                )
                continue

            annotation_id = _read_string(raw_annotation.get("annotation_id"))
            if not annotation_id:
                issues.append(
                    ValidationIssue(
                        "missing_annotation_id",
                        f"{annotation_path}.annotation_id",
                        "annotation_id is required.",
                    )
                )
            elif annotation_id in seen_annotation_ids:
                issues.append(
                    ValidationIssue(
                        "duplicate_annotation_id",
                        f"{annotation_path}.annotation_id",
                        f"Duplicate annotation_id in sample: {annotation_id}.",
                    )
                )
            else:
                seen_annotation_ids.add(annotation_id)

            canonical_id = _read_string(raw_annotation.get("canonical_object_id"))
            if canonical_id in DERIVED_ONLY_CLASSES:
                issues.append(
                    ValidationIssue(
                        "derived_class_not_trainable",
                        f"{annotation_path}.canonical_object_id",
                        f"{canonical_id} is derived evidence, not a detector training class.",
                    )
                )
            elif canonical_id not in expected_classes:
                issues.append(
                    ValidationIssue(
                        "class_not_allowed_for_role",
                        f"{annotation_path}.canonical_object_id",
                        f"{canonical_id or '<missing>'} is not trainable by the {role or '<invalid>'} E1 role.",
                    )
                )

            _validate_normalized_box(
                issues,
                raw_annotation.get("bbox_xywh_normalized"),
                f"{annotation_path}.bbox_xywh_normalized",
            )

    return tuple(issues)


def validate_split_disjointness(
    manifests: Iterable[Mapping[str, Any]],
) -> tuple[ValidationIssue, ...]:
    """Reject capture/source groups shared across train/validation/test.

    ``source_group_id`` should identify a unit that must not leak across splits,
    for example one recording session, burst, or other tightly related capture
    group. The function does not assume a particular participant identity model.
    """

    issues: list[ValidationIssue] = []
    split_by_group: dict[str, str] = {}
    for manifest_index, manifest in enumerate(manifests):
        split = _read_string(manifest.get("split"))
        if split not in _ALLOWED_SPLITS:
            continue
        samples = manifest.get("samples")
        if not isinstance(samples, Sequence) or isinstance(samples, (str, bytes)):
            continue
        for sample_index, sample in enumerate(samples):
            if not isinstance(sample, Mapping):
                continue
            group_id = _read_string(sample.get("source_group_id"))
            if not group_id:
                continue
            previous_split = split_by_group.get(group_id)
            if previous_split is None:
                split_by_group[group_id] = split
                continue
            if previous_split != split:
                issues.append(
                    ValidationIssue(
                        "source_group_split_leakage",
                        f"manifests[{manifest_index}].samples[{sample_index}].source_group_id",
                        f"source_group_id {group_id!r} appears in both {previous_split} and {split} splits.",
                    )
                )
    return tuple(issues)


def validate_evaluation_report(report: Mapping[str, Any]) -> tuple[ValidationIssue, ...]:
    """Validate an E1 held-out evaluation/calibration report contract.

    Metric presence and numeric ranges are checked, but this function does not
    impose performance pass/fail thresholds. Those values must come from the
    project's empirical calibration and acceptance process.
    """

    issues: list[ValidationIssue] = []
    _require_equal(
        issues,
        report.get("schema_version"),
        E1_TRAINING_SCHEMA_VERSION,
        "schema_version",
        "schema_version",
    )
    _require_equal(
        issues,
        report.get("taxonomy_version"),
        E1_TAXONOMY_VERSION,
        "taxonomy_version",
        "taxonomy_version",
    )
    _require_non_empty_string(issues, report.get("model_id"), "model_id")
    _require_non_empty_string(issues, report.get("model_version"), "model_version")
    _require_non_empty_string(
        issues, report.get("evaluation_dataset_id"), "evaluation_dataset_id"
    )

    role = _read_string(report.get("model_role"))
    expected_classes = expected_classes_for_role(role)
    if role not in _ALLOWED_ROLES:
        issues.append(
            ValidationIssue(
                "invalid_model_role",
                "model_role",
                "model_role must be 'base' or 'specialist'.",
            )
        )

    evaluation_split = _read_string(report.get("evaluation_split"))
    if evaluation_split not in _EVALUATION_SPLITS:
        issues.append(
            ValidationIssue(
                "invalid_evaluation_split",
                "evaluation_split",
                "Model evaluation must use validation or test data, not training data.",
            )
        )

    class_metrics = report.get("class_metrics")
    if not isinstance(class_metrics, Mapping):
        issues.append(
            ValidationIssue(
                "invalid_class_metrics",
                "class_metrics",
                "class_metrics must be an object keyed by canonical class ID.",
            )
        )
        class_metrics = {}

    for canonical_id in sorted(expected_classes):
        metrics = class_metrics.get(canonical_id)
        path = f"class_metrics.{canonical_id}"
        if not isinstance(metrics, Mapping):
            issues.append(
                ValidationIssue(
                    "missing_class_metrics",
                    path,
                    f"Held-out metrics are required for {canonical_id}.",
                )
            )
            continue
        _require_non_negative_int(issues, metrics.get("support"), f"{path}.support")
        for metric_name in _REQUIRED_CLASS_METRICS:
            _require_unit_interval(
                issues, metrics.get(metric_name), f"{path}.{metric_name}"
            )

    hard_negative_metrics = report.get("hard_negative_metrics", {})
    if not isinstance(hard_negative_metrics, Mapping):
        issues.append(
            ValidationIssue(
                "invalid_hard_negative_metrics",
                "hard_negative_metrics",
                "hard_negative_metrics must be an object when present.",
            )
        )
    else:
        for tag, metrics in hard_negative_metrics.items():
            path = f"hard_negative_metrics.{tag}"
            if not isinstance(tag, str) or not tag.strip() or not isinstance(metrics, Mapping):
                issues.append(
                    ValidationIssue(
                        "invalid_hard_negative_entry",
                        path,
                        "Each hard-negative entry requires a non-empty tag and metrics object.",
                    )
                )
                continue
            _require_non_negative_int(
                issues, metrics.get("sample_count"), f"{path}.sample_count"
            )
            _require_unit_interval(
                issues,
                metrics.get("false_positive_rate"),
                f"{path}.false_positive_rate",
            )

    calibration = report.get("calibration")
    if not isinstance(calibration, Mapping):
        issues.append(
            ValidationIssue(
                "invalid_calibration",
                "calibration",
                "calibration must be an object keyed by canonical class ID.",
            )
        )
        calibration = {}

    for canonical_id in sorted(expected_classes):
        record = calibration.get(canonical_id)
        path = f"calibration.{canonical_id}"
        if not isinstance(record, Mapping):
            issues.append(
                ValidationIssue(
                    "missing_calibration_record",
                    path,
                    "A calibration record is required even when its selected threshold is still null.",
                )
            )
            continue
        threshold = record.get("selected_confidence_threshold")
        if threshold is None:
            continue
        if not _is_unit_interval_number(threshold):
            issues.append(
                ValidationIssue(
                    "invalid_selected_threshold",
                    f"{path}.selected_confidence_threshold",
                    "A selected threshold must be between 0 and 1.",
                )
            )
            continue
        _require_non_empty_string(
            issues, record.get("selection_basis"), f"{path}.selection_basis"
        )
        _require_non_empty_string(
            issues,
            record.get("calibration_dataset_id"),
            f"{path}.calibration_dataset_id",
        )

    return tuple(issues)


def calibration_complete(report: Mapping[str, Any]) -> bool:
    """Return True only when every role class has an evidence-backed threshold."""

    if validate_evaluation_report(report):
        return False
    role = _read_string(report.get("model_role"))
    calibration = report.get("calibration")
    if not isinstance(calibration, Mapping):
        return False
    for canonical_id in expected_classes_for_role(role):
        record = calibration.get(canonical_id)
        if not isinstance(record, Mapping):
            return False
        threshold = record.get("selected_confidence_threshold")
        if not _is_unit_interval_number(threshold):
            return False
        if not _read_string(record.get("selection_basis")):
            return False
        if not _read_string(record.get("calibration_dataset_id")):
            return False
    return True


def _validate_normalized_box(
    issues: list[ValidationIssue], value: Any, path: str
) -> None:
    if not isinstance(value, Mapping):
        issues.append(
            ValidationIssue(
                "invalid_bbox", path, "bbox_xywh_normalized must be an object."
            )
        )
        return
    values: dict[str, float] = {}
    for key in ("x", "y", "width", "height"):
        raw = value.get(key)
        if not isinstance(raw, (int, float)) or isinstance(raw, bool):
            issues.append(
                ValidationIssue(
                    "invalid_bbox_value", f"{path}.{key}", f"{key} must be numeric."
                )
            )
            return
        numeric = float(raw)
        if not math.isfinite(numeric):
            issues.append(
                ValidationIssue(
                    "invalid_bbox_value",
                    f"{path}.{key}",
                    f"{key} must be finite.",
                )
            )
            return
        values[key] = numeric

    x = values["x"]
    y = values["y"]
    width = values["width"]
    height = values["height"]
    if (
        x < 0.0
        or y < 0.0
        or width <= 0.0
        or height <= 0.0
        or x > 1.0
        or y > 1.0
        or x + width > 1.0001
        or y + height > 1.0001
    ):
        issues.append(
            ValidationIssue(
                "bbox_out_of_range",
                path,
                "Normalized box must lie inside the full image with positive width and height.",
            )
        )


def _require_equal(
    issues: list[ValidationIssue],
    actual: Any,
    expected: str,
    code: str,
    path: str,
) -> None:
    if actual != expected:
        issues.append(
            ValidationIssue(
                f"invalid_{code}", path, f"Expected {expected!r}, got {actual!r}."
            )
        )


def _require_non_empty_string(
    issues: list[ValidationIssue], value: Any, path: str
) -> None:
    if not _read_string(value):
        issues.append(
            ValidationIssue("missing_string", path, "A non-empty string is required.")
        )


def _require_positive_int(
    issues: list[ValidationIssue], value: Any, path: str
) -> None:
    if not isinstance(value, int) or isinstance(value, bool) or value <= 0:
        issues.append(
            ValidationIssue("invalid_positive_int", path, "A positive integer is required.")
        )


def _require_non_negative_int(
    issues: list[ValidationIssue], value: Any, path: str
) -> None:
    if not isinstance(value, int) or isinstance(value, bool) or value < 0:
        issues.append(
            ValidationIssue(
                "invalid_non_negative_int",
                path,
                "A non-negative integer is required.",
            )
        )


def _require_unit_interval(
    issues: list[ValidationIssue], value: Any, path: str
) -> None:
    if not _is_unit_interval_number(value):
        issues.append(
            ValidationIssue(
                "metric_out_of_range", path, "Metric must be numeric between 0 and 1."
            )
        )


def _is_unit_interval_number(value: Any) -> bool:
    if not isinstance(value, (int, float)) or isinstance(value, bool):
        return False
    numeric = float(value)
    return math.isfinite(numeric) and 0.0 <= numeric <= 1.0


def _is_string_sequence(value: Any) -> bool:
    return isinstance(value, Sequence) and not isinstance(value, (str, bytes)) and all(
        isinstance(item, str) and bool(item.strip()) for item in value
    )


def _read_string(value: Any) -> str:
    return value.strip().lower() if isinstance(value, str) else ""

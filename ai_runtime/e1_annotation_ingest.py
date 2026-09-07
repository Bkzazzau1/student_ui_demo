"""Convert staged E1 annotations into the frozen canonical dataset manifest.

This module is development-time tooling only. It never participates in live exam
inference. The ingest boundary is deliberately strict: source-group leakage
boundaries and canonical class identities must be supplied by the dataset
workflow; semantic aliases are never guessed here.
"""

from __future__ import annotations

import argparse
from collections import Counter
from contextlib import suppress
import hashlib
import json
import math
from pathlib import Path
import sys
from typing import Any, Mapping, Sequence, TextIO

from .e1_training_readiness import (
    E1_TAXONOMY_VERSION,
    E1_TRAINING_SCHEMA_VERSION,
    ValidationIssue,
    expected_classes_for_role,
    validate_dataset_manifest,
)


E1_ANNOTATION_INGEST_SCHEMA_VERSION = "1.0"
_ALLOWED_ROLES = frozenset({"base", "specialist"})
_ALLOWED_SPLITS = frozenset({"train", "validation", "test"})
_GEOMETRY_KEYS = (
    "bbox_xywh_normalized",
    "bbox_xywh_pixels",
    "bbox_xyxy_pixels",
)


class E1AnnotationIngestInputError(ValueError):
    """Raised when a staged annotation file cannot be read as a JSON object."""

    def __init__(self, code: str, message: str):
        super().__init__(message)
        self.code = code
        self.message = message


def _read_string(value: Any) -> str:
    return value.strip() if isinstance(value, str) else ""


def _read_lower_string(value: Any) -> str:
    return _read_string(value).lower()


def _positive_int(value: Any) -> int | None:
    if isinstance(value, bool) or not isinstance(value, int) or value <= 0:
        return None
    return value


def _finite_number(value: Any) -> float | None:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        return None
    number = float(value)
    return number if math.isfinite(number) else None


def _normalized_path(value: Any) -> str:
    path = _read_string(value).replace("\\", "/")
    while path.startswith("./"):
        path = path[2:]
    return path


def _stable_id(prefix: str, *parts: str) -> str:
    payload = "\x1f".join(parts).encode("utf-8")
    digest = hashlib.sha256(payload).hexdigest()[:20]
    return f"{prefix}_{digest}"


def _round_normalized(value: float) -> float:
    return round(value, 10)


def _box_signature(box: Sequence[float]) -> str:
    return ",".join(f"{value:.10f}" for value in box)


def _issue(code: str, path: str, message: str) -> ValidationIssue:
    return ValidationIssue(code=code, path=path, message=message)


def _validate_unit_xywh(
    raw_box: Any,
    *,
    path: str,
) -> tuple[list[float] | None, list[ValidationIssue]]:
    issues: list[ValidationIssue] = []
    if not isinstance(raw_box, Sequence) or isinstance(raw_box, (str, bytes)):
        return None, [_issue("invalid_bbox", path, "Bounding box must be a four-number list.")]
    if len(raw_box) != 4:
        return None, [_issue("invalid_bbox", path, "Bounding box must contain exactly four numbers.")]

    values = [_finite_number(value) for value in raw_box]
    if any(value is None for value in values):
        return None, [_issue("invalid_bbox", path, "Bounding box values must be finite numbers.")]

    x, y, width, height = (float(value) for value in values if value is not None)
    if x < 0 or y < 0 or width <= 0 or height <= 0:
        issues.append(
            _issue(
                "invalid_bbox_geometry",
                path,
                "Normalized x/y must be non-negative and width/height must be positive.",
            )
        )
    if x + width > 1.0 + 1e-9 or y + height > 1.0 + 1e-9:
        issues.append(
            _issue(
                "bbox_out_of_bounds",
                path,
                "Normalized bounding box must stay inside the full source image.",
            )
        )
    if issues:
        return None, issues
    return [
        _round_normalized(x),
        _round_normalized(y),
        _round_normalized(width),
        _round_normalized(height),
    ], []


def _validate_pixel_xywh(
    raw_box: Any,
    *,
    image_width: int,
    image_height: int,
    path: str,
) -> tuple[list[float] | None, list[ValidationIssue]]:
    if not isinstance(raw_box, Sequence) or isinstance(raw_box, (str, bytes)) or len(raw_box) != 4:
        return None, [_issue("invalid_bbox", path, "Pixel xywh box must contain exactly four numbers.")]
    values = [_finite_number(value) for value in raw_box]
    if any(value is None for value in values):
        return None, [_issue("invalid_bbox", path, "Pixel xywh values must be finite numbers.")]
    x, y, width, height = (float(value) for value in values if value is not None)
    if x < 0 or y < 0 or width <= 0 or height <= 0:
        return None, [
            _issue(
                "invalid_bbox_geometry",
                path,
                "Pixel x/y must be non-negative and width/height must be positive.",
            )
        ]
    if x + width > image_width + 1e-9 or y + height > image_height + 1e-9:
        return None, [
            _issue(
                "bbox_out_of_bounds",
                path,
                "Pixel bounding box must stay inside the full source image.",
            )
        ]
    return _validate_unit_xywh(
        [x / image_width, y / image_height, width / image_width, height / image_height],
        path=path,
    )


def _validate_pixel_xyxy(
    raw_box: Any,
    *,
    image_width: int,
    image_height: int,
    path: str,
) -> tuple[list[float] | None, list[ValidationIssue]]:
    if not isinstance(raw_box, Sequence) or isinstance(raw_box, (str, bytes)) or len(raw_box) != 4:
        return None, [_issue("invalid_bbox", path, "Pixel xyxy box must contain exactly four numbers.")]
    values = [_finite_number(value) for value in raw_box]
    if any(value is None for value in values):
        return None, [_issue("invalid_bbox", path, "Pixel xyxy values must be finite numbers.")]
    x1, y1, x2, y2 = (float(value) for value in values if value is not None)
    if x1 < 0 or y1 < 0 or x2 <= x1 or y2 <= y1:
        return None, [
            _issue(
                "invalid_bbox_geometry",
                path,
                "Pixel xyxy requires non-negative x1/y1 and x2>x1, y2>y1.",
            )
        ]
    if x2 > image_width + 1e-9 or y2 > image_height + 1e-9:
        return None, [
            _issue(
                "bbox_out_of_bounds",
                path,
                "Pixel bounding box must stay inside the full source image.",
            )
        ]
    return _validate_pixel_xywh(
        [x1, y1, x2 - x1, y2 - y1],
        image_width=image_width,
        image_height=image_height,
        path=path,
    )


def _convert_geometry(
    annotation: Mapping[str, Any],
    *,
    image_width: int,
    image_height: int,
    path: str,
) -> tuple[list[float] | None, list[ValidationIssue]]:
    present = [key for key in _GEOMETRY_KEYS if key in annotation]
    if len(present) != 1:
        return None, [
            _issue(
                "ambiguous_bbox_source",
                path,
                "Each annotation must provide exactly one of bbox_xywh_normalized, bbox_xywh_pixels, or bbox_xyxy_pixels.",
            )
        ]

    key = present[0]
    box_path = f"{path}.{key}"
    if key == "bbox_xywh_normalized":
        return _validate_unit_xywh(annotation[key], path=box_path)
    if key == "bbox_xywh_pixels":
        return _validate_pixel_xywh(
            annotation[key],
            image_width=image_width,
            image_height=image_height,
            path=box_path,
        )
    return _validate_pixel_xyxy(
        annotation[key],
        image_width=image_width,
        image_height=image_height,
        path=box_path,
    )


def build_dataset_manifest(
    staging: Mapping[str, Any],
) -> tuple[dict[str, Any] | None, tuple[ValidationIssue, ...]]:
    """Build one frozen E1 manifest from one staged annotation JSON object."""

    issues: list[ValidationIssue] = []
    ingest_version = _read_string(staging.get("ingest_schema_version"))
    if ingest_version != E1_ANNOTATION_INGEST_SCHEMA_VERSION:
        issues.append(
            _issue(
                "invalid_ingest_schema_version",
                "ingest_schema_version",
                f"ingest_schema_version must be {E1_ANNOTATION_INGEST_SCHEMA_VERSION}.",
            )
        )

    dataset_id = _read_string(staging.get("dataset_id"))
    dataset_version = _read_string(staging.get("dataset_version"))
    role = _read_lower_string(staging.get("model_role"))
    split = _read_lower_string(staging.get("split"))

    if not dataset_id:
        issues.append(_issue("missing_dataset_id", "dataset_id", "dataset_id is required."))
    if not dataset_version:
        issues.append(
            _issue("missing_dataset_version", "dataset_version", "dataset_version is required.")
        )
    if role not in _ALLOWED_ROLES:
        issues.append(
            _issue("invalid_model_role", "model_role", "model_role must be 'base' or 'specialist'.")
        )
    if split not in _ALLOWED_SPLITS:
        issues.append(
            _issue("invalid_split", "split", "split must be train, validation, or test.")
        )

    records = staging.get("records")
    if not isinstance(records, Sequence) or isinstance(records, (str, bytes)):
        issues.append(_issue("invalid_records", "records", "records must be a list."))
        return None, tuple(issues)
    if not records:
        issues.append(_issue("empty_records", "records", "At least one staged image record is required."))
        return None, tuple(issues)

    expected_classes = expected_classes_for_role(role)
    samples: list[dict[str, Any]] = []
    seen_sample_ids: set[str] = set()

    for record_index, raw_record in enumerate(records):
        record_path = f"records[{record_index}]"
        if not isinstance(raw_record, Mapping):
            issues.append(_issue("invalid_record", record_path, "Each record must be an object."))
            continue

        source_group_id = _read_string(raw_record.get("source_group_id"))
        image_path = _normalized_path(raw_record.get("image_path"))
        image_width = _positive_int(raw_record.get("width"))
        image_height = _positive_int(raw_record.get("height"))

        if not source_group_id:
            issues.append(
                _issue(
                    "missing_source_group_id",
                    f"{record_path}.source_group_id",
                    "source_group_id must be supplied by the collection workflow; ingest will not infer a leakage boundary.",
                )
            )
        if not image_path:
            issues.append(_issue("missing_image_path", f"{record_path}.image_path", "image_path is required."))
        if image_width is None:
            issues.append(_issue("invalid_width", f"{record_path}.width", "width must be a positive integer."))
        if image_height is None:
            issues.append(_issue("invalid_height", f"{record_path}.height", "height must be a positive integer."))

        negative_tags_raw = raw_record.get("negative_tags", [])
        negative_tags: list[str] = []
        if not isinstance(negative_tags_raw, Sequence) or isinstance(negative_tags_raw, (str, bytes)):
            issues.append(
                _issue(
                    "invalid_negative_tags",
                    f"{record_path}.negative_tags",
                    "negative_tags must be a list of non-empty strings when present.",
                )
            )
        else:
            invalid_tag = False
            for tag in negative_tags_raw:
                normalized_tag = _read_lower_string(tag)
                if not normalized_tag:
                    invalid_tag = True
                    break
                negative_tags.append(normalized_tag)
            if invalid_tag:
                issues.append(
                    _issue(
                        "invalid_negative_tags",
                        f"{record_path}.negative_tags",
                        "negative_tags must contain only non-empty strings.",
                    )
                )
            negative_tags = sorted(set(negative_tags))

        annotations_raw = raw_record.get("annotations")
        if not isinstance(annotations_raw, Sequence) or isinstance(annotations_raw, (str, bytes)):
            issues.append(
                _issue(
                    "invalid_annotations",
                    f"{record_path}.annotations",
                    "annotations must be a list; use an empty list for a negative sample.",
                )
            )
            annotations_raw = []

        if not all((dataset_id, dataset_version, split, source_group_id, image_path)):
            continue
        if image_width is None or image_height is None:
            continue

        sample_id = _stable_id(
            "e1s",
            dataset_id,
            dataset_version,
            split,
            source_group_id,
            image_path,
        )
        if sample_id in seen_sample_ids:
            issues.append(
                _issue(
                    "duplicate_sample_identity",
                    record_path,
                    "Two staged records resolve to the same deterministic sample identity.",
                )
            )
            continue
        seen_sample_ids.add(sample_id)

        annotations: list[dict[str, Any]] = []
        seen_annotation_ids: set[str] = set()
        for annotation_index, raw_annotation in enumerate(annotations_raw):
            annotation_path = f"{record_path}.annotations[{annotation_index}]"
            if not isinstance(raw_annotation, Mapping):
                issues.append(
                    _issue("invalid_annotation", annotation_path, "Each annotation must be an object.")
                )
                continue

            raw_canonical_id = _read_string(raw_annotation.get("canonical_object_id"))
            canonical_id = raw_canonical_id.lower()
            if not canonical_id:
                issues.append(
                    _issue(
                        "missing_canonical_object_id",
                        f"{annotation_path}.canonical_object_id",
                        "canonical_object_id is required; ingest will not infer a class from a raw label.",
                    )
                )
                continue
            if canonical_id not in expected_classes:
                issues.append(
                    _issue(
                        "class_not_allowed_for_role",
                        f"{annotation_path}.canonical_object_id",
                        f"{raw_canonical_id!r} is not a canonical trainable class for the {role} E1 role; semantic aliases are not guessed.",
                    )
                )
                continue

            normalized_box, box_issues = _convert_geometry(
                raw_annotation,
                image_width=image_width,
                image_height=image_height,
                path=annotation_path,
            )
            issues.extend(box_issues)
            if normalized_box is None:
                continue

            annotation_id = _stable_id(
                "e1a",
                sample_id,
                canonical_id,
                _box_signature(normalized_box),
            )
            if annotation_id in seen_annotation_ids:
                issues.append(
                    _issue(
                        "duplicate_annotation_identity",
                        annotation_path,
                        "Duplicate class/geometry annotation resolves to the same deterministic identity.",
                    )
                )
                continue
            seen_annotation_ids.add(annotation_id)
            annotations.append(
                {
                    "annotation_id": annotation_id,
                    "canonical_object_id": canonical_id,
                    "bbox_xywh_normalized": normalized_box,
                }
            )

        samples.append(
            {
                "sample_id": sample_id,
                "source_group_id": source_group_id,
                "image_path": image_path,
                "width": image_width,
                "height": image_height,
                "negative_tags": negative_tags,
                "annotations": annotations,
            }
        )

    if issues:
        return None, tuple(issues)

    manifest: dict[str, Any] = {
        "schema_version": E1_TRAINING_SCHEMA_VERSION,
        "taxonomy_version": E1_TAXONOMY_VERSION,
        "dataset_id": dataset_id,
        "dataset_version": dataset_version,
        "model_role": role,
        "split": split,
        "samples": samples,
    }
    manifest_issues = validate_dataset_manifest(manifest)
    if manifest_issues:
        return None, manifest_issues
    return manifest, ()


def _load_json_object(path: Path) -> Mapping[str, Any]:
    try:
        raw = path.read_text(encoding="utf-8")
    except OSError as exc:
        raise E1AnnotationIngestInputError(
            "input_read_error", f"Could not read {path}: {exc}"
        ) from exc
    try:
        value = json.loads(raw)
    except json.JSONDecodeError as exc:
        raise E1AnnotationIngestInputError(
            "invalid_json",
            f"Invalid JSON in {path} at line {exc.lineno}, column {exc.colno}: {exc.msg}",
        ) from exc
    if not isinstance(value, Mapping):
        raise E1AnnotationIngestInputError(
            "json_root_not_object", f"Top-level JSON value in {path} must be an object."
        )
    return value


def _issue_dict(issue: ValidationIssue) -> dict[str, str]:
    return {"code": issue.code, "path": issue.path, "message": issue.message}


def _summary(manifest: Mapping[str, Any]) -> dict[str, Any]:
    class_counts: Counter[str] = Counter()
    negative_tag_counts: Counter[str] = Counter()
    annotation_count = 0
    samples = manifest.get("samples", [])
    if not isinstance(samples, list):
        samples = []
    for sample in samples:
        if not isinstance(sample, Mapping):
            continue
        for tag in sample.get("negative_tags", []):
            if isinstance(tag, str):
                negative_tag_counts[tag] += 1
        annotations = sample.get("annotations", [])
        if not isinstance(annotations, list):
            continue
        annotation_count += len(annotations)
        for annotation in annotations:
            if isinstance(annotation, Mapping):
                canonical_id = annotation.get("canonical_object_id")
                if isinstance(canonical_id, str):
                    class_counts[canonical_id] += 1
    return {
        "sample_count": len(samples),
        "annotation_count": annotation_count,
        "class_counts": dict(sorted(class_counts.items())),
        "negative_tag_counts": dict(sorted(negative_tag_counts.items())),
    }


def ingest_annotation_file(
    input_path: Path,
    output_path: Path,
    *,
    force: bool = False,
) -> dict[str, Any]:
    try:
        if input_path.resolve() == output_path.resolve():
            return {
                "command": "ingest",
                "ok": False,
                "input": str(input_path),
                "output": str(output_path),
                "issues": [
                    {
                        "code": "input_output_same",
                        "path": "$",
                        "message": "Input staging JSON and output canonical manifest must be different files.",
                    }
                ],
            }
    except OSError:
        pass

    if output_path.exists() and not force:
        return {
            "command": "ingest",
            "ok": False,
            "input": str(input_path),
            "output": str(output_path),
            "issues": [
                {
                    "code": "output_exists",
                    "path": "$",
                    "message": "Output already exists; pass --force to replace it.",
                }
            ],
        }

    try:
        staging = _load_json_object(input_path)
    except E1AnnotationIngestInputError as exc:
        return {
            "command": "ingest",
            "ok": False,
            "input": str(input_path),
            "output": str(output_path),
            "issues": [{"code": exc.code, "path": "$", "message": exc.message}],
        }

    manifest, issues = build_dataset_manifest(staging)
    if manifest is None:
        return {
            "command": "ingest",
            "ok": False,
            "input": str(input_path),
            "output": str(output_path),
            "issues": [_issue_dict(issue) for issue in issues],
        }

    try:
        output_path.parent.mkdir(parents=True, exist_ok=True)
        temporary = output_path.with_name(f".{output_path.name}.tmp")
        temporary.write_text(
            json.dumps(manifest, indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
        )
        temporary.replace(output_path)
    except OSError as exc:
        return {
            "command": "ingest",
            "ok": False,
            "input": str(input_path),
            "output": str(output_path),
            "issues": [
                {
                    "code": "output_write_error",
                    "path": "$",
                    "message": f"Could not write canonical manifest: {exc}",
                }
            ],
        }

    return {
        "command": "ingest",
        "ok": True,
        "input": str(input_path),
        "output": str(output_path),
        "dataset_id": manifest["dataset_id"],
        "dataset_version": manifest["dataset_version"],
        "model_role": manifest["model_role"],
        "split": manifest["split"],
        "summary": _summary(manifest),
        "issues": [],
    }


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="python -m ai_runtime.e1_annotation_ingest",
        description="Convert staged E1 annotations into a canonical validated dataset manifest.",
    )
    parser.add_argument("input", type=Path, help="Staged annotation JSON file.")
    parser.add_argument("output", type=Path, help="Canonical manifest JSON to create.")
    parser.add_argument(
        "--force",
        action="store_true",
        help="Replace an existing output manifest.",
    )
    parser.add_argument(
        "--pretty",
        action="store_true",
        help="Pretty-print the command result JSON.",
    )
    return parser


def main(argv: Sequence[str] | None = None, *, stdout: TextIO | None = None) -> int:
    args = _build_parser().parse_args(argv)
    output = stdout if stdout is not None else sys.stdout
    result = ingest_annotation_file(args.input, args.output, force=args.force)
    json.dump(result, output, indent=2 if args.pretty else None, sort_keys=True)
    output.write("\n")
    with suppress(AttributeError):
        output.flush()
    return 0 if result["ok"] else 1


if __name__ == "__main__":
    raise SystemExit(main())

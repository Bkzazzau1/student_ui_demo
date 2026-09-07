"""Export frozen E1 manifests into a reproducible YOLO training package.

Development-time tooling only. This module never participates in live exam
inference. It consumes already-canonical E1 dataset manifests, validates them,
materializes images and YOLO labels, and emits provenance needed to reproduce
the training input exactly.
"""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import shutil
import sys
import tempfile
from typing import Any, Mapping, Sequence, TextIO

from .e1_training_readiness import (
    E1_TAXONOMY_VERSION,
    ValidationIssue,
    expected_classes_for_role,
    validate_dataset_manifest,
    validate_split_disjointness,
)


E1_TRAINING_EXPORT_SCHEMA_VERSION = "1.0"

BASE_YOLO_CLASS_ORDER = (
    "person",
    "phone",
    "laptop",
    "television",
    "keyboard",
    "mouse",
    "remote",
    "book",
)

SPECIALIST_YOLO_CLASS_ORDER = (
    "smartwatch",
    "earbud",
    "tablet",
    "paper_note",
    "calculator",
)

_ALLOWED_SPLITS = ("train", "validation", "test")
_REQUIRED_SPLITS = frozenset({"train", "validation"})
_SAFE_SAMPLE_ID_CHARS = frozenset(
    "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-"
)
_WINDOWS_RESERVED_STEMS = frozenset(
    {"CON", "PRN", "AUX", "NUL"}
    | {f"COM{index}" for index in range(1, 10)}
    | {f"LPT{index}" for index in range(1, 10)}
)


class E1TrainingExportInputError(ValueError):
    """Raised when the requested training export cannot be built safely."""

    def __init__(self, code: str, message: str):
        super().__init__(message)
        self.code = code
        self.message = message


def class_order_for_role(role: str) -> tuple[str, ...]:
    normalized = role.strip().lower()
    if normalized == "base":
        return BASE_YOLO_CLASS_ORDER
    if normalized == "specialist":
        return SPECIALIST_YOLO_CLASS_ORDER
    return ()


def _load_json_object(path: Path) -> Mapping[str, Any]:
    try:
        raw = path.read_text(encoding="utf-8")
    except OSError as exc:
        raise E1TrainingExportInputError(
            "manifest_read_error", f"Could not read {path}: {exc}"
        ) from exc
    try:
        value = json.loads(raw)
    except json.JSONDecodeError as exc:
        raise E1TrainingExportInputError(
            "invalid_manifest_json",
            f"Invalid JSON in {path} at line {exc.lineno}, column {exc.colno}: {exc.msg}",
        ) from exc
    if not isinstance(value, Mapping):
        raise E1TrainingExportInputError(
            "manifest_root_not_object", f"Top-level JSON in {path} must be an object."
        )
    return value


def _issue_dict(issue: ValidationIssue, source: Path | str) -> dict[str, str]:
    return {
        "code": issue.code,
        "path": issue.path,
        "message": issue.message,
        "source": str(source),
    }


def _read_string(value: Any) -> str:
    return value.strip() if isinstance(value, str) else ""


def _normalized_role(value: Any) -> str:
    return _read_string(value).lower()


def _normalized_split(value: Any) -> str:
    return _read_string(value).lower()


def _safe_sample_id(value: str) -> bool:
    if not value or len(value) > 128 or value in {".", ".."}:
        return False
    if any(character not in _SAFE_SAMPLE_ID_CHARS for character in value):
        return False
    windows_stem = value.split(".", 1)[0].upper()
    return windows_stem not in _WINDOWS_RESERVED_STEMS


def _resolve_image_path(manifest_path: Path, image_path: str) -> Path:
    source = Path(image_path)
    if source.is_absolute():
        return source
    return (manifest_path.parent / source).resolve()


def _sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _format_float(value: float) -> str:
    return f"{value:.10f}".rstrip("0").rstrip(".") or "0"


def _yolo_line(
    annotation: Mapping[str, Any],
    *,
    class_index: Mapping[str, int],
) -> str:
    canonical_id = _read_string(annotation.get("canonical_object_id")).lower()
    box = annotation.get("bbox_xywh_normalized")
    if canonical_id not in class_index or not isinstance(box, Mapping):
        raise E1TrainingExportInputError(
            "invalid_annotation_for_export",
            "Canonical annotation validation unexpectedly failed before YOLO conversion.",
        )
    x = float(box["x"])
    y = float(box["y"])
    width = float(box["width"])
    height = float(box["height"])
    center_x = x + width / 2.0
    center_y = y + height / 2.0
    return " ".join(
        (
            str(class_index[canonical_id]),
            _format_float(center_x),
            _format_float(center_y),
            _format_float(width),
            _format_float(height),
        )
    )


def _dataset_yaml(class_order: Sequence[str], available_splits: set[str]) -> str:
    lines = ["path: .", "train: images/train", "val: images/validation"]
    if "test" in available_splits:
        lines.append("test: images/test")
    lines.append("names:")
    lines.extend(
        f"  {index}: {canonical_id}"
        for index, canonical_id in enumerate(class_order)
    )
    return "\n".join(lines) + "\n"


def _validate_manifest_collection(
    manifest_paths: Sequence[Path],
) -> tuple[list[tuple[Path, Mapping[str, Any]]], list[dict[str, str]]]:
    loaded: list[tuple[Path, Mapping[str, Any]]] = []
    issues: list[dict[str, str]] = []

    for path in manifest_paths:
        try:
            manifest = _load_json_object(path)
        except E1TrainingExportInputError as exc:
            issues.append(
                {
                    "code": exc.code,
                    "path": "$",
                    "message": exc.message,
                    "source": str(path),
                }
            )
            continue
        loaded.append((path, manifest))
        issues.extend(
            _issue_dict(issue, path)
            for issue in validate_dataset_manifest(manifest)
        )

    if loaded:
        manifests = [manifest for _, manifest in loaded]
        issues.extend(
            _issue_dict(issue, "<combined-manifests>")
            for issue in validate_split_disjointness(manifests)
        )

        dataset_ids = {
            _read_string(manifest.get("dataset_id")) for manifest in manifests
        }
        versions = {
            _read_string(manifest.get("dataset_version")) for manifest in manifests
        }
        roles = {
            _normalized_role(manifest.get("model_role")) for manifest in manifests
        }
        taxonomies = {
            _read_string(manifest.get("taxonomy_version")) for manifest in manifests
        }
        splits = [
            _normalized_split(manifest.get("split")) for manifest in manifests
        ]

        if len(dataset_ids) != 1:
            issues.append(
                {
                    "code": "mixed_dataset_id",
                    "path": "dataset_id",
                    "message": "All exported manifests must belong to one dataset_id.",
                    "source": "<combined-manifests>",
                }
            )
        if len(versions) != 1:
            issues.append(
                {
                    "code": "mixed_dataset_version",
                    "path": "dataset_version",
                    "message": "All exported manifests must belong to one dataset_version.",
                    "source": "<combined-manifests>",
                }
            )
        if len(roles) != 1:
            issues.append(
                {
                    "code": "mixed_model_role",
                    "path": "model_role",
                    "message": "Base and specialist manifests must be exported separately.",
                    "source": "<combined-manifests>",
                }
            )
        if taxonomies != {E1_TAXONOMY_VERSION}:
            issues.append(
                {
                    "code": "mixed_taxonomy_version",
                    "path": "taxonomy_version",
                    "message": "All manifests must use the frozen E1 taxonomy version.",
                    "source": "<combined-manifests>",
                }
            )
        if len(splits) != len(set(splits)):
            issues.append(
                {
                    "code": "duplicate_split_manifest",
                    "path": "split",
                    "message": "Provide at most one manifest for each train/validation/test split.",
                    "source": "<combined-manifests>",
                }
            )
        missing_required = sorted(_REQUIRED_SPLITS - set(splits))
        if missing_required:
            issues.append(
                {
                    "code": "missing_required_split",
                    "path": "split",
                    "message": "Training export requires train and validation manifests; missing: "
                    + ", ".join(missing_required),
                    "source": "<combined-manifests>",
                }
            )

    return loaded, issues


def export_training_package(
    manifest_paths: Sequence[Path],
    output_dir: Path,
) -> dict[str, Any]:
    """Validate and materialize one deterministic YOLO package.

    The output path must not already exist. Images are copied into the package so
    YOLO's conventional sibling ``images``/``labels`` layout is self-contained.
    """

    if not manifest_paths:
        raise E1TrainingExportInputError(
            "no_manifests",
            "At least train and validation manifest paths are required.",
        )
    if output_dir.exists():
        raise E1TrainingExportInputError(
            "output_exists",
            f"Refusing to overwrite existing output path: {output_dir}",
        )

    loaded, issues = _validate_manifest_collection(manifest_paths)
    if issues:
        return {"ok": False, "output_dir": str(output_dir), "issues": issues}

    role = _normalized_role(loaded[0][1].get("model_role"))
    class_order = class_order_for_role(role)
    expected = expected_classes_for_role(role)
    if not class_order or set(class_order) != set(expected):
        raise E1TrainingExportInputError(
            "class_order_contract_mismatch",
            f"YOLO class order does not match frozen {role} trainable classes.",
        )
    class_index = {
        canonical_id: index for index, canonical_id in enumerate(class_order)
    }

    dataset_id = _read_string(loaded[0][1].get("dataset_id"))
    dataset_version = _read_string(loaded[0][1].get("dataset_version"))
    available_splits = {
        _normalized_split(manifest.get("split")) for _, manifest in loaded
    }

    output_parent = output_dir.parent.resolve()
    output_parent.mkdir(parents=True, exist_ok=True)
    staging = Path(
        tempfile.mkdtemp(prefix=f".{output_dir.name}.staging-", dir=str(output_parent))
    )

    samples_out: list[dict[str, Any]] = []
    split_summary: dict[str, dict[str, int]] = {}

    try:
        for split in _ALLOWED_SPLITS:
            if split not in available_splits:
                continue
            (staging / "images" / split).mkdir(parents=True, exist_ok=True)
            (staging / "labels" / split).mkdir(parents=True, exist_ok=True)

        for manifest_path, manifest in loaded:
            split = _normalized_split(manifest.get("split"))
            sample_count = 0
            annotation_count = 0
            for raw_sample in manifest.get("samples", []):
                sample_id = _read_string(raw_sample.get("sample_id"))
                source_group_id = _read_string(raw_sample.get("source_group_id"))
                image_path = _read_string(raw_sample.get("image_path"))
                if not _safe_sample_id(sample_id):
                    raise E1TrainingExportInputError(
                        "unsafe_sample_id",
                        "sample_id must be a portable filename stem using only "
                        f"letters, digits, dot, underscore or hyphen: {sample_id!r}",
                    )
                source_image = _resolve_image_path(manifest_path, image_path)
                if not source_image.is_file():
                    raise E1TrainingExportInputError(
                        "missing_source_image",
                        f"Image for sample {sample_id} does not exist: {source_image}",
                    )
                if source_image.stat().st_size <= 0:
                    raise E1TrainingExportInputError(
                        "empty_source_image",
                        f"Image for sample {sample_id} is empty: {source_image}",
                    )

                suffix = source_image.suffix.lower() or ".img"
                export_image_rel = Path("images") / split / f"{sample_id}{suffix}"
                export_label_rel = Path("labels") / split / f"{sample_id}.txt"
                export_image = staging / export_image_rel
                export_label = staging / export_label_rel
                shutil.copy2(source_image, export_image)

                annotations = list(raw_sample.get("annotations", []))
                annotations.sort(
                    key=lambda item: _read_string(item.get("annotation_id"))
                )
                label_lines = [
                    _yolo_line(annotation, class_index=class_index)
                    for annotation in annotations
                ]
                export_label.write_text(
                    ("\n".join(label_lines) + "\n") if label_lines else "",
                    encoding="utf-8",
                )

                sample_count += 1
                annotation_count += len(annotations)
                samples_out.append(
                    {
                        "sample_id": sample_id,
                        "split": split,
                        "source_group_id": source_group_id,
                        "source_manifest": str(manifest_path),
                        "source_image_path": str(source_image),
                        "source_image_sha256": _sha256_file(source_image),
                        "export_image_path": export_image_rel.as_posix(),
                        "export_label_path": export_label_rel.as_posix(),
                        "annotation_count": len(annotations),
                        "negative_tags": sorted(raw_sample.get("negative_tags", [])),
                    }
                )
            split_summary[split] = {
                "sample_count": sample_count,
                "annotation_count": annotation_count,
            }

        samples_out.sort(key=lambda item: (item["split"], item["sample_id"]))
        class_map = [
            {"index": index, "canonical_object_id": canonical_id}
            for index, canonical_id in enumerate(class_order)
        ]
        export_manifest = {
            "export_schema_version": E1_TRAINING_EXPORT_SCHEMA_VERSION,
            "taxonomy_version": E1_TAXONOMY_VERSION,
            "dataset_id": dataset_id,
            "dataset_version": dataset_version,
            "model_role": role,
            "class_map": class_map,
            "source_manifests": [str(path) for path, _ in loaded],
            "splits": split_summary,
            "samples": samples_out,
        }

        (staging / "dataset.yaml").write_text(
            _dataset_yaml(class_order, available_splits), encoding="utf-8"
        )
        (staging / "export_manifest.json").write_text(
            json.dumps(export_manifest, indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
        )
        staging.rename(output_dir)
    except Exception:
        shutil.rmtree(staging, ignore_errors=True)
        raise

    return {
        "ok": True,
        "output_dir": str(output_dir),
        "dataset_id": dataset_id,
        "dataset_version": dataset_version,
        "model_role": role,
        "class_count": len(class_order),
        "sample_count": len(samples_out),
        "annotation_count": sum(item["annotation_count"] for item in samples_out),
        "splits": split_summary,
        "issues": [],
    }


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="python -m ai_runtime.e1_training_export",
        description="Export validated E1 manifests into a self-contained YOLO package.",
    )
    parser.add_argument(
        "--pretty", action="store_true", help="Pretty-print JSON status output."
    )
    parser.add_argument(
        "--output",
        required=True,
        type=Path,
        help="New output directory; must not already exist.",
    )
    parser.add_argument("manifests", nargs="+", type=Path)
    return parser


def main(argv: Sequence[str] | None = None, *, stdout: TextIO | None = None) -> int:
    parser = _build_parser()
    args = parser.parse_args(argv)
    output = stdout if stdout is not None else sys.stdout
    try:
        result = export_training_package(args.manifests, args.output)
    except E1TrainingExportInputError as exc:
        result = {
            "ok": False,
            "output_dir": str(args.output),
            "issues": [
                {"code": exc.code, "path": "$", "message": exc.message}
            ],
        }

    json.dump(result, output, indent=2 if args.pretty else None, sort_keys=True)
    output.write("\n")
    output.flush()
    return 0 if result["ok"] else 1


if __name__ == "__main__":
    raise SystemExit(main())

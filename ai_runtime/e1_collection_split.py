"""Create deterministic E1 dataset split plans without leaking source groups.

Development-time tooling only. The caller must explicitly supply train,
validation, and test weights plus a split seed. This module never chooses a
scientific split ratio on behalf of the project and never participates in live
exam inference.
"""

from __future__ import annotations

import argparse
from collections import defaultdict
from contextlib import suppress
import hashlib
import json
import math
from pathlib import Path
import sys
from typing import Any, Mapping, Sequence, TextIO


E1_COLLECTION_SCHEMA_VERSION = "1.0"
E1_SPLIT_PLAN_SCHEMA_VERSION = "1.0"
_SPLITS = ("train", "validation", "test")
_ALLOWED_ROLES = frozenset({"base", "specialist"})


class E1CollectionSplitInputError(ValueError):
    def __init__(self, code: str, message: str):
        super().__init__(message)
        self.code = code
        self.message = message


def _read_string(value: Any) -> str:
    return value.strip() if isinstance(value, str) else ""


def _lower_string(value: Any) -> str:
    return _read_string(value).lower()


def _positive_int(value: Any) -> int | None:
    if isinstance(value, bool) or not isinstance(value, int) or value <= 0:
        return None
    return value


def _weight(value: Any) -> float | None:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        return None
    number = float(value)
    if not math.isfinite(number) or number < 0.0:
        return None
    return number


def _normalized_path(value: Any) -> str:
    path = _read_string(value).replace("\\", "/")
    while path.startswith("./"):
        path = path[2:]
    return path


def _stable_rank(seed: str, source_group_id: str) -> str:
    return hashlib.sha256(f"{seed}\x1f{source_group_id}".encode("utf-8")).hexdigest()


def _load_json_object(path: Path) -> Mapping[str, Any]:
    try:
        raw = path.read_text(encoding="utf-8")
    except OSError as exc:
        raise E1CollectionSplitInputError(
            "input_read_error", f"Could not read {path}: {exc}"
        ) from exc
    try:
        value = json.loads(raw)
    except json.JSONDecodeError as exc:
        raise E1CollectionSplitInputError(
            "invalid_json",
            f"Invalid JSON in {path} at line {exc.lineno}, column {exc.colno}: {exc.msg}",
        ) from exc
    if not isinstance(value, Mapping):
        raise E1CollectionSplitInputError(
            "json_root_not_object", "Top-level collection JSON must be an object."
        )
    return value


def _validate_collection(
    collection: Mapping[str, Any],
) -> tuple[dict[str, Any] | None, list[dict[str, str]]]:
    issues: list[dict[str, str]] = []

    def add(code: str, path: str, message: str) -> None:
        issues.append({"code": code, "path": path, "message": message})

    if _read_string(collection.get("collection_schema_version")) != E1_COLLECTION_SCHEMA_VERSION:
        add(
            "invalid_collection_schema_version",
            "collection_schema_version",
            f"collection_schema_version must be {E1_COLLECTION_SCHEMA_VERSION}.",
        )

    dataset_id = _read_string(collection.get("dataset_id"))
    dataset_version = _read_string(collection.get("dataset_version"))
    model_role = _lower_string(collection.get("model_role"))
    split_seed = _read_string(collection.get("split_seed"))
    if not dataset_id:
        add("missing_dataset_id", "dataset_id", "dataset_id is required.")
    if not dataset_version:
        add("missing_dataset_version", "dataset_version", "dataset_version is required.")
    if model_role not in _ALLOWED_ROLES:
        add("invalid_model_role", "model_role", "model_role must be 'base' or 'specialist'.")
    if not split_seed:
        add(
            "missing_split_seed",
            "split_seed",
            "split_seed is required so split assignment is reproducible.",
        )

    raw_weights = collection.get("split_weights")
    weights: dict[str, float] = {}
    if not isinstance(raw_weights, Mapping):
        add(
            "invalid_split_weights",
            "split_weights",
            "split_weights must explicitly contain train, validation, and test weights.",
        )
    else:
        extra = sorted(set(str(key) for key in raw_weights) - set(_SPLITS))
        if extra:
            add(
                "unknown_split_weight",
                "split_weights",
                f"Unknown split weight keys: {', '.join(extra)}.",
            )
        for split in _SPLITS:
            value = _weight(raw_weights.get(split))
            if value is None:
                add(
                    "invalid_split_weight",
                    f"split_weights.{split}",
                    f"{split} weight must be a finite non-negative number and must be supplied explicitly.",
                )
            else:
                weights[split] = value
        if len(weights) == len(_SPLITS) and sum(weights.values()) <= 0.0:
            add(
                "zero_split_weights",
                "split_weights",
                "At least one split weight must be greater than zero.",
            )

    raw_records = collection.get("records")
    records: list[dict[str, Any]] = []
    seen_paths: set[str] = set()
    if not isinstance(raw_records, Sequence) or isinstance(raw_records, (str, bytes)):
        add("invalid_records", "records", "records must be a list.")
    elif not raw_records:
        add("empty_records", "records", "At least one collected image record is required.")
    else:
        for index, raw_record in enumerate(raw_records):
            path = f"records[{index}]"
            if not isinstance(raw_record, Mapping):
                add("invalid_record", path, "Each record must be an object.")
                continue
            source_group_id = _read_string(raw_record.get("source_group_id"))
            image_path = _normalized_path(raw_record.get("image_path"))
            width = _positive_int(raw_record.get("width"))
            height = _positive_int(raw_record.get("height"))
            if not source_group_id:
                add(
                    "missing_source_group_id",
                    f"{path}.source_group_id",
                    "source_group_id must be assigned by the collection workflow; splitting will not infer it.",
                )
            if not image_path:
                add("missing_image_path", f"{path}.image_path", "image_path is required.")
            elif image_path in seen_paths:
                add(
                    "duplicate_image_path",
                    f"{path}.image_path",
                    f"Duplicate normalized image_path: {image_path}.",
                )
            else:
                seen_paths.add(image_path)
            if width is None:
                add("invalid_width", f"{path}.width", "width must be a positive integer.")
            if height is None:
                add("invalid_height", f"{path}.height", "height must be a positive integer.")
            if source_group_id and image_path and width is not None and height is not None:
                records.append(
                    {
                        "source_group_id": source_group_id,
                        "image_path": image_path,
                        "width": width,
                        "height": height,
                    }
                )

    if issues:
        return None, issues
    return {
        "dataset_id": dataset_id,
        "dataset_version": dataset_version,
        "model_role": model_role,
        "split_seed": split_seed,
        "split_weights": weights,
        "records": records,
    }, []


def _choose_split(
    *,
    group_size: int,
    assigned_records: Mapping[str, int],
    targets: Mapping[str, float],
    weights: Mapping[str, float],
) -> str:
    candidates = [split for split in _SPLITS if weights[split] > 0.0]
    best_split = candidates[0]
    best_score: float | None = None
    for split in candidates:
        score = 0.0
        for candidate in candidates:
            count = assigned_records[candidate] + (group_size if candidate == split else 0)
            target = targets[candidate]
            scale = max(target, 1.0)
            score += ((count - target) / scale) ** 2
        if best_score is None or score < best_score - 1e-12:
            best_split = split
            best_score = score
    return best_split


def build_split_plan(
    collection: Mapping[str, Any],
) -> tuple[dict[str, Any] | None, list[dict[str, str]]]:
    normalized, issues = _validate_collection(collection)
    if normalized is None:
        return None, issues

    records = normalized["records"]
    weights = normalized["split_weights"]
    seed = normalized["split_seed"]
    groups: dict[str, list[dict[str, Any]]] = defaultdict(list)
    for record in records:
        groups[record["source_group_id"]].append(record)

    total_records = len(records)
    total_weight = sum(weights.values())
    targets = {
        split: total_records * weights[split] / total_weight for split in _SPLITS
    }
    assigned_records = {split: 0 for split in _SPLITS}
    assigned_groups = {split: 0 for split in _SPLITS}
    group_assignment: dict[str, str] = {}

    ordered_groups = sorted(
        groups.items(),
        key=lambda item: (-len(item[1]), _stable_rank(seed, item[0]), item[0]),
    )
    for source_group_id, group_records in ordered_groups:
        split = _choose_split(
            group_size=len(group_records),
            assigned_records=assigned_records,
            targets=targets,
            weights=weights,
        )
        group_assignment[source_group_id] = split
        assigned_records[split] += len(group_records)
        assigned_groups[split] += 1

    planned_records = [
        {
            **record,
            "split": group_assignment[record["source_group_id"]],
        }
        for record in sorted(records, key=lambda item: (item["source_group_id"], item["image_path"]))
    ]
    assignments = [
        {
            "source_group_id": source_group_id,
            "split": group_assignment[source_group_id],
            "record_count": len(groups[source_group_id]),
        }
        for source_group_id in sorted(groups)
    ]

    split_summary: dict[str, dict[str, Any]] = {}
    for split in _SPLITS:
        actual_records = assigned_records[split]
        split_summary[split] = {
            "weight": weights[split],
            "target_record_count": round(targets[split], 6),
            "record_count": actual_records,
            "source_group_count": assigned_groups[split],
            "actual_record_fraction": round(actual_records / total_records, 10),
        }

    return {
        "split_plan_schema_version": E1_SPLIT_PLAN_SCHEMA_VERSION,
        "dataset_id": normalized["dataset_id"],
        "dataset_version": normalized["dataset_version"],
        "model_role": normalized["model_role"],
        "split_seed": seed,
        "split_weights": weights,
        "summary": {
            "record_count": total_records,
            "source_group_count": len(groups),
            "splits": split_summary,
        },
        "assignments": assignments,
        "records": planned_records,
    }, []


def split_plan_is_group_disjoint(plan: Mapping[str, Any]) -> bool:
    seen: dict[str, str] = {}
    records = plan.get("records")
    if not isinstance(records, list):
        return False
    for record in records:
        if not isinstance(record, Mapping):
            return False
        group_id = _read_string(record.get("source_group_id"))
        split = _lower_string(record.get("split"))
        if not group_id or split not in _SPLITS:
            return False
        previous = seen.setdefault(group_id, split)
        if previous != split:
            return False
    return True


def create_split_plan_file(
    input_path: Path,
    output_path: Path,
    *,
    force: bool = False,
) -> dict[str, Any]:
    try:
        if input_path.resolve() == output_path.resolve():
            return {
                "command": "split",
                "ok": False,
                "input": str(input_path),
                "output": str(output_path),
                "issues": [{
                    "code": "input_output_same",
                    "path": "$",
                    "message": "Collection inventory and split-plan output must be different files.",
                }],
            }
    except OSError:
        pass

    if output_path.exists() and not force:
        return {
            "command": "split",
            "ok": False,
            "input": str(input_path),
            "output": str(output_path),
            "issues": [{
                "code": "output_exists",
                "path": "$",
                "message": "Output already exists; pass --force to replace it.",
            }],
        }

    try:
        collection = _load_json_object(input_path)
    except E1CollectionSplitInputError as exc:
        return {
            "command": "split",
            "ok": False,
            "input": str(input_path),
            "output": str(output_path),
            "issues": [{"code": exc.code, "path": "$", "message": exc.message}],
        }

    plan, issues = build_split_plan(collection)
    if plan is None:
        return {
            "command": "split",
            "ok": False,
            "input": str(input_path),
            "output": str(output_path),
            "issues": issues,
        }
    if not split_plan_is_group_disjoint(plan):
        return {
            "command": "split",
            "ok": False,
            "input": str(input_path),
            "output": str(output_path),
            "issues": [{
                "code": "internal_group_leakage",
                "path": "$",
                "message": "Generated plan violated the source-group split invariant.",
            }],
        }

    temporary = output_path.with_name(f".{output_path.name}.tmp")
    try:
        output_path.parent.mkdir(parents=True, exist_ok=True)
        temporary.write_text(json.dumps(plan, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        temporary.replace(output_path)
    except OSError as exc:
        with suppress(OSError):
            temporary.unlink()
        return {
            "command": "split",
            "ok": False,
            "input": str(input_path),
            "output": str(output_path),
            "issues": [{
                "code": "output_write_error",
                "path": "$",
                "message": f"Could not write split plan: {exc}",
            }],
        }

    return {
        "command": "split",
        "ok": True,
        "input": str(input_path),
        "output": str(output_path),
        "summary": plan["summary"],
        "issues": [],
    }


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="python -m ai_runtime.e1_collection_split",
        description="Create a deterministic source-group-safe E1 dataset split plan.",
    )
    parser.add_argument("input", type=Path, help="Collection inventory JSON.")
    parser.add_argument("output", type=Path, help="Split-plan JSON to create.")
    parser.add_argument("--force", action="store_true", help="Replace an existing output file.")
    parser.add_argument("--pretty", action="store_true", help="Pretty-print command result JSON.")
    return parser


def main(argv: Sequence[str] | None = None, *, stdout: TextIO | None = None) -> int:
    args = _build_parser().parse_args(argv)
    output = stdout if stdout is not None else sys.stdout
    result = create_split_plan_file(args.input, args.output, force=args.force)
    json.dump(result, output, indent=2 if args.pretty else None, sort_keys=True)
    output.write("\n")
    with suppress(AttributeError):
        output.flush()
    return 0 if result["ok"] else 1


if __name__ == "__main__":
    raise SystemExit(main())

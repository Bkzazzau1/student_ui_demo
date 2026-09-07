"""Create and finalize explicit E1 annotation worklists.

Development-time tooling only. Worklists keep unreviewed images in a `pending`
state so an empty annotation list can never be silently interpreted as a
confirmed negative during the normal collection workflow.
"""

from __future__ import annotations

import argparse
from contextlib import suppress
import json
from pathlib import Path
import sys
from typing import Any, Mapping, Sequence, TextIO

from .e1_annotation_ingest import (
    E1_ANNOTATION_INGEST_SCHEMA_VERSION,
    build_dataset_manifest,
)
from .e1_collection_split import E1_SPLIT_PLAN_SCHEMA_VERSION, split_plan_is_group_disjoint


E1_ANNOTATION_WORKLIST_SCHEMA_VERSION = "1.0"
_STATUSES = frozenset({"pending", "positive_confirmed", "negative_confirmed"})
_SPLITS = ("train", "validation", "test")


class E1AnnotationWorklistInputError(ValueError):
    def __init__(self, code: str, message: str):
        super().__init__(message)
        self.code = code
        self.message = message


def _read_string(value: Any) -> str:
    return value.strip() if isinstance(value, str) else ""


def _lower_string(value: Any) -> str:
    return _read_string(value).lower()


def _load_json_object(path: Path) -> Mapping[str, Any]:
    try:
        raw = path.read_text(encoding="utf-8")
    except OSError as exc:
        raise E1AnnotationWorklistInputError(
            "input_read_error", f"Could not read {path}: {exc}"
        ) from exc
    try:
        value = json.loads(raw)
    except json.JSONDecodeError as exc:
        raise E1AnnotationWorklistInputError(
            "invalid_json",
            f"Invalid JSON in {path} at line {exc.lineno}, column {exc.colno}: {exc.msg}",
        ) from exc
    if not isinstance(value, Mapping):
        raise E1AnnotationWorklistInputError(
            "json_root_not_object", "Top-level JSON value must be an object."
        )
    return value


def build_worklists_from_split_plan(
    plan: Mapping[str, Any],
) -> tuple[dict[str, dict[str, Any]] | None, list[dict[str, str]]]:
    issues: list[dict[str, str]] = []

    def add(code: str, path: str, message: str) -> None:
        issues.append({"code": code, "path": path, "message": message})

    if _read_string(plan.get("split_plan_schema_version")) != E1_SPLIT_PLAN_SCHEMA_VERSION:
        add(
            "invalid_split_plan_schema_version",
            "split_plan_schema_version",
            f"split_plan_schema_version must be {E1_SPLIT_PLAN_SCHEMA_VERSION}.",
        )
    if not split_plan_is_group_disjoint(plan):
        add(
            "unsafe_split_plan",
            "records",
            "Split plan must keep every source_group_id entirely inside one split.",
        )

    dataset_id = _read_string(plan.get("dataset_id"))
    dataset_version = _read_string(plan.get("dataset_version"))
    model_role = _lower_string(plan.get("model_role"))
    split_seed = _read_string(plan.get("split_seed"))
    if not dataset_id:
        add("missing_dataset_id", "dataset_id", "dataset_id is required.")
    if not dataset_version:
        add("missing_dataset_version", "dataset_version", "dataset_version is required.")
    if model_role not in {"base", "specialist"}:
        add("invalid_model_role", "model_role", "model_role must be base or specialist.")
    if not split_seed:
        add("missing_split_seed", "split_seed", "split_seed is required for provenance.")

    raw_records = plan.get("records")
    if not isinstance(raw_records, Sequence) or isinstance(raw_records, (str, bytes)):
        add("invalid_records", "records", "Split-plan records must be a list.")
        return None, issues

    by_split: dict[str, list[dict[str, Any]]] = {split: [] for split in _SPLITS}
    seen_paths: set[str] = set()
    for index, raw_record in enumerate(raw_records):
        path = f"records[{index}]"
        if not isinstance(raw_record, Mapping):
            add("invalid_record", path, "Each split-plan record must be an object.")
            continue
        split = _lower_string(raw_record.get("split"))
        source_group_id = _read_string(raw_record.get("source_group_id"))
        image_path = _read_string(raw_record.get("image_path"))
        width = raw_record.get("width")
        height = raw_record.get("height")
        if split not in _SPLITS:
            add("invalid_split", f"{path}.split", "Record split must be train, validation, or test.")
        if not source_group_id:
            add("missing_source_group_id", f"{path}.source_group_id", "source_group_id is required.")
        if not image_path:
            add("missing_image_path", f"{path}.image_path", "image_path is required.")
        elif image_path in seen_paths:
            add("duplicate_image_path", f"{path}.image_path", f"Duplicate image_path: {image_path}.")
        else:
            seen_paths.add(image_path)
        if not isinstance(width, int) or isinstance(width, bool) or width <= 0:
            add("invalid_width", f"{path}.width", "width must be a positive integer.")
        if not isinstance(height, int) or isinstance(height, bool) or height <= 0:
            add("invalid_height", f"{path}.height", "height must be a positive integer.")
        if (
            split in _SPLITS
            and source_group_id
            and image_path
            and isinstance(width, int)
            and not isinstance(width, bool)
            and width > 0
            and isinstance(height, int)
            and not isinstance(height, bool)
            and height > 0
        ):
            by_split[split].append(
                {
                    "source_group_id": source_group_id,
                    "image_path": image_path,
                    "width": width,
                    "height": height,
                    "annotation_status": "pending",
                }
            )

    if issues:
        return None, issues

    worklists: dict[str, dict[str, Any]] = {}
    for split in _SPLITS:
        records = sorted(
            by_split[split], key=lambda item: (item["source_group_id"], item["image_path"])
        )
        worklists[split] = {
            "worklist_schema_version": E1_ANNOTATION_WORKLIST_SCHEMA_VERSION,
            "dataset_id": dataset_id,
            "dataset_version": dataset_version,
            "model_role": model_role,
            "split": split,
            "split_seed": split_seed,
            "records": records,
        }
    return worklists, []


def finalize_worklist(
    worklist: Mapping[str, Any],
) -> tuple[dict[str, Any] | None, list[dict[str, str]]]:
    issues: list[dict[str, str]] = []

    def add(code: str, path: str, message: str) -> None:
        issues.append({"code": code, "path": path, "message": message})

    if _read_string(worklist.get("worklist_schema_version")) != E1_ANNOTATION_WORKLIST_SCHEMA_VERSION:
        add(
            "invalid_worklist_schema_version",
            "worklist_schema_version",
            f"worklist_schema_version must be {E1_ANNOTATION_WORKLIST_SCHEMA_VERSION}.",
        )

    dataset_id = _read_string(worklist.get("dataset_id"))
    dataset_version = _read_string(worklist.get("dataset_version"))
    model_role = _lower_string(worklist.get("model_role"))
    split = _lower_string(worklist.get("split"))
    if not dataset_id:
        add("missing_dataset_id", "dataset_id", "dataset_id is required.")
    if not dataset_version:
        add("missing_dataset_version", "dataset_version", "dataset_version is required.")
    if model_role not in {"base", "specialist"}:
        add("invalid_model_role", "model_role", "model_role must be base or specialist.")
    if split not in _SPLITS:
        add("invalid_split", "split", "split must be train, validation, or test.")

    raw_records = worklist.get("records")
    if not isinstance(raw_records, Sequence) or isinstance(raw_records, (str, bytes)):
        add("invalid_records", "records", "records must be a list.")
        return None, issues

    staging_records: list[dict[str, Any]] = []
    for index, raw_record in enumerate(raw_records):
        path = f"records[{index}]"
        if not isinstance(raw_record, Mapping):
            add("invalid_record", path, "Each worklist record must be an object.")
            continue

        status = _lower_string(raw_record.get("annotation_status"))
        if status not in _STATUSES:
            add(
                "invalid_annotation_status",
                f"{path}.annotation_status",
                "annotation_status must be pending, positive_confirmed, or negative_confirmed.",
            )
            continue
        if status == "pending":
            add(
                "annotation_pending",
                f"{path}.annotation_status",
                "Pending records cannot be finalized into training staging data.",
            )
            continue

        annotations = raw_record.get("annotations", [])
        if not isinstance(annotations, Sequence) or isinstance(annotations, (str, bytes)):
            add("invalid_annotations", f"{path}.annotations", "annotations must be a list.")
            continue
        if status == "positive_confirmed" and len(annotations) == 0:
            add(
                "positive_without_annotations",
                f"{path}.annotations",
                "positive_confirmed requires at least one annotation.",
            )
            continue
        if status == "negative_confirmed" and len(annotations) != 0:
            add(
                "negative_with_annotations",
                f"{path}.annotations",
                "negative_confirmed must not contain positive annotations.",
            )
            continue

        negative_tags = raw_record.get("negative_tags", [])
        if not isinstance(negative_tags, Sequence) or isinstance(negative_tags, (str, bytes)):
            add("invalid_negative_tags", f"{path}.negative_tags", "negative_tags must be a list.")
            continue

        staging_records.append(
            {
                "source_group_id": raw_record.get("source_group_id"),
                "image_path": raw_record.get("image_path"),
                "width": raw_record.get("width"),
                "height": raw_record.get("height"),
                "annotation_status": status,
                "negative_tags": list(negative_tags),
                "annotations": list(annotations),
            }
        )

    if issues:
        return None, issues

    staging = {
        "ingest_schema_version": E1_ANNOTATION_INGEST_SCHEMA_VERSION,
        "dataset_id": dataset_id,
        "dataset_version": dataset_version,
        "model_role": model_role,
        "split": split,
        "records": staging_records,
    }
    manifest, ingest_issues = build_dataset_manifest(staging)
    if manifest is None:
        return None, [
            {"code": issue.code, "path": issue.path, "message": issue.message}
            for issue in ingest_issues
        ]
    return staging, []


def create_worklist_files(
    split_plan_path: Path,
    output_directory: Path,
    *,
    force: bool = False,
) -> dict[str, Any]:
    try:
        plan = _load_json_object(split_plan_path)
    except E1AnnotationWorklistInputError as exc:
        return {
            "command": "create",
            "ok": False,
            "input": str(split_plan_path),
            "output_directory": str(output_directory),
            "issues": [{"code": exc.code, "path": "$", "message": exc.message}],
        }

    worklists, issues = build_worklists_from_split_plan(plan)
    if worklists is None:
        return {
            "command": "create",
            "ok": False,
            "input": str(split_plan_path),
            "output_directory": str(output_directory),
            "issues": issues,
        }

    output_paths = {
        split: output_directory / f"{split}.annotation-worklist.json" for split in _SPLITS
    }
    existing = [str(path) for path in output_paths.values() if path.exists()]
    if existing and not force:
        return {
            "command": "create",
            "ok": False,
            "input": str(split_plan_path),
            "output_directory": str(output_directory),
            "issues": [{
                "code": "output_exists",
                "path": "$",
                "message": "Worklist output already exists; pass --force to replace it: " + ", ".join(existing),
            }],
        }

    try:
        output_directory.mkdir(parents=True, exist_ok=True)
        for split, path in output_paths.items():
            temporary = path.with_name(f".{path.name}.tmp")
            temporary.write_text(
                json.dumps(worklists[split], indent=2, sort_keys=True) + "\n",
                encoding="utf-8",
            )
            temporary.replace(path)
    except OSError as exc:
        for path in output_paths.values():
            with suppress(OSError):
                path.with_name(f".{path.name}.tmp").unlink()
        return {
            "command": "create",
            "ok": False,
            "input": str(split_plan_path),
            "output_directory": str(output_directory),
            "issues": [{
                "code": "output_write_error",
                "path": "$",
                "message": f"Could not write annotation worklists: {exc}",
            }],
        }

    return {
        "command": "create",
        "ok": True,
        "input": str(split_plan_path),
        "output_directory": str(output_directory),
        "files": {split: str(path) for split, path in output_paths.items()},
        "counts": {split: len(worklists[split]["records"]) for split in _SPLITS},
        "issues": [],
    }


def finalize_worklist_file(
    input_path: Path,
    output_path: Path,
    *,
    force: bool = False,
) -> dict[str, Any]:
    try:
        if input_path.resolve() == output_path.resolve():
            return {
                "command": "finalize",
                "ok": False,
                "input": str(input_path),
                "output": str(output_path),
                "issues": [{
                    "code": "input_output_same",
                    "path": "$",
                    "message": "Worklist and staging output must be different files.",
                }],
            }
    except OSError:
        pass

    if output_path.exists() and not force:
        return {
            "command": "finalize",
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
        worklist = _load_json_object(input_path)
    except E1AnnotationWorklistInputError as exc:
        return {
            "command": "finalize",
            "ok": False,
            "input": str(input_path),
            "output": str(output_path),
            "issues": [{"code": exc.code, "path": "$", "message": exc.message}],
        }

    staging, issues = finalize_worklist(worklist)
    if staging is None:
        return {
            "command": "finalize",
            "ok": False,
            "input": str(input_path),
            "output": str(output_path),
            "issues": issues,
        }

    temporary = output_path.with_name(f".{output_path.name}.tmp")
    try:
        output_path.parent.mkdir(parents=True, exist_ok=True)
        temporary.write_text(json.dumps(staging, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        temporary.replace(output_path)
    except OSError as exc:
        with suppress(OSError):
            temporary.unlink()
        return {
            "command": "finalize",
            "ok": False,
            "input": str(input_path),
            "output": str(output_path),
            "issues": [{
                "code": "output_write_error",
                "path": "$",
                "message": f"Could not write staging file: {exc}",
            }],
        }

    positives = sum(1 for record in staging["records"] if record["annotation_status"] == "positive_confirmed")
    negatives = sum(1 for record in staging["records"] if record["annotation_status"] == "negative_confirmed")
    return {
        "command": "finalize",
        "ok": True,
        "input": str(input_path),
        "output": str(output_path),
        "record_count": len(staging["records"]),
        "positive_confirmed": positives,
        "negative_confirmed": negatives,
        "issues": [],
    }


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="python -m ai_runtime.e1_annotation_worklist",
        description="Create E1 annotation worklists and finalize only explicitly reviewed records.",
    )
    subparsers = parser.add_subparsers(dest="command", required=True)

    create = subparsers.add_parser("create", help="Create pending worklists from a split plan.")
    create.add_argument("split_plan", type=Path)
    create.add_argument("output_directory", type=Path)
    create.add_argument("--force", action="store_true")
    create.add_argument("--pretty", action="store_true")

    finalize = subparsers.add_parser("finalize", help="Convert one completed worklist into ingest staging JSON.")
    finalize.add_argument("worklist", type=Path)
    finalize.add_argument("output", type=Path)
    finalize.add_argument("--force", action="store_true")
    finalize.add_argument("--pretty", action="store_true")
    return parser


def main(argv: Sequence[str] | None = None, *, stdout: TextIO | None = None) -> int:
    args = _build_parser().parse_args(argv)
    output = stdout if stdout is not None else sys.stdout
    if args.command == "create":
        result = create_worklist_files(args.split_plan, args.output_directory, force=args.force)
    else:
        result = finalize_worklist_file(args.worklist, args.output, force=args.force)
    json.dump(result, output, indent=2 if args.pretty else None, sort_keys=True)
    output.write("\n")
    with suppress(AttributeError):
        output.flush()
    return 0 if result["ok"] else 1


if __name__ == "__main__":
    raise SystemExit(main())

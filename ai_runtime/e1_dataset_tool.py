"""Command-line tooling for E1 dataset and evaluation readiness.

This module is development-time tooling only. It validates files produced by
E1 dataset construction, annotation, evaluation, and calibration workflows. It
is never imported by the live exam inference path.
"""

from __future__ import annotations

import argparse
from collections import Counter
from contextlib import suppress
import json
from pathlib import Path
import sys
from typing import Any, Mapping, Sequence, TextIO

from .e1_training_readiness import (
    ValidationIssue,
    calibration_complete,
    validate_dataset_manifest,
    validate_evaluation_report,
    validate_split_disjointness,
)


class E1DatasetToolInputError(ValueError):
    """Raised when an input file cannot be read as a JSON object."""

    def __init__(self, code: str, message: str):
        super().__init__(message)
        self.code = code
        self.message = message


def _load_json_object(path: Path) -> Mapping[str, Any]:
    try:
        raw = path.read_text(encoding="utf-8")
    except OSError as exc:
        raise E1DatasetToolInputError(
            "input_read_error", f"Could not read {path}: {exc}"
        ) from exc

    try:
        value = json.loads(raw)
    except json.JSONDecodeError as exc:
        raise E1DatasetToolInputError(
            "invalid_json",
            f"Invalid JSON in {path} at line {exc.lineno}, column {exc.colno}: {exc.msg}",
        ) from exc

    if not isinstance(value, Mapping):
        raise E1DatasetToolInputError(
            "json_root_not_object", f"Top-level JSON value in {path} must be an object."
        )
    return value


def _issue_dict(
    issue: ValidationIssue,
    *,
    source: str | None = None,
) -> dict[str, str]:
    result = {
        "code": issue.code,
        "path": issue.path,
        "message": issue.message,
    }
    if source is not None:
        result["source"] = source
    return result


def _input_issue_dict(path: Path, exc: E1DatasetToolInputError) -> dict[str, str]:
    return {
        "code": exc.code,
        "path": "$",
        "message": exc.message,
        "source": str(path),
    }


def _dataset_summary(manifests: Sequence[Mapping[str, Any]]) -> dict[str, Any]:
    sample_count = 0
    annotation_count = 0
    class_counts: Counter[str] = Counter()
    negative_tag_counts: Counter[str] = Counter()
    splits: Counter[str] = Counter()
    roles: Counter[str] = Counter()

    for manifest in manifests:
        split = manifest.get("split")
        if isinstance(split, str) and split.strip():
            splits[split.strip().lower()] += 1
        role = manifest.get("model_role")
        if isinstance(role, str) and role.strip():
            roles[role.strip().lower()] += 1

        samples = manifest.get("samples")
        if not isinstance(samples, list):
            continue
        sample_count += len(samples)
        for sample in samples:
            if not isinstance(sample, Mapping):
                continue
            tags = sample.get("negative_tags", [])
            if isinstance(tags, list):
                for tag in tags:
                    if isinstance(tag, str) and tag.strip():
                        negative_tag_counts[tag.strip().lower()] += 1

            annotations = sample.get("annotations", [])
            if not isinstance(annotations, list):
                continue
            annotation_count += len(annotations)
            for annotation in annotations:
                if not isinstance(annotation, Mapping):
                    continue
                canonical_id = annotation.get("canonical_object_id")
                if isinstance(canonical_id, str) and canonical_id.strip():
                    class_counts[canonical_id.strip().lower()] += 1

    return {
        "manifest_count": len(manifests),
        "sample_count": sample_count,
        "annotation_count": annotation_count,
        "class_counts": dict(sorted(class_counts.items())),
        "negative_tag_counts": dict(sorted(negative_tag_counts.items())),
        "splits": dict(sorted(splits.items())),
        "roles": dict(sorted(roles.items())),
    }


def validate_dataset_files(paths: Sequence[Path]) -> dict[str, Any]:
    manifests: list[Mapping[str, Any]] = []
    manifest_sources: list[str] = []
    issues: list[dict[str, str]] = []

    for path in paths:
        try:
            manifest = _load_json_object(path)
        except E1DatasetToolInputError as exc:
            issues.append(_input_issue_dict(path, exc))
            continue

        manifests.append(manifest)
        manifest_sources.append(str(path))
        for issue in validate_dataset_manifest(manifest):
            issues.append(_issue_dict(issue, source=str(path)))

    if manifests:
        for issue in validate_split_disjointness(manifests):
            issues.append(_issue_dict(issue, source="<combined-manifests>"))

    return {
        "command": "dataset",
        "ok": not issues and len(manifests) == len(paths),
        "files": [str(path) for path in paths],
        "loaded_files": manifest_sources,
        "summary": _dataset_summary(manifests),
        "issues": issues,
    }


def _zero_support_issues(report: Mapping[str, Any]) -> list[ValidationIssue]:
    issues: list[ValidationIssue] = []
    class_metrics = report.get("class_metrics")
    if not isinstance(class_metrics, Mapping):
        return issues
    for canonical_id, metrics in class_metrics.items():
        if not isinstance(canonical_id, str) or not isinstance(metrics, Mapping):
            continue
        support = metrics.get("support")
        if isinstance(support, int) and not isinstance(support, bool) and support == 0:
            issues.append(
                ValidationIssue(
                    "zero_class_support",
                    f"class_metrics.{canonical_id}.support",
                    "Held-out class metrics require at least one labelled example; support=0 is not evaluation evidence.",
                )
            )
    return issues


def validate_evaluation_file(path: Path) -> dict[str, Any]:
    try:
        report = _load_json_object(path)
    except E1DatasetToolInputError as exc:
        return {
            "command": "evaluation",
            "ok": False,
            "file": str(path),
            "calibration_complete": False,
            "issues": [_input_issue_dict(path, exc)],
        }

    validation_issues = list(validate_evaluation_report(report))
    validation_issues.extend(_zero_support_issues(report))
    issues = [_issue_dict(issue, source=str(path)) for issue in validation_issues]
    complete = not issues and calibration_complete(report)

    return {
        "command": "evaluation",
        "ok": not issues,
        "file": str(path),
        "model_id": report.get("model_id"),
        "model_version": report.get("model_version"),
        "model_role": report.get("model_role"),
        "evaluation_split": report.get("evaluation_split"),
        "calibration_complete": complete,
        "issues": issues,
    }


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="python -m ai_runtime.e1_dataset_tool",
        description="Validate E1 dataset manifests and held-out evaluation reports.",
    )
    parser.add_argument(
        "--pretty",
        action="store_true",
        help="Pretty-print JSON output.",
    )
    subparsers = parser.add_subparsers(dest="command", required=True)

    dataset = subparsers.add_parser(
        "dataset",
        help="Validate one or more dataset split manifests and cross-split leakage.",
    )
    dataset.add_argument("paths", nargs="+", type=Path)

    evaluation = subparsers.add_parser(
        "evaluation",
        help="Validate a held-out evaluation/calibration report.",
    )
    evaluation.add_argument("path", type=Path)
    return parser


def main(argv: Sequence[str] | None = None, *, stdout: TextIO | None = None) -> int:
    parser = _build_parser()
    args = parser.parse_args(argv)
    output = stdout if stdout is not None else sys.stdout

    if args.command == "dataset":
        result = validate_dataset_files(args.paths)
    else:
        result = validate_evaluation_file(args.path)

    json.dump(
        result,
        output,
        indent=2 if args.pretty else None,
        sort_keys=True,
    )
    output.write("\n")
    with suppress(AttributeError):
        output.flush()
    return 0 if result["ok"] else 1


if __name__ == "__main__":
    raise SystemExit(main())

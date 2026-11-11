"""Resolve development-time E1 teacher review into human-approved annotation staging.

This module never calls external models and is never part of live exam inference.
Teacher consensus is advisory only. A human reviewer must explicitly resolve every
candidate before any annotation staging record is emitted.
"""

from __future__ import annotations

import argparse
from dataclasses import dataclass
import json
import math
import os
from pathlib import Path
import sys
import tempfile
from typing import Any, Sequence, TextIO


REVIEW_SCHEMA_VERSION = "1.0"
BASE_CLASSES = (
    "person",
    "phone",
    "laptop",
    "television",
    "keyboard",
    "mouse",
    "remote",
    "book",
)
SPECIALIST_CLASSES = (
    "wrist_device",
    "earbud",
    "tablet",
    "paper_note",
    "calculator",
)
FINAL_DECISIONS = ("canonical", "no_object", "exclude_candidate", "unresolved")
VALID_SPLITS = ("train", "validation", "test")


@dataclass(frozen=True)
class ResolutionIssue:
    code: str
    message: str
    path: str

    def as_dict(self) -> dict[str, str]:
        return {"code": self.code, "message": self.message, "path": self.path}


def _text(value: Any) -> str:
    return value.strip() if isinstance(value, str) else ""


def _canonical_text(value: Any) -> str:
    return _text(value).lower()


def _allowed_classes(model_role: str) -> tuple[str, ...]:
    if model_role == "base":
        return BASE_CLASSES
    if model_role == "specialist":
        return SPECIALIST_CLASSES
    return ()


def _positive_int(value: Any) -> bool:
    return isinstance(value, int) and not isinstance(value, bool) and value > 0


def _normalize_bbox(value: Any) -> list[float] | None:
    if not isinstance(value, list) or len(value) != 4:
        return None
    result: list[float] = []
    for item in value:
        if isinstance(item, bool) or not isinstance(item, (int, float)):
            return None
        numeric = float(item)
        if not math.isfinite(numeric):
            return None
        result.append(numeric)
    x, y, width, height = result
    epsilon = 1e-9
    if x < 0 or y < 0 or width <= 0 or height <= 0:
        return None
    if x > 1 or y > 1 or x + width > 1 + epsilon or y + height > 1 + epsilon:
        return None
    return result


def _normalize_negative_tags(value: Any) -> list[str] | None:
    if value is None:
        return []
    if not isinstance(value, list):
        return None
    tags: list[str] = []
    seen: set[str] = set()
    for raw in value:
        tag = _canonical_text(raw)
        if not tag:
            return None
        if tag not in seen:
            seen.add(tag)
            tags.append(tag)
    return tags


def build_annotation_staging(
    teacher_report: dict[str, Any],
    human_review: dict[str, Any],
) -> tuple[dict[str, Any] | None, tuple[ResolutionIssue, ...]]:
    """Validate one human review and emit one annotation-ingest staging record.

    The function intentionally refuses partial or unresolved review. It does not
    infer labels, geometry, source groups, split assignment, or reviewer identity.
    """

    issues: list[ResolutionIssue] = []
    if not isinstance(teacher_report, dict):
        return None, (ResolutionIssue("invalid_teacher_report", "teacher report must be an object", "$teacher_report"),)
    if not isinstance(human_review, dict):
        return None, (ResolutionIssue("invalid_human_review", "human review must be an object", "$human_review"),)

    if human_review.get("review_schema_version") != REVIEW_SCHEMA_VERSION:
        issues.append(
            ResolutionIssue(
                "unsupported_review_schema_version",
                f"review_schema_version must be {REVIEW_SCHEMA_VERSION}",
                "$.review_schema_version",
            )
        )

    report_packet_id = _text(teacher_report.get("packet_id"))
    review_packet_id = _text(human_review.get("review_packet_id"))
    if not report_packet_id or review_packet_id != report_packet_id:
        issues.append(
            ResolutionIssue(
                "review_packet_mismatch",
                "review_packet_id must exactly match the teacher report packet_id",
                "$.review_packet_id",
            )
        )

    model_role = _canonical_text(teacher_report.get("model_role"))
    if model_role not in {"base", "specialist"}:
        issues.append(ResolutionIssue("invalid_model_role", "teacher report model_role must be base or specialist", "$teacher_report.model_role"))
    allowed_classes = _allowed_classes(model_role)

    dataset_id = _text(human_review.get("dataset_id"))
    dataset_version = _text(human_review.get("dataset_version"))
    split = _canonical_text(human_review.get("split"))
    source_group_id = _text(human_review.get("source_group_id"))
    if not dataset_id:
        issues.append(ResolutionIssue("missing_dataset_id", "dataset_id is required", "$.dataset_id"))
    if not dataset_version:
        issues.append(ResolutionIssue("missing_dataset_version", "dataset_version is required", "$.dataset_version"))
    if split not in VALID_SPLITS:
        issues.append(ResolutionIssue("invalid_split", "split must be train, validation, or test", "$.split"))
    if not source_group_id:
        issues.append(ResolutionIssue("missing_source_group_id", "source_group_id is required and is never inferred", "$.source_group_id"))

    report_image = teacher_report.get("image")
    review_image = human_review.get("image")
    if not isinstance(report_image, dict) or not isinstance(review_image, dict):
        issues.append(ResolutionIssue("invalid_image", "teacher report and human review must both carry image metadata", "$.image"))
        report_image = {}
        review_image = {}

    report_path = _text(report_image.get("image_path"))
    review_path = _text(review_image.get("image_path"))
    report_width = report_image.get("width")
    report_height = report_image.get("height")
    review_width = review_image.get("width")
    review_height = review_image.get("height")

    if not review_path or review_path != report_path:
        issues.append(ResolutionIssue("image_path_mismatch", "human review image_path must exactly match teacher report", "$.image.image_path"))
    if not _positive_int(review_width) or review_width != report_width:
        issues.append(ResolutionIssue("image_width_mismatch", "human review width must exactly match teacher report", "$.image.width"))
    if not _positive_int(review_height) or review_height != report_height:
        issues.append(ResolutionIssue("image_height_mismatch", "human review height must exactly match teacher report", "$.image.height"))

    negative_tags = _normalize_negative_tags(human_review.get("negative_tags"))
    if negative_tags is None:
        issues.append(ResolutionIssue("invalid_negative_tags", "negative_tags must be an array of non-empty strings", "$.negative_tags"))
        negative_tags = []

    report_candidates = teacher_report.get("candidates")
    review_candidates = human_review.get("candidate_reviews")
    if not isinstance(report_candidates, list):
        issues.append(ResolutionIssue("invalid_teacher_candidates", "teacher report candidates must be an array", "$teacher_report.candidates"))
        report_candidates = []
    if not isinstance(review_candidates, list):
        issues.append(ResolutionIssue("invalid_candidate_reviews", "candidate_reviews must be an array", "$.candidate_reviews"))
        review_candidates = []

    expected_ids = {_text(item.get("candidate_id")) for item in report_candidates if isinstance(item, dict)}
    expected_ids.discard("")
    seen_ids: set[str] = set()
    annotations: list[dict[str, Any]] = []
    unresolved = False

    for index, raw_review in enumerate(review_candidates):
        path = f"$.candidate_reviews[{index}]"
        if not isinstance(raw_review, dict):
            issues.append(ResolutionIssue("invalid_candidate_review", "candidate review must be an object", path))
            continue

        candidate_id = _text(raw_review.get("candidate_id"))
        reviewer_id = _text(raw_review.get("reviewer_id"))
        decision = _canonical_text(raw_review.get("decision"))

        if not candidate_id:
            issues.append(ResolutionIssue("missing_candidate_id", "candidate_id is required", f"{path}.candidate_id"))
        elif candidate_id not in expected_ids:
            issues.append(ResolutionIssue("unknown_candidate_id", "candidate_id does not exist in teacher report", f"{path}.candidate_id"))
        elif candidate_id in seen_ids:
            issues.append(ResolutionIssue("duplicate_candidate_review", "candidate_id may be reviewed only once", f"{path}.candidate_id"))
        else:
            seen_ids.add(candidate_id)

        if not reviewer_id:
            issues.append(ResolutionIssue("missing_reviewer_id", "reviewer_id is required; it is never inferred", f"{path}.reviewer_id"))
        if decision not in FINAL_DECISIONS:
            issues.append(ResolutionIssue("invalid_final_decision", f"decision must be one of {', '.join(FINAL_DECISIONS)}", f"{path}.decision"))
            continue

        canonical_object_id = _canonical_text(raw_review.get("canonical_object_id"))
        bbox_raw = raw_review.get("bbox_xywh_normalized")

        if decision == "canonical":
            if canonical_object_id not in allowed_classes:
                issues.append(
                    ResolutionIssue(
                        "class_not_allowed_for_role",
                        "canonical_object_id must be a canonical class allowed for the teacher report model_role; aliases are not guessed",
                        f"{path}.canonical_object_id",
                    )
                )
            bbox = _normalize_bbox(bbox_raw)
            if bbox is None:
                issues.append(ResolutionIssue("invalid_bbox", "canonical decisions require a valid full-image normalized [x,y,width,height] box", f"{path}.bbox_xywh_normalized"))
            if canonical_object_id in allowed_classes and bbox is not None:
                annotations.append(
                    {
                        "canonical_object_id": canonical_object_id,
                        "bbox_xywh_normalized": bbox,
                    }
                )
        else:
            if canonical_object_id:
                issues.append(ResolutionIssue("unexpected_canonical_object_id", "canonical_object_id is only allowed for canonical decisions", f"{path}.canonical_object_id"))
            if bbox_raw is not None:
                issues.append(ResolutionIssue("unexpected_bbox", "bbox is only allowed for canonical decisions", f"{path}.bbox_xywh_normalized"))
            if decision == "unresolved":
                unresolved = True

    missing_ids = sorted(expected_ids - seen_ids)
    if missing_ids:
        issues.append(
            ResolutionIssue(
                "missing_candidate_reviews",
                "every teacher candidate must receive an explicit human review before annotation staging is emitted: " + ", ".join(missing_ids),
                "$.candidate_reviews",
            )
        )
    if unresolved:
        issues.append(
            ResolutionIssue(
                "unresolved_candidate",
                "at least one candidate remains unresolved; no annotation staging may be emitted",
                "$.candidate_reviews",
            )
        )

    if issues:
        return None, tuple(issues)

    staging = {
        "ingest_schema_version": "1.0",
        "dataset_id": dataset_id,
        "dataset_version": dataset_version,
        "model_role": model_role,
        "split": split,
        "records": [
            {
                "source_group_id": source_group_id,
                "image_path": review_path,
                "width": review_width,
                "height": review_height,
                "negative_tags": negative_tags,
                "annotations": annotations,
            }
        ],
    }
    return staging, ()


def _write_json_atomic(path: Path, value: dict[str, Any], *, pretty: bool) -> None:
    """Write JSON to a unique temp file beside ``path``, then atomically replace it.

    A predictable shared temp name (e.g. ``.name.tmp``) would itself collide if two
    calls raced on the same output path; a unique name avoids that and still leaves
    no partially written file at ``path`` if the process is interrupted mid-write.
    """

    path.parent.mkdir(parents=True, exist_ok=True)
    indent = 2 if pretty else None
    text = json.dumps(value, indent=indent, sort_keys=pretty) + "\n"
    descriptor, temp_name = tempfile.mkstemp(
        prefix=f".{path.name}.", suffix=".tmp", dir=str(path.parent)
    )
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as handle:
            handle.write(text)
        os.replace(temp_name, path)
    except OSError:
        try:
            os.remove(temp_name)
        except OSError:
            pass
        raise


def resolve_files(
    teacher_report_path: Path,
    human_review_path: Path,
    output_path: Path,
    *,
    force: bool = False,
    pretty: bool = False,
) -> dict[str, Any]:
    try:
        resolved_output = output_path.resolve()
        if resolved_output in (teacher_report_path.resolve(), human_review_path.resolve()):
            return {
                "ok": False,
                "issues": [
                    ResolutionIssue(
                        "input_output_same",
                        "output must not be the same file as the teacher report or human review input",
                        str(output_path),
                    ).as_dict()
                ],
            }
    except OSError:
        pass

    if output_path.exists() and not force:
        return {
            "ok": False,
            "issues": [ResolutionIssue("output_exists", "output already exists; use --force to replace it", str(output_path)).as_dict()],
        }
    try:
        teacher_report = json.loads(teacher_report_path.read_text(encoding="utf-8"))
        human_review = json.loads(human_review_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        return {"ok": False, "issues": [ResolutionIssue("input_read_error", str(error), "$input").as_dict()]}

    staging, issues = build_annotation_staging(teacher_report, human_review)
    if issues or staging is None:
        return {"ok": False, "issues": [issue.as_dict() for issue in issues]}

    try:
        _write_json_atomic(output_path, staging, pretty=pretty)
    except OSError as error:
        return {
            "ok": False,
            "issues": [ResolutionIssue("output_write_error", str(error), str(output_path)).as_dict()],
        }
    record = staging["records"][0]
    return {
        "ok": True,
        "output_path": str(output_path),
        "summary": {
            "annotation_count": len(record["annotations"]),
            "negative_tag_count": len(record["negative_tags"]),
            "model_role": staging["model_role"],
            "split": staging["split"],
        },
    }


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Convert an E1 teacher report plus explicit human review into annotation-ingest staging."
    )
    parser.add_argument("teacher_report", type=Path)
    parser.add_argument("human_review", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--force", action="store_true")
    parser.add_argument("--pretty", action="store_true")
    return parser


def main(argv: Sequence[str] | None = None, *, stdout: TextIO = sys.stdout) -> int:
    args = _parser().parse_args(argv)
    result = resolve_files(
        args.teacher_report,
        args.human_review,
        args.output,
        force=args.force,
        pretty=args.pretty,
    )
    stdout.write(json.dumps(result, sort_keys=True) + "\n")
    return 0 if result["ok"] else 1


if __name__ == "__main__":
    raise SystemExit(main())

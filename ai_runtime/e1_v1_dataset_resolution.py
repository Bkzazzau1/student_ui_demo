"""Build V1 E1 dataset staging from strict teacher consensus and non-physical sources.

This module is development-time tooling only. It never calls external models and
is never imported by live exam inference. It consumes an already-produced E1
teacher-consensus report plus explicit source and geometry provenance.

V1 may use synthetic, open-source, or other openly licensed media without a
project-owned physical capture campaign. Teacher-consensus labels are never called
ground truth. Training labels are marked ``silver``. Validation/test labels are
marked ``teacher_consensus_eval`` and may support provisional development metrics,
but not human-grounded final accuracy claims.
"""

from __future__ import annotations

import argparse
from dataclasses import dataclass
import json
import os
from pathlib import Path
import sys
import tempfile
from typing import Any, Mapping, Sequence, TextIO

from .e1_teacher_silver_resolution import (
    MIN_EFFECTIVE_PROVIDERS,
    SilverIssue,
    _allowed_classes,
    _lower,
    _normalize_bbox,
    _normalize_negative_tags,
    _positive_int,
    _strict_teacher_decision,
    _text,
)


V1_DATASET_SCHEMA_VERSION = "1.0"
_ALLOWED_ROLES = frozenset({"base", "specialist"})
_ALLOWED_SPLITS = frozenset({"train", "validation", "test"})
_ALLOWED_SOURCE_KINDS = frozenset(
    {"synthetic", "open_source_dataset", "openly_licensed_media"}
)
_LABEL_QUALITY_BY_SPLIT = {
    "train": "silver",
    "validation": "teacher_consensus_eval",
    "test": "teacher_consensus_eval",
}
_ROUTE_BY_SPLIT = {
    "train": "silver_train",
    "validation": "teacher_consensus_validation",
    "test": "teacher_consensus_test",
}


@dataclass(frozen=True)
class V1Source:
    kind: str
    values: dict[str, str]

    def as_dict(self) -> dict[str, str]:
        return {"kind": self.kind, **self.values}


def _normalize_data_source(value: Any) -> tuple[V1Source | None, list[SilverIssue]]:
    if not isinstance(value, Mapping):
        return None, [
            SilverIssue(
                "invalid_data_source",
                "data_source must be an object describing the original V1 media provenance",
                "$.data_source",
            )
        ]

    kind = _lower(value.get("kind"))
    if kind not in _ALLOWED_SOURCE_KINDS:
        return None, [
            SilverIssue(
                "unsupported_v1_source_kind",
                "V1 accepts only synthetic, open_source_dataset, or openly_licensed_media sources; project physical capture is deferred",
                "$.data_source.kind",
            )
        ]

    source_id = _text(value.get("source_id"))
    if not source_id:
        return None, [
            SilverIssue(
                "missing_source_id",
                "data_source.source_id is required and must remain stable across the dataset workflow",
                "$.data_source.source_id",
            )
        ]

    if kind == "synthetic":
        provider = _lower(value.get("generator_provider"))
        model_id = _text(value.get("generator_model_id"))
        generation_id = _text(value.get("generation_id"))
        issues: list[SilverIssue] = []
        if not provider:
            issues.append(
                SilverIssue(
                    "missing_generator_provider",
                    "synthetic data requires generator_provider",
                    "$.data_source.generator_provider",
                )
            )
        if not model_id:
            issues.append(
                SilverIssue(
                    "missing_generator_model_id",
                    "synthetic data requires the exact generator_model_id",
                    "$.data_source.generator_model_id",
                )
            )
        if not generation_id:
            issues.append(
                SilverIssue(
                    "missing_generation_id",
                    "synthetic data requires generation_id so related generations can be traced",
                    "$.data_source.generation_id",
                )
            )
        if issues:
            return None, issues
        values = {
            "source_id": source_id,
            "generator_provider": provider,
            "generator_model_id": model_id,
            "generation_id": generation_id,
        }
        prompt_id = _text(value.get("prompt_id"))
        if prompt_id:
            values["prompt_id"] = prompt_id
        return V1Source(kind=kind, values=values), []

    source_name = _text(value.get("source_name"))
    source_item_id = _text(value.get("source_item_id"))
    license_text = _text(value.get("license"))
    issues = []
    if not source_name:
        issues.append(
            SilverIssue(
                "missing_source_name",
                "open-source/openly licensed data requires source_name",
                "$.data_source.source_name",
            )
        )
    if not source_item_id:
        issues.append(
            SilverIssue(
                "missing_source_item_id",
                "open-source/openly licensed data requires the original source_item_id",
                "$.data_source.source_item_id",
            )
        )
    if not license_text:
        issues.append(
            SilverIssue(
                "missing_source_license",
                "open-source/openly licensed data requires an explicit recorded license; the tool does not guess licensing rights",
                "$.data_source.license",
            )
        )
    if issues:
        return None, issues

    values = {
        "source_id": source_id,
        "source_name": source_name,
        "source_item_id": source_item_id,
        "license": license_text,
    }
    source_ref = _text(value.get("source_ref"))
    if source_ref:
        values["source_ref"] = source_ref
    return V1Source(kind=kind, values=values), []


def _normalize_geometry_proposals(value: Any) -> tuple[dict[str, dict[str, Any]], list[SilverIssue]]:
    if not isinstance(value, list):
        return {}, [
            SilverIssue(
                "invalid_geometry_proposals",
                "geometry_proposals must be an array",
                "$.geometry_proposals",
            )
        ]

    proposals: dict[str, dict[str, Any]] = {}
    issues: list[SilverIssue] = []
    for index, raw in enumerate(value):
        path = f"$.geometry_proposals[{index}]"
        if not isinstance(raw, Mapping):
            issues.append(
                SilverIssue("invalid_geometry_proposal", "geometry proposal must be an object", path)
            )
            continue
        candidate_id = _text(raw.get("candidate_id"))
        if not candidate_id:
            issues.append(
                SilverIssue("missing_candidate_id", "candidate_id is required", f"{path}.candidate_id")
            )
            continue
        if candidate_id in proposals:
            issues.append(
                SilverIssue(
                    "duplicate_geometry_proposal",
                    "only one geometry proposal is allowed per candidate",
                    f"{path}.candidate_id",
                )
            )
            continue
        bbox = _normalize_bbox(raw.get("bbox_xywh_normalized"))
        if bbox is None:
            issues.append(
                SilverIssue(
                    "invalid_bbox",
                    "geometry proposal requires valid full-image normalized [x,y,width,height]",
                    f"{path}.bbox_xywh_normalized",
                )
            )
            continue
        geometry_source = raw.get("geometry_source")
        if not isinstance(geometry_source, Mapping):
            issues.append(
                SilverIssue(
                    "missing_geometry_source",
                    "geometry_source object is required",
                    f"{path}.geometry_source",
                )
            )
            continue
        provider = _lower(geometry_source.get("provider"))
        model_id = _text(geometry_source.get("model_id"))
        proposal_id = _text(geometry_source.get("proposal_id"))
        if not provider or not model_id or not proposal_id:
            issues.append(
                SilverIssue(
                    "incomplete_geometry_provenance",
                    "geometry_source requires provider, exact model_id, and proposal_id",
                    f"{path}.geometry_source",
                )
            )
            continue
        proposals[candidate_id] = {
            "bbox_xywh_normalized": bbox,
            "geometry_source": {
                "provider": provider,
                "model_id": model_id,
                "proposal_id": proposal_id,
            },
        }
    return proposals, issues


def build_v1_annotation_staging(
    teacher_report: Mapping[str, Any],
    request: Mapping[str, Any],
) -> tuple[dict[str, Any] | None, tuple[SilverIssue, ...]]:
    """Build ingest-compatible V1 staging from non-physical source media.

    The same strict independent-provider consensus rule is used across train,
    validation, and test. The split changes the evidence tier, not the truth rule:
    train is ``silver`` while validation/test are ``teacher_consensus_eval``.
    """

    issues: list[SilverIssue] = []
    if not isinstance(teacher_report, Mapping):
        return None, (
            SilverIssue("invalid_teacher_report", "teacher report must be an object", "$teacher_report"),
        )
    if not isinstance(request, Mapping):
        return None, (
            SilverIssue("invalid_v1_request", "V1 dataset request must be an object", "$request"),
        )

    if request.get("v1_dataset_schema_version") != V1_DATASET_SCHEMA_VERSION:
        issues.append(
            SilverIssue(
                "unsupported_v1_dataset_schema_version",
                f"v1_dataset_schema_version must be {V1_DATASET_SCHEMA_VERSION}",
                "$.v1_dataset_schema_version",
            )
        )

    packet_id = _text(teacher_report.get("packet_id"))
    if not packet_id or _text(request.get("review_packet_id")) != packet_id:
        issues.append(
            SilverIssue(
                "review_packet_mismatch",
                "review_packet_id must exactly match teacher report packet_id",
                "$.review_packet_id",
            )
        )

    role = _lower(teacher_report.get("model_role"))
    if role not in _ALLOWED_ROLES:
        issues.append(
            SilverIssue(
                "invalid_model_role",
                "teacher report model_role must be base or specialist",
                "$teacher_report.model_role",
            )
        )
    allowed_classes = _allowed_classes(role)

    dataset_id = _text(request.get("dataset_id"))
    dataset_version = _text(request.get("dataset_version"))
    split = _lower(request.get("split"))
    source_group_id = _text(request.get("source_group_id"))
    if not dataset_id:
        issues.append(SilverIssue("missing_dataset_id", "dataset_id is required", "$.dataset_id"))
    if not dataset_version:
        issues.append(
            SilverIssue("missing_dataset_version", "dataset_version is required", "$.dataset_version")
        )
    if split not in _ALLOWED_SPLITS:
        issues.append(
            SilverIssue(
                "invalid_split",
                "split must be train, validation, or test",
                "$.split",
            )
        )
    if not source_group_id:
        issues.append(
            SilverIssue(
                "missing_source_group_id",
                "source_group_id is required and is never inferred",
                "$.source_group_id",
            )
        )

    data_source, source_issues = _normalize_data_source(request.get("data_source"))
    issues.extend(source_issues)

    report_image = teacher_report.get("image")
    request_image = request.get("image")
    if not isinstance(report_image, Mapping) or not isinstance(request_image, Mapping):
        issues.append(
            SilverIssue(
                "invalid_image",
                "teacher report and V1 request must both carry image metadata",
                "$.image",
            )
        )
        report_image = {}
        request_image = {}

    report_path = _text(report_image.get("image_path"))
    request_path = _text(request_image.get("image_path"))
    report_width = report_image.get("width")
    report_height = report_image.get("height")
    request_width = request_image.get("width")
    request_height = request_image.get("height")
    if not request_path or request_path != report_path:
        issues.append(
            SilverIssue(
                "image_path_mismatch",
                "V1 request image_path must exactly match teacher report",
                "$.image.image_path",
            )
        )
    if not _positive_int(request_width) or request_width != report_width:
        issues.append(
            SilverIssue(
                "image_width_mismatch",
                "V1 request width must exactly match teacher report",
                "$.image.width",
            )
        )
    if not _positive_int(request_height) or request_height != report_height:
        issues.append(
            SilverIssue(
                "image_height_mismatch",
                "V1 request height must exactly match teacher report",
                "$.image.height",
            )
        )

    negative_tags = _normalize_negative_tags(request.get("negative_tags"))
    if negative_tags is None:
        issues.append(
            SilverIssue(
                "invalid_negative_tags",
                "negative_tags must be an array of non-empty strings",
                "$.negative_tags",
            )
        )
        negative_tags = []

    geometry_by_candidate, geometry_issues = _normalize_geometry_proposals(
        request.get("geometry_proposals", [])
    )
    issues.extend(geometry_issues)

    candidates = teacher_report.get("candidates")
    if not isinstance(candidates, list) or not candidates:
        issues.append(
            SilverIssue(
                "missing_candidates",
                "teacher report must contain at least one candidate",
                "$teacher_report.candidates",
            )
        )
        candidates = []

    if issues:
        return None, tuple(issues)

    annotations: list[dict[str, Any]] = []
    accepted_audit: list[dict[str, Any]] = []
    expected_candidate_ids: set[str] = set()

    for index, raw_candidate in enumerate(candidates):
        path = f"$teacher_report.candidates[{index}]"
        if not isinstance(raw_candidate, Mapping):
            issues.append(SilverIssue("invalid_candidate", "candidate must be an object", path))
            continue
        candidate_id = _text(raw_candidate.get("candidate_id"))
        if not candidate_id:
            issues.append(
                SilverIssue("missing_candidate_id", "candidate_id is required", f"{path}.candidate_id")
            )
            continue
        if candidate_id in expected_candidate_ids:
            issues.append(
                SilverIssue(
                    "duplicate_candidate_id",
                    "candidate_id must be unique",
                    f"{path}.candidate_id",
                )
            )
            continue
        expected_candidate_ids.add(candidate_id)

        decision, candidate_issues = _strict_teacher_decision(
            raw_candidate,
            allowed_classes=allowed_classes,
            path=path,
        )
        if candidate_issues or decision is None:
            issues.extend(candidate_issues)
            continue

        audit_item: dict[str, Any] = {
            "candidate_id": candidate_id,
            "decision": decision["decision"],
            "effective_provider_count": decision["effective_provider_count"],
            "teachers": decision["teachers"],
        }
        if decision["decision"] == "canonical":
            proposal = geometry_by_candidate.get(candidate_id)
            if proposal is None:
                issues.append(
                    SilverIssue(
                        "missing_geometry_proposal",
                        "every canonical V1 candidate requires one explicit geometry proposal; teacher boxes are not fused or auto-selected",
                        f"$.geometry_proposals[{candidate_id}]",
                    )
                )
                continue
            canonical_id = decision["canonical_object_id"]
            annotations.append(
                {
                    "canonical_object_id": canonical_id,
                    "bbox_xywh_normalized": proposal["bbox_xywh_normalized"],
                }
            )
            audit_item["canonical_object_id"] = canonical_id
            audit_item["geometry_source"] = proposal["geometry_source"]
        accepted_audit.append(audit_item)

    extra_geometry_ids = sorted(set(geometry_by_candidate) - expected_candidate_ids)
    if extra_geometry_ids:
        issues.append(
            SilverIssue(
                "unknown_geometry_candidate",
                "geometry proposals reference candidates absent from the teacher report: "
                + ", ".join(extra_geometry_ids),
                "$.geometry_proposals",
            )
        )

    if not annotations and not negative_tags and not issues:
        issues.append(
            SilverIssue(
                "empty_v1_record_without_negative_tags",
                "a V1 record with no canonical annotations must carry explicit negative_tags; candidate no-object votes do not invent whole-image negative meaning",
                "$.negative_tags",
            )
        )

    if issues:
        return None, tuple(issues)

    assert data_source is not None
    label_quality = _LABEL_QUALITY_BY_SPLIT[split]
    evaluation_is_human_ground_truth = False
    staging = {
        "ingest_schema_version": "1.0",
        "dataset_id": dataset_id,
        "dataset_version": dataset_version,
        "model_role": role,
        "split": split,
        "records": [
            {
                "source_group_id": source_group_id,
                "image_path": request_path,
                "width": request_width,
                "height": request_height,
                "negative_tags": negative_tags,
                "annotations": annotations,
            }
        ],
        "v1_audit": {
            "v1_dataset_schema_version": V1_DATASET_SCHEMA_VERSION,
            "label_quality": label_quality,
            "human_verified": False,
            "teacher_packet_id": packet_id,
            "minimum_effective_provider_count": MIN_EFFECTIVE_PROVIDERS,
            "teacher_consensus_is_ground_truth": False,
            "evaluation_is_human_ground_truth": evaluation_is_human_ground_truth,
            "final_human_grounded_accuracy_claim_allowed": False,
            "teacher_models_are_development_only": True,
            "live_exam_external_ai_allowed": False,
            "physical_collection_required_for_v1": False,
            "data_source": data_source.as_dict(),
            "geometry_policy": "explicit_candidate_proposal_no_teacher_box_fusion",
            "accepted_candidates": accepted_audit,
        },
    }
    return staging, ()


def _write_json_atomic(path: Path, value: dict[str, Any], *, pretty: bool) -> None:
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


def resolve_v1_files(
    teacher_report_path: Path,
    request_path: Path,
    output_path: Path,
    *,
    force: bool = False,
    pretty: bool = False,
) -> dict[str, Any]:
    try:
        resolved_output = output_path.resolve()
        if resolved_output in (teacher_report_path.resolve(), request_path.resolve()):
            return {
                "ok": False,
                "route": "quarantine",
                "issues": [
                    SilverIssue(
                        "input_output_same",
                        "output must not overwrite either V1 dataset input",
                        str(output_path),
                    ).as_dict()
                ],
            }
    except OSError:
        pass

    if output_path.exists() and not force:
        return {
            "ok": False,
            "route": "quarantine",
            "issues": [
                SilverIssue(
                    "output_exists",
                    "output already exists; use --force to replace it",
                    str(output_path),
                ).as_dict()
            ],
        }

    try:
        teacher_report = json.loads(teacher_report_path.read_text(encoding="utf-8"))
        request = json.loads(request_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        return {
            "ok": False,
            "route": "quarantine",
            "issues": [SilverIssue("input_read_error", str(error), "$input").as_dict()],
        }

    staging, issues = build_v1_annotation_staging(teacher_report, request)
    if issues or staging is None:
        return {
            "ok": False,
            "route": "quarantine",
            "issues": [issue.as_dict() for issue in issues],
        }

    try:
        _write_json_atomic(output_path, staging, pretty=pretty)
    except OSError as error:
        return {
            "ok": False,
            "route": "quarantine",
            "issues": [
                SilverIssue("output_write_error", str(error), str(output_path)).as_dict()
            ],
        }

    record = staging["records"][0]
    split = staging["split"]
    return {
        "ok": True,
        "route": _ROUTE_BY_SPLIT[split],
        "output_path": str(output_path),
        "summary": {
            "annotation_count": len(record["annotations"]),
            "negative_tag_count": len(record["negative_tags"]),
            "model_role": staging["model_role"],
            "split": split,
            "label_quality": staging["v1_audit"]["label_quality"],
            "human_verified": False,
        },
    }


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description=(
            "Build E1 V1 staging from synthetic/open-source/openly licensed media "
            "using strict independent teacher consensus."
        )
    )
    parser.add_argument("teacher_report", type=Path)
    parser.add_argument("v1_request", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--force", action="store_true")
    parser.add_argument("--pretty", action="store_true")
    return parser


def main(argv: Sequence[str] | None = None, *, stdout: TextIO = sys.stdout) -> int:
    args = _parser().parse_args(argv)
    result = resolve_v1_files(
        args.teacher_report,
        args.v1_request,
        args.output,
        force=args.force,
        pretty=args.pretty,
    )
    stdout.write(json.dumps(result, sort_keys=True) + "\n")
    return 0 if result["ok"] else 1


if __name__ == "__main__":
    raise SystemExit(main())

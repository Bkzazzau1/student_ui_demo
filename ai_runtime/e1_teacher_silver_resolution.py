"""Build V1 E1 silver-label training staging from strict teacher consensus.

This module is development-time tooling only. It never calls external models and
is never imported by live exam inference. It consumes an already-produced E1
teacher consensus report plus an explicit geometry-proposal request.

Silver labels are not ground truth. They are allowed only in the training split.
Validation/test data remains outside this path so it can be human-verified/gold.
UNKNOWN, disagreement, insufficient independent-provider review, missing geometry,
or inconsistent provenance fail closed and route the image back to review/quarantine.
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
from typing import Any, Mapping, Sequence, TextIO


SILVER_SCHEMA_VERSION = "1.0"
MIN_EFFECTIVE_PROVIDERS = 3
_ALLOWED_SPLIT = "train"
_ALLOWED_ROLES = frozenset({"base", "specialist"})
BASE_CLASSES = frozenset(
    {"person", "phone", "laptop", "television", "keyboard", "mouse", "remote", "book"}
)
SPECIALIST_CLASSES = frozenset(
    {"wrist_device", "earbud", "tablet", "paper_note", "calculator"}
)


@dataclass(frozen=True)
class SilverIssue:
    code: str
    message: str
    path: str

    def as_dict(self) -> dict[str, str]:
        return {"code": self.code, "message": self.message, "path": self.path}


def _text(value: Any) -> str:
    return value.strip() if isinstance(value, str) else ""


def _lower(value: Any) -> str:
    return _text(value).lower()


def _positive_int(value: Any) -> bool:
    return isinstance(value, int) and not isinstance(value, bool) and value > 0


def _allowed_classes(role: str) -> frozenset[str]:
    if role == "base":
        return BASE_CLASSES
    if role == "specialist":
        return SPECIALIST_CLASSES
    return frozenset()


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
    result: list[str] = []
    seen: set[str] = set()
    for raw in value:
        tag = _lower(raw)
        if not tag:
            return None
        if tag not in seen:
            seen.add(tag)
            result.append(tag)
    return result


def _decision_key(vote: Mapping[str, Any]) -> str:
    decision = _lower(vote.get("decision"))
    if decision == "canonical":
        return f"canonical:{_lower(vote.get('canonical_object_id'))}"
    return decision


def _strict_teacher_decision(
    candidate: Mapping[str, Any],
    *,
    allowed_classes: frozenset[str],
    path: str,
) -> tuple[dict[str, Any] | None, list[SilverIssue]]:
    issues: list[SilverIssue] = []
    votes = candidate.get("teacher_votes")
    if not isinstance(votes, list) or not votes:
        return None, [
            SilverIssue(
                "missing_teacher_votes",
                "silver bootstrap requires the normalized teacher votes from the consensus report",
                f"{path}.teacher_votes",
            )
        ]

    effective_votes: list[Mapping[str, Any]] = []
    effective_keys: list[str] = []
    has_unknown = False
    provider_models: set[tuple[str, str]] = set()
    effective_providers: set[str] = set()

    for vote_index, raw_vote in enumerate(votes):
        vote_path = f"{path}.teacher_votes[{vote_index}]"
        if not isinstance(raw_vote, Mapping):
            issues.append(SilverIssue("invalid_teacher_vote", "teacher vote must be an object", vote_path))
            continue
        provider = _lower(raw_vote.get("provider"))
        model_id = _text(raw_vote.get("model_id"))
        decision = _lower(raw_vote.get("decision"))
        if not provider:
            issues.append(SilverIssue("missing_provider", "teacher provider is required", f"{vote_path}.provider"))
        if not model_id:
            issues.append(SilverIssue("missing_model_id", "exact teacher model_id is required", f"{vote_path}.model_id"))
        if decision == "unknown":
            has_unknown = True
        if decision in {"canonical", "no_object"}:
            key = _decision_key(raw_vote)
            if decision == "canonical":
                canonical_id = _lower(raw_vote.get("canonical_object_id"))
                if canonical_id not in allowed_classes:
                    issues.append(
                        SilverIssue(
                            "class_not_allowed_for_role",
                            "teacher canonical_object_id must already be an exact canonical class for this model role",
                            f"{vote_path}.canonical_object_id",
                        )
                    )
            effective_votes.append(raw_vote)
            effective_keys.append(key)
            if provider:
                effective_providers.add(provider)
            if provider and model_id:
                provider_models.add((provider, model_id))
        elif decision not in {"abstain", "unknown"}:
            issues.append(
                SilverIssue(
                    "invalid_teacher_decision",
                    "teacher decision must be canonical, no_object, unknown, or abstain",
                    f"{vote_path}.decision",
                )
            )

    if issues:
        return None, issues
    if has_unknown:
        return None, [
            SilverIssue(
                "silver_unknown_present",
                "UNKNOWN is preserved; a candidate with any UNKNOWN vote is not eligible for silver training",
                path,
            )
        ]
    if len(effective_providers) < MIN_EFFECTIVE_PROVIDERS:
        return None, [
            SilverIssue(
                "silver_insufficient_effective_providers",
                f"silver training requires at least {MIN_EFFECTIVE_PROVIDERS} distinct effective teacher providers",
                path,
            )
        ]
    if not effective_keys or len(set(effective_keys)) != 1:
        return None, [
            SilverIssue(
                "silver_teacher_disagreement",
                "all effective teacher providers must agree exactly; disagreement is quarantined",
                path,
            )
        ]

    agreed_key = effective_keys[0]
    agreed: dict[str, Any]
    if agreed_key.startswith("canonical:"):
        canonical_id = agreed_key.split(":", 1)[1]
        if canonical_id not in allowed_classes:
            return None, [
                SilverIssue(
                    "class_not_allowed_for_role",
                    "agreed class is not trainable for this model role",
                    path,
                )
            ]
        agreed = {"decision": "canonical", "canonical_object_id": canonical_id}
    elif agreed_key == "no_object":
        agreed = {"decision": "no_object"}
    else:
        return None, [SilverIssue("silver_invalid_agreement", "effective agreement is invalid", path)]

    if _lower(candidate.get("status")) != "teacher_agreement":
        return None, [
            SilverIssue(
                "teacher_report_status_mismatch",
                "candidate must already be teacher_agreement in the consensus report",
                f"{path}.status",
            )
        ]

    reported_effective_count = candidate.get("teacher_effective_provider_count")
    if reported_effective_count is not None and reported_effective_count != len(effective_providers):
        return None, [
            SilverIssue(
                "teacher_report_count_mismatch",
                "teacher_effective_provider_count does not match the effective providers in teacher_votes",
                f"{path}.teacher_effective_provider_count",
            )
        ]

    suggested = candidate.get("suggested_decision")
    if suggested != agreed:
        return None, [
            SilverIssue(
                "teacher_report_suggestion_mismatch",
                "suggested_decision does not match the recomputed strict teacher agreement",
                f"{path}.suggested_decision",
            )
        ]

    agreed["effective_provider_count"] = len(effective_providers)
    agreed["teachers"] = [
        {"provider": provider, "model_id": model_id}
        for provider, model_id in sorted(provider_models)
    ]
    return agreed, []


def build_silver_annotation_staging(
    teacher_report: Mapping[str, Any],
    silver_request: Mapping[str, Any],
) -> tuple[dict[str, Any] | None, tuple[SilverIssue, ...]]:
    """Emit training-only silver staging when every candidate passes strict review.

    No teacher geometry is fused or selected. Canonical candidates require one
    explicit candidate geometry proposal with exact proposer provenance.
    """

    issues: list[SilverIssue] = []
    if not isinstance(teacher_report, Mapping):
        return None, (SilverIssue("invalid_teacher_report", "teacher report must be an object", "$teacher_report"),)
    if not isinstance(silver_request, Mapping):
        return None, (SilverIssue("invalid_silver_request", "silver request must be an object", "$silver_request"),)

    if silver_request.get("silver_schema_version") != SILVER_SCHEMA_VERSION:
        issues.append(
            SilverIssue(
                "unsupported_silver_schema_version",
                f"silver_schema_version must be {SILVER_SCHEMA_VERSION}",
                "$.silver_schema_version",
            )
        )

    packet_id = _text(teacher_report.get("packet_id"))
    if not packet_id or _text(silver_request.get("review_packet_id")) != packet_id:
        issues.append(
            SilverIssue(
                "review_packet_mismatch",
                "review_packet_id must exactly match teacher report packet_id",
                "$.review_packet_id",
            )
        )

    role = _lower(teacher_report.get("model_role"))
    if role not in _ALLOWED_ROLES:
        issues.append(SilverIssue("invalid_model_role", "teacher report model_role must be base or specialist", "$teacher_report.model_role"))
    allowed_classes = _allowed_classes(role)

    dataset_id = _text(silver_request.get("dataset_id"))
    dataset_version = _text(silver_request.get("dataset_version"))
    split = _lower(silver_request.get("split"))
    source_group_id = _text(silver_request.get("source_group_id"))
    if not dataset_id:
        issues.append(SilverIssue("missing_dataset_id", "dataset_id is required", "$.dataset_id"))
    if not dataset_version:
        issues.append(SilverIssue("missing_dataset_version", "dataset_version is required", "$.dataset_version"))
    if split != _ALLOWED_SPLIT:
        issues.append(
            SilverIssue(
                "silver_train_only",
                "AI-only silver labels may be emitted only for the train split; validation/test must remain gold/human-verified",
                "$.split",
            )
        )
    if not source_group_id:
        issues.append(SilverIssue("missing_source_group_id", "source_group_id is required and is never inferred", "$.source_group_id"))

    report_image = teacher_report.get("image")
    request_image = silver_request.get("image")
    if not isinstance(report_image, Mapping) or not isinstance(request_image, Mapping):
        issues.append(SilverIssue("invalid_image", "teacher report and silver request must both carry image metadata", "$.image"))
        report_image = {}
        request_image = {}
    report_path = _text(report_image.get("image_path"))
    request_path = _text(request_image.get("image_path"))
    report_width = report_image.get("width")
    report_height = report_image.get("height")
    request_width = request_image.get("width")
    request_height = request_image.get("height")
    if not request_path or request_path != report_path:
        issues.append(SilverIssue("image_path_mismatch", "silver request image_path must exactly match teacher report", "$.image.image_path"))
    if not _positive_int(request_width) or request_width != report_width:
        issues.append(SilverIssue("image_width_mismatch", "silver request width must exactly match teacher report", "$.image.width"))
    if not _positive_int(request_height) or request_height != report_height:
        issues.append(SilverIssue("image_height_mismatch", "silver request height must exactly match teacher report", "$.image.height"))

    negative_tags = _normalize_negative_tags(silver_request.get("negative_tags"))
    if negative_tags is None:
        issues.append(SilverIssue("invalid_negative_tags", "negative_tags must be an array of non-empty strings", "$.negative_tags"))
        negative_tags = []

    geometry_raw = silver_request.get("geometry_proposals", [])
    if not isinstance(geometry_raw, list):
        issues.append(SilverIssue("invalid_geometry_proposals", "geometry_proposals must be an array", "$.geometry_proposals"))
        geometry_raw = []
    geometry_by_candidate: dict[str, dict[str, Any]] = {}
    for index, raw_proposal in enumerate(geometry_raw):
        proposal_path = f"$.geometry_proposals[{index}]"
        if not isinstance(raw_proposal, Mapping):
            issues.append(SilverIssue("invalid_geometry_proposal", "geometry proposal must be an object", proposal_path))
            continue
        candidate_id = _text(raw_proposal.get("candidate_id"))
        if not candidate_id:
            issues.append(SilverIssue("missing_candidate_id", "candidate_id is required", f"{proposal_path}.candidate_id"))
            continue
        if candidate_id in geometry_by_candidate:
            issues.append(SilverIssue("duplicate_geometry_proposal", "only one geometry proposal is allowed per candidate", f"{proposal_path}.candidate_id"))
            continue
        bbox = _normalize_bbox(raw_proposal.get("bbox_xywh_normalized"))
        if bbox is None:
            issues.append(SilverIssue("invalid_bbox", "geometry proposal requires valid full-image normalized [x,y,width,height]", f"{proposal_path}.bbox_xywh_normalized"))
            continue
        geometry_source = raw_proposal.get("geometry_source")
        if not isinstance(geometry_source, Mapping):
            issues.append(SilverIssue("missing_geometry_source", "geometry_source object is required", f"{proposal_path}.geometry_source"))
            continue
        provider = _lower(geometry_source.get("provider"))
        model_id = _text(geometry_source.get("model_id"))
        proposal_id = _text(geometry_source.get("proposal_id"))
        if not provider or not model_id or not proposal_id:
            issues.append(
                SilverIssue(
                    "incomplete_geometry_provenance",
                    "geometry_source requires provider, exact model_id, and proposal_id",
                    f"{proposal_path}.geometry_source",
                )
            )
            continue
        geometry_by_candidate[candidate_id] = {
            "bbox_xywh_normalized": bbox,
            "geometry_source": {
                "provider": provider,
                "model_id": model_id,
                "proposal_id": proposal_id,
            },
        }

    candidates = teacher_report.get("candidates")
    if not isinstance(candidates, list) or not candidates:
        issues.append(SilverIssue("missing_candidates", "teacher report must contain at least one candidate", "$teacher_report.candidates"))
        candidates = []

    if issues:
        return None, tuple(issues)

    annotations: list[dict[str, Any]] = []
    accepted_audit: list[dict[str, Any]] = []
    expected_candidate_ids: set[str] = set()

    for index, raw_candidate in enumerate(candidates):
        candidate_path = f"$teacher_report.candidates[{index}]"
        if not isinstance(raw_candidate, Mapping):
            issues.append(SilverIssue("invalid_candidate", "candidate must be an object", candidate_path))
            continue
        candidate_id = _text(raw_candidate.get("candidate_id"))
        if not candidate_id:
            issues.append(SilverIssue("missing_candidate_id", "candidate_id is required", f"{candidate_path}.candidate_id"))
            continue
        if candidate_id in expected_candidate_ids:
            issues.append(SilverIssue("duplicate_candidate_id", "candidate_id must be unique", f"{candidate_path}.candidate_id"))
            continue
        expected_candidate_ids.add(candidate_id)

        decision, candidate_issues = _strict_teacher_decision(
            raw_candidate,
            allowed_classes=allowed_classes,
            path=candidate_path,
        )
        if candidate_issues or decision is None:
            issues.extend(candidate_issues)
            continue

        audit_item = {
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
                        "every canonical silver candidate requires one explicit geometry proposal; teacher boxes are not fused or auto-selected",
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
                "geometry proposals reference candidates absent from the teacher report: " + ", ".join(extra_geometry_ids),
                "$.geometry_proposals",
            )
        )

    if not annotations and not negative_tags and not issues:
        issues.append(
            SilverIssue(
                "empty_silver_record_without_negative_tags",
                "a silver record with no canonical annotations must carry explicit negative_tags; no-object votes alone do not invent an image-level negative meaning",
                "$.negative_tags",
            )
        )

    if issues:
        return None, tuple(issues)

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
        "silver_audit": {
            "silver_schema_version": SILVER_SCHEMA_VERSION,
            "label_quality": "silver",
            "human_verified": False,
            "teacher_packet_id": packet_id,
            "minimum_effective_provider_count": MIN_EFFECTIVE_PROVIDERS,
            "teacher_consensus_is_ground_truth": False,
            "teacher_models_are_development_only": True,
            "live_exam_external_ai_allowed": False,
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


def resolve_silver_files(
    teacher_report_path: Path,
    silver_request_path: Path,
    output_path: Path,
    *,
    force: bool = False,
    pretty: bool = False,
) -> dict[str, Any]:
    try:
        resolved_output = output_path.resolve()
        if resolved_output in (teacher_report_path.resolve(), silver_request_path.resolve()):
            return {
                "ok": False,
                "route": "quarantine",
                "issues": [
                    SilverIssue(
                        "input_output_same",
                        "output must not overwrite either silver-bootstrap input",
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
            "issues": [SilverIssue("output_exists", "output already exists; use --force to replace it", str(output_path)).as_dict()],
        }
    try:
        teacher_report = json.loads(teacher_report_path.read_text(encoding="utf-8"))
        silver_request = json.loads(silver_request_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        return {
            "ok": False,
            "route": "quarantine",
            "issues": [SilverIssue("input_read_error", str(error), "$input").as_dict()],
        }

    staging, issues = build_silver_annotation_staging(teacher_report, silver_request)
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
            "issues": [SilverIssue("output_write_error", str(error), str(output_path)).as_dict()],
        }

    record = staging["records"][0]
    return {
        "ok": True,
        "route": "silver_train",
        "output_path": str(output_path),
        "summary": {
            "annotation_count": len(record["annotations"]),
            "negative_tag_count": len(record["negative_tags"]),
            "model_role": staging["model_role"],
            "label_quality": "silver",
        },
    }


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Build training-only E1 silver annotations from strict independent teacher consensus."
    )
    parser.add_argument("teacher_report", type=Path)
    parser.add_argument("silver_request", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--force", action="store_true")
    parser.add_argument("--pretty", action="store_true")
    return parser


def main(argv: Sequence[str] | None = None, *, stdout: TextIO = sys.stdout) -> int:
    args = _parser().parse_args(argv)
    result = resolve_silver_files(
        args.teacher_report,
        args.silver_request,
        args.output,
        force=args.force,
        pretty=args.pretty,
    )
    stdout.write(json.dumps(result, sort_keys=True) + "\n")
    return 0 if result["ok"] else 1


if __name__ == "__main__":
    raise SystemExit(main())

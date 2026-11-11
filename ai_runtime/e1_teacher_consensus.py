"""Development-time E1 teacher-model review and consensus evaluator.

This module is intentionally offline/development-only. It never calls an external
model and it is not part of live exam inference. Instead, it validates already
collected teacher responses from systems such as ChatGPT, Claude, Gemini, or
other development-time teacher models, preserves disagreement/UNKNOWN, and
produces a human-review report.

Teacher agreement is a review aid, never ground truth. Human approval remains
required before an annotation may enter the canonical E1 dataset ingest path.
"""

from __future__ import annotations

import argparse
from collections import Counter
from dataclasses import dataclass
import json
import math
import os
from pathlib import Path
import sys
import tempfile
from typing import Any, Iterable, Sequence, TextIO


TEACHER_SCHEMA_VERSION = "1.0"
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
VALID_DECISIONS = ("canonical", "no_object", "unknown", "abstain")


@dataclass(frozen=True)
class ReviewIssue:
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


def _valid_positive_int(value: Any) -> bool:
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


def _decision_key(vote: dict[str, Any]) -> str:
    decision = vote["decision"]
    if decision == "canonical":
        return f"canonical:{vote['canonical_object_id']}"
    return decision


def _evaluate_candidate(candidate: dict[str, Any]) -> dict[str, Any]:
    votes = candidate["teacher_votes"]
    provider_count = len({vote["provider"] for vote in votes})
    keys = [_decision_key(vote) for vote in votes]
    vote_counts = Counter(keys)
    has_unknown = "unknown" in vote_counts
    effective = [key for key in keys if key not in {"abstain", "unknown"}]
    # Agreement requires independent providers among the EFFECTIVE votes, not
    # just among all votes: a provider that abstains still counts toward
    # provider_count, which would otherwise let a single provider's repeated
    # calls (under different teacher_id configs) masquerade as multi-provider
    # consensus while every other provider abstained.
    effective_provider_count = len(
        {vote["provider"] for vote, key in zip(votes, keys) if key not in {"abstain", "unknown"}}
    )

    status: str
    suggested_decision: dict[str, Any] | None = None

    if provider_count < 2:
        status = "insufficient_review"
    elif has_unknown:
        status = "needs_human_review"
    elif not effective:
        status = "unresolved"
    elif effective_provider_count < 2:
        status = "insufficient_review"
    elif len(set(effective)) == 1:
        status = "teacher_agreement"
        agreed = effective[0]
        if agreed.startswith("canonical:"):
            suggested_decision = {
                "decision": "canonical",
                "canonical_object_id": agreed.split(":", 1)[1],
            }
        else:
            suggested_decision = {"decision": agreed}
    else:
        status = "needs_human_review"

    normalized_votes = []
    has_canonical_vote = False
    for vote in votes:
        normalized = {
            "teacher_id": vote["teacher_id"],
            "provider": vote["provider"],
            "model_id": vote["model_id"],
            "decision": vote["decision"],
        }
        if vote["decision"] == "canonical":
            has_canonical_vote = True
            normalized["canonical_object_id"] = vote["canonical_object_id"]
        if vote.get("bbox_xywh_normalized") is not None:
            normalized["bbox_xywh_normalized"] = vote["bbox_xywh_normalized"]
        normalized_votes.append(normalized)

    return {
        "candidate_id": candidate["candidate_id"],
        "status": status,
        "teacher_provider_count": provider_count,
        "teacher_effective_provider_count": effective_provider_count,
        "teacher_vote_count": len(votes),
        "vote_counts": dict(sorted(vote_counts.items())),
        "suggested_decision": suggested_decision,
        "human_review_required": True,
        "geometry_resolution": "human_required" if has_canonical_vote else "not_applicable",
        "teacher_votes": normalized_votes,
    }


def evaluate_teacher_packet(
    packet: dict[str, Any],
) -> tuple[dict[str, Any] | None, tuple[ReviewIssue, ...]]:
    """Validate and evaluate one teacher-review packet.

    The returned report never constitutes a training annotation. It deliberately
    excludes any auto-approved label or fused geometry.
    """

    issues: list[ReviewIssue] = []
    if not isinstance(packet, dict):
        return None, (
            ReviewIssue("invalid_packet", "teacher packet must be a JSON object", "$"),
        )

    if packet.get("teacher_schema_version") != TEACHER_SCHEMA_VERSION:
        issues.append(
            ReviewIssue(
                "unsupported_schema_version",
                f"teacher_schema_version must be {TEACHER_SCHEMA_VERSION}",
                "$.teacher_schema_version",
            )
        )

    packet_id = _text(packet.get("packet_id"))
    if not packet_id:
        issues.append(ReviewIssue("missing_packet_id", "packet_id is required", "$.packet_id"))

    model_role = _canonical_text(packet.get("model_role"))
    if model_role not in {"base", "specialist"}:
        issues.append(
            ReviewIssue(
                "invalid_model_role",
                "model_role must be base or specialist",
                "$.model_role",
            )
        )
    allowed_classes = _allowed_classes(model_role)

    image = packet.get("image")
    if not isinstance(image, dict):
        issues.append(ReviewIssue("invalid_image", "image must be an object", "$.image"))
        image_path = ""
        width = 0
        height = 0
    else:
        image_path = _text(image.get("image_path"))
        width = image.get("width")
        height = image.get("height")
        if not image_path:
            issues.append(
                ReviewIssue("missing_image_path", "image_path is required", "$.image.image_path")
            )
        if not _valid_positive_int(width):
            issues.append(
                ReviewIssue("invalid_image_width", "width must be a positive integer", "$.image.width")
            )
        if not _valid_positive_int(height):
            issues.append(
                ReviewIssue("invalid_image_height", "height must be a positive integer", "$.image.height")
            )

    candidates = packet.get("candidates")
    if not isinstance(candidates, list):
        issues.append(
            ReviewIssue("invalid_candidates", "candidates must be an array", "$.candidates")
        )
        candidates = []

    normalized_candidates: list[dict[str, Any]] = []
    seen_candidate_ids: set[str] = set()
    for candidate_index, raw_candidate in enumerate(candidates):
        candidate_path = f"$.candidates[{candidate_index}]"
        if not isinstance(raw_candidate, dict):
            issues.append(
                ReviewIssue("invalid_candidate", "candidate must be an object", candidate_path)
            )
            continue

        candidate_id = _text(raw_candidate.get("candidate_id"))
        if not candidate_id:
            issues.append(
                ReviewIssue("missing_candidate_id", "candidate_id is required", f"{candidate_path}.candidate_id")
            )
        elif candidate_id in seen_candidate_ids:
            issues.append(
                ReviewIssue(
                    "duplicate_candidate_id",
                    f"candidate_id {candidate_id!r} is duplicated",
                    f"{candidate_path}.candidate_id",
                )
            )
        else:
            seen_candidate_ids.add(candidate_id)

        votes = raw_candidate.get("teacher_votes")
        if not isinstance(votes, list) or not votes:
            issues.append(
                ReviewIssue(
                    "missing_teacher_votes",
                    "teacher_votes must contain at least one vote",
                    f"{candidate_path}.teacher_votes",
                )
            )
            continue

        normalized_votes: list[dict[str, Any]] = []
        seen_teacher_ids: set[str] = set()
        for vote_index, raw_vote in enumerate(votes):
            vote_path = f"{candidate_path}.teacher_votes[{vote_index}]"
            if not isinstance(raw_vote, dict):
                issues.append(ReviewIssue("invalid_teacher_vote", "vote must be an object", vote_path))
                continue

            teacher_id = _text(raw_vote.get("teacher_id"))
            provider = _canonical_text(raw_vote.get("provider"))
            model_id = _text(raw_vote.get("model_id"))
            decision = _canonical_text(raw_vote.get("decision"))

            if not teacher_id:
                issues.append(
                    ReviewIssue("missing_teacher_id", "teacher_id is required", f"{vote_path}.teacher_id")
                )
            elif teacher_id in seen_teacher_ids:
                issues.append(
                    ReviewIssue(
                        "duplicate_teacher_id",
                        f"teacher_id {teacher_id!r} is duplicated for this candidate",
                        f"{vote_path}.teacher_id",
                    )
                )
            else:
                seen_teacher_ids.add(teacher_id)
            if not provider:
                issues.append(
                    ReviewIssue("missing_provider", "provider is required", f"{vote_path}.provider")
                )
            if not model_id:
                issues.append(
                    ReviewIssue("missing_model_id", "model_id is required", f"{vote_path}.model_id")
                )
            if decision not in VALID_DECISIONS:
                issues.append(
                    ReviewIssue(
                        "invalid_decision",
                        f"decision must be one of {', '.join(VALID_DECISIONS)}",
                        f"{vote_path}.decision",
                    )
                )

            canonical_object_id = _canonical_text(raw_vote.get("canonical_object_id"))
            if decision == "canonical":
                if canonical_object_id not in allowed_classes:
                    issues.append(
                        ReviewIssue(
                            "class_not_allowed_for_role",
                            "canonical_object_id must already be a canonical class allowed for model_role; aliases are not guessed",
                            f"{vote_path}.canonical_object_id",
                        )
                    )
            elif canonical_object_id:
                issues.append(
                    ReviewIssue(
                        "unexpected_canonical_object_id",
                        "canonical_object_id is only allowed when decision is canonical",
                        f"{vote_path}.canonical_object_id",
                    )
                )

            bbox_value = raw_vote.get("bbox_xywh_normalized")
            normalized_bbox = None
            if bbox_value is not None:
                normalized_bbox = _normalize_bbox(bbox_value)
                if normalized_bbox is None:
                    issues.append(
                        ReviewIssue(
                            "invalid_bbox",
                            "bbox_xywh_normalized must be [x, y, width, height] within the full image",
                            f"{vote_path}.bbox_xywh_normalized",
                        )
                    )
                elif decision != "canonical":
                    issues.append(
                        ReviewIssue(
                            "bbox_without_canonical_decision",
                            "geometry is only allowed for a canonical object decision",
                            f"{vote_path}.bbox_xywh_normalized",
                        )
                    )

            normalized_vote = {
                "teacher_id": teacher_id,
                "provider": provider,
                "model_id": model_id,
                "decision": decision,
            }
            if decision == "canonical":
                normalized_vote["canonical_object_id"] = canonical_object_id
            if normalized_bbox is not None:
                normalized_vote["bbox_xywh_normalized"] = normalized_bbox
            normalized_votes.append(normalized_vote)

        normalized_candidates.append(
            {"candidate_id": candidate_id, "teacher_votes": normalized_votes}
        )

    if issues:
        return None, tuple(issues)

    evaluated_candidates = [_evaluate_candidate(candidate) for candidate in normalized_candidates]
    status_counts = Counter(candidate["status"] for candidate in evaluated_candidates)
    report = {
        "teacher_schema_version": TEACHER_SCHEMA_VERSION,
        "packet_id": packet_id,
        "model_role": model_role,
        "image": {"image_path": image_path, "width": width, "height": height},
        "policy": {
            "live_exam_external_ai_allowed": False,
            "teacher_models_are_development_only": True,
            "teacher_agreement_is_ground_truth": False,
            "human_review_required": True,
            "teacher_confidence_weighting_used": False,
            "teacher_geometry_fusion_used": False,
        },
        "summary": {
            "candidate_count": len(evaluated_candidates),
            "status_counts": dict(sorted(status_counts.items())),
        },
        "candidates": evaluated_candidates,
    }
    return report, ()


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


def review_teacher_file(
    input_path: Path,
    output_path: Path,
    *,
    force: bool = False,
    pretty: bool = False,
) -> dict[str, Any]:
    try:
        if input_path.resolve() == output_path.resolve():
            return {
                "ok": False,
                "issues": [
                    ReviewIssue(
                        "input_output_same",
                        "teacher packet input and human-review report output must be different files",
                        str(output_path),
                    ).as_dict()
                ],
            }
    except OSError:
        pass

    if output_path.exists() and not force:
        return {
            "ok": False,
            "issues": [
                ReviewIssue(
                    "output_exists",
                    "output already exists; use --force to replace it",
                    str(output_path),
                ).as_dict()
            ],
        }
    try:
        packet = json.loads(input_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        return {
            "ok": False,
            "issues": [ReviewIssue("input_read_error", str(error), str(input_path)).as_dict()],
        }

    report, issues = evaluate_teacher_packet(packet)
    if issues or report is None:
        return {"ok": False, "issues": [issue.as_dict() for issue in issues]}

    try:
        _write_json_atomic(output_path, report, pretty=pretty)
    except OSError as error:
        return {
            "ok": False,
            "issues": [ReviewIssue("output_write_error", str(error), str(output_path)).as_dict()],
        }
    return {"ok": True, "summary": report["summary"], "output_path": str(output_path)}


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Evaluate development-time E1 teacher-model votes without creating ground truth."
    )
    parser.add_argument("input", type=Path, help="teacher review packet JSON")
    parser.add_argument("output", type=Path, help="human-review report JSON")
    parser.add_argument("--force", action="store_true", help="replace an existing output")
    parser.add_argument("--pretty", action="store_true", help="pretty-print JSON output")
    return parser


def main(argv: Sequence[str] | None = None, *, stdout: TextIO = sys.stdout) -> int:
    args = _parser().parse_args(argv)
    result = review_teacher_file(
        args.input,
        args.output,
        force=args.force,
        pretty=args.pretty,
    )
    stdout.write(json.dumps(result, sort_keys=True) + "\n")
    return 0 if result["ok"] else 1


if __name__ == "__main__":
    raise SystemExit(main())

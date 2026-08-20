from __future__ import annotations

import json
import secrets
from datetime import timedelta
from pathlib import Path
from typing import Any

from .identity_store import IdentityStore, Principal, iso, utc_now


_FORBIDDEN_KEYS = {
    "bytes", "raw_bytes", "frame_bytes", "image_bytes", "audio_bytes",
    "pcm_bytes", "wav_bytes", "video_bytes", "base64", "image_base64",
    "audio_base64", "video_base64", "raw_frame", "raw_image", "raw_audio",
    "raw_video", "file_path", "directory_path", "absolute_path", "path",
    "image_path", "audio_path", "video_path", "snapshot_path", "recording_path",
}
_EVIDENCE_KEYS = {
    "id", "event_type", "file_type", "sha256", "size_bytes", "created_at",
    "review_reason", "storage",
}


class ProctoringStore:
    def __init__(self, identity_store: IdentityStore) -> None:
        self.identity = identity_store
        self.database_path = identity_store.database_path
        self._initialize()

    def _initialize(self) -> None:
        with self.identity.connect() as db:
            db.executescript(
                """
                CREATE TABLE IF NOT EXISTS proctoring_events (
                    event_id TEXT PRIMARY KEY,
                    student_id TEXT NOT NULL,
                    exam_id TEXT NOT NULL,
                    attempt_id TEXT NOT NULL,
                    event_type TEXT NOT NULL,
                    severity TEXT NOT NULL,
                    message TEXT NOT NULL,
                    occurred_at TEXT NOT NULL,
                    received_at TEXT NOT NULL,
                    assessment_type TEXT NOT NULL,
                    review_audience TEXT NOT NULL,
                    metadata_json TEXT NOT NULL,
                    expires_at TEXT NOT NULL,
                    deleted_at TEXT
                );
                CREATE INDEX IF NOT EXISTS proctoring_attempt_idx
                    ON proctoring_events(student_id, exam_id, attempt_id, occurred_at);
                CREATE TABLE IF NOT EXISTS fusion_decisions (
                    decision_id TEXT PRIMARY KEY,
                    student_id TEXT NOT NULL,
                    exam_id TEXT NOT NULL,
                    attempt_id TEXT NOT NULL,
                    source_event_type TEXT NOT NULL,
                    risk_score INTEGER NOT NULL,
                    risk_level TEXT NOT NULL,
                    disposition TEXT NOT NULL,
                    requires_human_review INTEGER NOT NULL,
                    signal_groups_json TEXT NOT NULL,
                    reasons_json TEXT NOT NULL,
                    model_id TEXT NOT NULL,
                    model_version TEXT NOT NULL,
                    authority TEXT NOT NULL,
                    occurred_at TEXT NOT NULL,
                    expires_at TEXT NOT NULL,
                    deleted_at TEXT
                );
                CREATE INDEX IF NOT EXISTS fusion_attempt_idx
                    ON fusion_decisions(student_id, exam_id, attempt_id, occurred_at);
                """
            )

    def add_event(self, principal: Principal, payload: dict[str, Any]) -> dict[str, Any]:
        student_id = _required(payload, "student_id")
        if not self.identity.authorize_student(principal, student_id):
            raise PermissionError("student identity does not match access token")
        now = utc_now()
        event_id = secrets.token_urlsafe(18)
        metadata = sanitize_metadata(payload.get("metadata", {}))
        values = (
            event_id, student_id, _required(payload, "exam_id"),
            _required(payload, "attempt_id"), _required(payload, "event_type"),
            _required(payload, "severity"), _bounded_text(payload.get("message"), 2000),
            _timestamp(payload.get("created_at")), iso(now),
            _bounded_text(payload.get("assessment_type", "exam"), 80),
            _bounded_text(payload.get("review_audience", "invigilator"), 80),
            json.dumps(metadata, separators=(",", ":")),
            iso(now + timedelta(days=90)),
        )
        with self.identity.connect() as db:
            db.execute(
                "INSERT INTO proctoring_events VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NULL)",
                values,
            )
        self.identity.audit(principal, "proctoring.event.create", student_id, None, "allowed", {"event_id": event_id, "attempt_id": values[3], "event_type": values[4]})
        return {"event_id": event_id, "stored": True, "stores_raw_media": False}

    def add_fusion_decision(self, principal: Principal, payload: dict[str, Any]) -> dict[str, Any]:
        student_id = _required(payload, "student_id")
        if not self.identity.authorize_student(principal, student_id):
            raise PermissionError("student identity does not match access token")
        score = int(payload.get("risk_score", 0))
        if score < 0 or score > 100:
            raise ValueError("risk_score must be between 0 and 100")
        groups = _string_list(payload.get("signal_groups", []), "signal_groups")
        reasons = _string_list(payload.get("reasons", []), "reasons")
        now = utc_now()
        decision_id = secrets.token_urlsafe(18)
        values = (
            decision_id, student_id, _required(payload, "exam_id"),
            _required(payload, "attempt_id"), _required(payload, "source_event_type"),
            score, _required(payload, "risk_level"), _required(payload, "disposition"),
            1 if payload.get("requires_human_review") is True else 0,
            json.dumps(groups, separators=(",", ":")),
            json.dumps(reasons, separators=(",", ":")),
            _bounded_text(payload.get("model_id", "kslas-edge-ai"), 100),
            _bounded_text(payload.get("model_version", "1.0"), 50),
            "rust_authorized_actions_only", _timestamp(payload.get("occurred_at")),
            iso(now + timedelta(days=90)),
        )
        with self.identity.connect() as db:
            db.execute(
                "INSERT INTO fusion_decisions VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NULL)",
                values,
            )
        self.identity.audit(principal, "proctoring.fusion.create", student_id, None, "allowed", {"decision_id": decision_id, "attempt_id": values[3]})
        return {"decision_id": decision_id, "stored": True, "stores_raw_media": False}

    def timeline(self, principal: Principal, student_id: str, exam_id: str, attempt_id: str) -> dict[str, Any]:
        if principal.role not in {"admin", "invigilator"}:
            raise PermissionError("invigilator or administrator role is required")
        with self.identity.connect() as db:
            events = db.execute(
                "SELECT * FROM proctoring_events WHERE student_id=? AND exam_id=? AND attempt_id=? AND deleted_at IS NULL ORDER BY occurred_at",
                (student_id, exam_id, attempt_id),
            ).fetchall()
            decisions = db.execute(
                "SELECT * FROM fusion_decisions WHERE student_id=? AND exam_id=? AND attempt_id=? AND deleted_at IS NULL ORDER BY occurred_at",
                (student_id, exam_id, attempt_id),
            ).fetchall()
        items = [
            {"kind": "observation", "id": row["event_id"], "occurred_at": row["occurred_at"], "event_type": row["event_type"], "severity": row["severity"], "message": row["message"], "metadata": json.loads(row["metadata_json"])}
            for row in events
        ] + [
            {"kind": "fusion_decision", "id": row["decision_id"], "occurred_at": row["occurred_at"], "source_event_type": row["source_event_type"], "risk_score": row["risk_score"], "risk_level": row["risk_level"], "disposition": row["disposition"], "requires_human_review": bool(row["requires_human_review"]), "signal_groups": json.loads(row["signal_groups_json"]), "reasons": json.loads(row["reasons_json"]), "model_id": row["model_id"], "model_version": row["model_version"], "authority": row["authority"]}
            for row in decisions
        ]
        items.sort(key=lambda item: item["occurred_at"])
        self.identity.audit(principal, "proctoring.timeline.read", student_id, None, "allowed", {"attempt_id": attempt_id})
        return {"student_id": student_id, "exam_id": exam_id, "attempt_id": attempt_id, "items": items, "stores_raw_media": False}

    def purge_expired(self, principal: Principal) -> dict[str, int]:
        if principal.role != "admin":
            raise PermissionError("administrator role is required")
        now = iso(utc_now())
        with self.identity.connect() as db:
            events = db.execute("UPDATE proctoring_events SET deleted_at=? WHERE expires_at<=? AND deleted_at IS NULL", (now, now)).rowcount
            decisions = db.execute("UPDATE fusion_decisions SET deleted_at=? WHERE expires_at<=? AND deleted_at IS NULL", (now, now)).rowcount
        self.identity.audit(principal, "proctoring.retention.purge", principal.student_id, None, "allowed", {"events": events, "decisions": decisions})
        return {"events_deleted": events, "decisions_deleted": decisions}


def sanitize_metadata(value: Any, depth: int = 0) -> Any:
    if value is None or isinstance(value, (bool, int, float)):
        return value
    if isinstance(value, str):
        return _bounded_text(value, 2000)
    if depth >= 6:
        return "[nested_metadata_truncated]"
    if isinstance(value, list):
        return [sanitize_metadata(item, depth + 1) for item in value[:50]]
    if not isinstance(value, dict):
        return _bounded_text(str(value), 2000)
    result: dict[str, Any] = {}
    for raw_key, item in list(value.items())[:80]:
        key = str(raw_key)
        normalized = key.strip().lower().replace("-", "_")
        if normalized in _FORBIDDEN_KEYS:
            result[key] = "[stored_locally]"
        elif normalized in {"local_record", "local_audio_record", "local_camera_record"} and isinstance(item, dict):
            result[key] = {str(k): sanitize_metadata(v, depth + 1) for k, v in item.items() if str(k).strip().lower() in _EVIDENCE_KEYS}
            result[key]["storage"] = "local_device_vault"
        else:
            result[key] = sanitize_metadata(item, depth + 1)
    return result


def _required(payload: dict[str, Any], key: str) -> str:
    value = str(payload.get(key, "")).strip()
    if not value:
        raise ValueError(f"{key} is required")
    return _bounded_text(value, 200)


def _bounded_text(value: Any, limit: int) -> str:
    text = str(value or "").strip()
    if len(text) > limit:
        raise ValueError("text field exceeds maximum length")
    return text


def _timestamp(value: Any) -> str:
    text = str(value or "").strip()
    if not text:
        return iso(utc_now())
    return _bounded_text(text, 50)


def _string_list(value: Any, key: str) -> list[str]:
    if not isinstance(value, list) or len(value) > 20:
        raise ValueError(f"{key} must be an array with at most 20 entries")
    return [_bounded_text(item, 300) for item in value]

from __future__ import annotations

from collections import defaultdict, deque
from dataclasses import dataclass
from datetime import datetime, timezone
from typing import Any


EVENT_WEIGHTS = {
    "gaze_head_pose_deviation": 8,
    "sustained_gaze_head_pose_deviation": 22,
    "multiple_people_detected": 35,
    "yolo_phone_detected": 30,
    "yolo_book_or_paper_detected": 18,
    "yolo_calculator_detected": 15,
    "yolo_extra_screen_detected": 30,
    "audio_voice_isolation_alert": 22,
    "exam_screen_backgrounded": 25,
    "continuous_liveness_spoof_risk": 35,
}

CORROBORATING_GROUPS = {
    "attention": {"gaze_head_pose_deviation", "sustained_gaze_head_pose_deviation"},
    "environment": {"multiple_people_detected", "yolo_phone_detected", "yolo_book_or_paper_detected", "yolo_calculator_detected", "yolo_extra_screen_detected"},
    "audio": {"audio_voice_isolation_alert", "background_voice_environment_warning"},
    "device": {"exam_screen_backgrounded", "continuous_liveness_spoof_risk"},
}


@dataclass(frozen=True)
class ReviewResult:
    risk_score: int
    risk_level: str
    disposition: str
    reasons: tuple[str, ...]
    proposed_actions: tuple[str, ...]
    requires_human_review: bool

    def to_dict(self) -> dict[str, Any]:
        return {
            "risk_score": self.risk_score,
            "risk_level": self.risk_level,
            "disposition": self.disposition,
            "reasons": list(self.reasons),
            "proposed_actions": list(self.proposed_actions),
            "requires_human_review": self.requires_human_review,
            "authority": "rust",
        }


class EdgeAiEngine:
    """Bounded, deterministic baseline that can later host local ML models."""

    def __init__(self, max_events_per_attempt: int = 200) -> None:
        if max_events_per_attempt < 1:
            raise ValueError("max_events_per_attempt must be positive")
        self._events: dict[str, deque[dict[str, Any]]] = defaultdict(
            lambda: deque(maxlen=max_events_per_attempt)
        )
        self._gaze: dict[str, deque[dict[str, Any]]] = defaultdict(
            lambda: deque(maxlen=120)
        )

    def observe_gaze(self, observation: dict[str, Any]) -> dict[str, Any]:
        """Track bounded temporal behavior from normalized signals, not media."""
        attempt_id = _required_text(observation, "attempt_id")
        confidence = _confidence(observation.get("confidence", 0.0))
        signal_quality = _confidence(observation.get("signal_quality", confidence))
        calibrated = observation.get("calibrated") is True
        actionable = observation.get("actionable") is True
        deviating = observation.get("deviating") is True
        zone = str(observation.get("zone") or "camera_not_reliable")
        item = {
            "zone": zone,
            "confidence": confidence,
            "signal_quality": signal_quality,
            "calibrated": calibrated,
            "actionable": actionable,
            "deviating": deviating,
            "observed_at": str(observation.get("observed_at") or _utc_now()),
        }
        history = self._gaze[attempt_id]
        history.append(item)
        recent = list(history)[-12:]
        reliable = [entry for entry in recent if entry["calibrated"] and entry["actionable"]]
        deviations = sum(1 for entry in reliable if entry["deviating"])
        if not calibrated or signal_quality < 0.45:
            state = "uncertain"
        elif len(reliable) >= 8 and deviations >= 6:
            state = "needs_review"
        else:
            state = "normal"
        return {
            "state": state,
            "zone": zone,
            "reliable_samples": len(reliable),
            "deviation_samples": deviations,
            "stores_raw_media": False,
            "proposed_actions": [],
        }

    def review_event(self, event: dict[str, Any]) -> ReviewResult:
        attempt_id = _required_text(event, "attempt_id")
        event_type = _required_text(event, "event_type")
        confidence = _confidence(event.get("confidence", 1.0))
        normalized = {
            "event_type": event_type,
            "confidence": confidence,
            "occurred_at": str(event.get("occurred_at") or _utc_now()),
        }
        history = self._events[attempt_id]
        history.append(normalized)

        recent = list(history)[-20:]
        weighted = sum(
            EVENT_WEIGHTS.get(item["event_type"], 0) * item["confidence"]
            for item in recent
        )
        kinds = {item["event_type"] for item in recent}
        active_groups = [name for name, members in CORROBORATING_GROUPS.items() if kinds & members]
        corroboration_bonus = max(0, len(active_groups) - 1) * 8
        score = min(100, round(weighted + corroboration_bonus))
        level = "low" if score < 20 else "medium" if score < 45 else "high" if score < 70 else "critical"

        reasons = [f"{event_type} observed with confidence {confidence:.2f}"]
        if len(active_groups) > 1:
            reasons.append("Corroborating signals: " + ", ".join(active_groups))
        if event_type.startswith("gaze") or event_type.startswith("sustained_gaze"):
            reasons.append("Gaze is contextual evidence and is never treated as proof by itself")

        needs_review = score >= 45 or event_type in {
            "multiple_people_detected", "continuous_liveness_spoof_risk"
        }
        actions: tuple[str, ...] = ("capture_review_snapshot",) if needs_review else ()
        disposition = "human_review" if needs_review else "continue_observation"
        return ReviewResult(score, level, disposition, tuple(reasons), actions, needs_review)

    def clear_attempt(self, attempt_id: str) -> bool:
        removed_events = self._events.pop(attempt_id, None) is not None
        removed_gaze = self._gaze.pop(attempt_id, None) is not None
        return removed_events or removed_gaze

    def event_count(self, attempt_id: str) -> int:
        return len(self._events.get(attempt_id, ()))


def _required_text(value: dict[str, Any], key: str) -> str:
    result = value.get(key)
    if not isinstance(result, str) or not result.strip():
        raise ValueError(f"{key} must be a non-empty string")
    return result.strip()


def _confidence(value: Any) -> float:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise ValueError("confidence must be a number")
    return max(0.0, min(1.0, float(value)))


def _utc_now() -> str:
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")

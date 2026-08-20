from __future__ import annotations

from collections import defaultdict, deque
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from typing import Any


EVENT_WEIGHTS = {
    "gaze_head_pose_deviation": 8,
    "sustained_gaze_head_pose_deviation": 22,
    "multiple_people_detected": 35,
    "camera_view_needs_review": 12,
    "camera_reconnect_timeout": 10,
    "yolo_phone_detected": 30,
    "yolo_book_or_paper_detected": 18,
    "yolo_calculator_detected": 15,
    "yolo_extra_screen_detected": 30,
    "audio_voice_isolation_alert": 22,
    "audio_temporal_behaviour_review": 18,
    "exam_screen_backgrounded": 25,
    "continuous_liveness_spoof_risk": 35,
    "object_reflection_shadow_risk": 18,
    "system_monitoring_unavailable": 20,
    "microphone_reconnect_timeout": 10,
}

CORROBORATING_GROUPS = {
    "attention": {"gaze_head_pose_deviation", "sustained_gaze_head_pose_deviation"},
    "identity_presence": {"multiple_people_detected", "camera_view_needs_review", "camera_reconnect_timeout", "continuous_liveness_spoof_risk"},
    "environment": {"yolo_phone_detected", "yolo_book_or_paper_detected", "yolo_calculator_detected", "yolo_extra_screen_detected", "object_reflection_shadow_risk"},
    "audio": {"audio_voice_isolation_alert", "background_voice_environment_warning", "audio_temporal_behaviour_review"},
    "device": {"exam_screen_backgrounded", "system_monitoring_unavailable", "microphone_reconnect_timeout"},
}


@dataclass(frozen=True)
class ReviewResult:
    risk_score: int
    risk_level: str
    disposition: str
    reasons: tuple[str, ...]
    proposed_actions: tuple[str, ...]
    requires_human_review: bool
    signal_groups: tuple[str, ...] = ()
    window_seconds: int = 120

    def to_dict(self) -> dict[str, Any]:
        return {
            "risk_score": self.risk_score,
            "risk_level": self.risk_level,
            "disposition": self.disposition,
            "reasons": list(self.reasons),
            "proposed_actions": list(self.proposed_actions),
            "requires_human_review": self.requires_human_review,
            "authority": "rust",
            "signal_groups": list(self.signal_groups),
            "window_seconds": self.window_seconds,
            "observable_behaviour_only": True,
            "decision_basis": "correlated_normalized_signals",
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
        self._audio: dict[str, deque[dict[str, Any]]] = defaultdict(
            lambda: deque(maxlen=180)
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
        signal_quality = _confidence(event.get("signal_quality", confidence))
        occurred_at = _parse_timestamp(event.get("occurred_at"))
        normalized = {
            "event_type": event_type,
            "confidence": confidence,
            "signal_quality": signal_quality,
            "occurred_at": occurred_at,
        }
        history = self._events[attempt_id]
        history.append(normalized)

        window_start = occurred_at - timedelta(seconds=120)
        recent = [
            item for item in history
            if item["occurred_at"] >= window_start and item["signal_quality"] >= 0.45
        ]
        strongest_by_type: dict[str, float] = {}
        count_by_type: dict[str, int] = defaultdict(int)
        for item in recent:
            kind = item["event_type"]
            strongest_by_type[kind] = max(
                strongest_by_type.get(kind, 0.0), item["confidence"]
            )
            count_by_type[kind] += 1
        weighted = sum(
            EVENT_WEIGHTS.get(kind, 0) * confidence_value
            for kind, confidence_value in strongest_by_type.items()
        )
        persistence_bonus = sum(
            min(max(count - 1, 0), 3) * 2 for count in count_by_type.values()
        )
        kinds = {item["event_type"] for item in recent}
        active_groups = [name for name, members in CORROBORATING_GROUPS.items() if kinds & members]
        corroboration_bonus = max(0, len(active_groups) - 1) * 8
        score = min(100, round(weighted + persistence_bonus + corroboration_bonus))
        level = "low" if score < 20 else "medium" if score < 45 else "high" if score < 70 else "critical"

        reasons = [f"{event_type} observed with confidence {confidence:.2f}"]
        if signal_quality < 0.45:
            reasons.append("Current signal quality is insufficient for fusion")
        if len(active_groups) > 1:
            reasons.append("Corroborating signals: " + ", ".join(active_groups))
        if event_type.startswith("gaze") or event_type.startswith("sustained_gaze"):
            reasons.append("Gaze is contextual evidence and is never treated as proof by itself")

        needs_review = signal_quality >= 0.45 and (score >= 45 or event_type in {
            "multiple_people_detected", "continuous_liveness_spoof_risk"
        })
        actions: tuple[str, ...] = ("capture_review_snapshot",) if needs_review else ()
        disposition = "human_review" if needs_review else "continue_observation"
        return ReviewResult(
            score, level, disposition, tuple(reasons), actions, needs_review,
            tuple(active_groups), 120,
        )

    def observe_audio(self, observation: dict[str, Any]) -> dict[str, Any]:
        """Classify temporal acoustic behaviour from normalized features only."""
        attempt_id = _required_text(observation, "attempt_id")
        label = str(observation.get("label") or "unclear_environment_sound")
        confidence = _confidence(observation.get("voice_confidence", 0.0))
        signal_quality = _confidence(observation.get("signal_quality", 0.0))
        baseline_deviation = _non_negative_number(
            observation.get("baseline_deviation", 0.0), "baseline_deviation"
        )
        duration_ms = int(_non_negative_number(
            observation.get("duration_ms", 1000), "duration_ms"
        ))
        duration_ms = min(duration_ms, 5000)
        calibrated = observation.get("calibrated") is True
        near_voice = observation.get("near_voice") is True
        background_voice = observation.get("background_voice") is True
        unusual = observation.get("allowed_ambient") is not True
        item = {
            "label": label,
            "voice_confidence": confidence,
            "signal_quality": signal_quality,
            "baseline_deviation": baseline_deviation,
            "duration_ms": duration_ms,
            "calibrated": calibrated,
            "near_voice": near_voice,
            "background_voice": background_voice,
            "unusual": unusual,
            "observed_at": str(observation.get("observed_at") or _utc_now()),
        }
        history = self._audio[attempt_id]
        history.append(item)
        recent = list(history)[-30:]
        reliable = [
            entry for entry in recent
            if entry["calibrated"] and entry["signal_quality"] >= 0.45
        ]
        near_voice_ms = sum(
            entry["duration_ms"] for entry in reliable
            if entry["near_voice"] and entry["voice_confidence"] >= 0.55
        )
        background_voice_ms = sum(
            entry["duration_ms"] for entry in reliable
            if entry["background_voice"] and entry["voice_confidence"] >= 0.40
        )
        unusual_samples = sum(
            1 for entry in reliable
            if entry["unusual"] and entry["baseline_deviation"] >= 2.5
        )
        if not calibrated or signal_quality < 0.45:
            state = "uncertain"
        elif near_voice_ms >= 3000 or background_voice_ms >= 8000 or unusual_samples >= 5:
            state = "needs_review"
        else:
            state = "normal"
        return {
            "state": state,
            "label": label,
            "reliable_samples": len(reliable),
            "near_voice_duration_ms": near_voice_ms,
            "background_voice_duration_ms": background_voice_ms,
            "unusual_samples": unusual_samples,
            "observable_behaviour_only": True,
            "stores_raw_media": False,
            "proposed_actions": [],
        }

    def clear_attempt(self, attempt_id: str) -> bool:
        removed_events = self._events.pop(attempt_id, None) is not None
        removed_gaze = self._gaze.pop(attempt_id, None) is not None
        removed_audio = self._audio.pop(attempt_id, None) is not None
        return removed_events or removed_gaze or removed_audio

    def event_count(self, attempt_id: str) -> int:
        return len(self._events.get(attempt_id, ()))


def _required_text(value: dict[str, Any], key: str) -> str:
    result = value.get(key)
    if not isinstance(result, str) or not result.strip():
        raise ValueError(f"{key} must be a non-empty string")
    return result.strip()


def _non_negative_number(value: Any, key: str) -> float:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise ValueError(f"{key} must be a number")
    result = float(value)
    if result < 0:
        raise ValueError(f"{key} must be non-negative")
    return result


def _confidence(value: Any) -> float:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise ValueError("confidence must be a number")
    return max(0.0, min(1.0, float(value)))


def _utc_now() -> str:
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


def _parse_timestamp(value: Any) -> datetime:
    if value is None:
        return datetime.now(timezone.utc)
    if not isinstance(value, str) or not value.strip():
        raise ValueError("occurred_at must be an ISO-8601 timestamp")
    try:
        parsed = datetime.fromisoformat(value.strip().replace("Z", "+00:00"))
    except ValueError as error:
        raise ValueError("occurred_at must be an ISO-8601 timestamp") from error
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=timezone.utc)
    return parsed.astimezone(timezone.utc)

"""Recorded native E1 trace assertions. Rust supplies all tracks and memory.

This validates a recorded trace, not network isolation or camera availability.
An operator must run the native capture with networking disabled separately.
"""

from .e1_ml_common import integer, required
from .e1_evaluation import fingerprint
from .model_event import ModelEventV1


def check_scenarios(spec, trace):
    if trace.get("scenario_sha256") != fingerprint(spec):
        raise ValueError("Trace does not identify this scenario specification")
    cases = spec.get("cases")
    if not isinstance(cases, list) or not cases:
        raise ValueError("At least one recorded scenario is required")
    if trace.get("tracker_owner") != "rust":
        raise ValueError("Tracks must come from the native Rust pipeline")
    required(trace.get("native_build_id"), "native_build_id")
    frames = {}
    for frame in trace.get("frames", []):
        key = (required(frame.get("session_id"), "session_id"),
               integer(frame.get("source_frame_id"), "source_frame_id", 0))
        integer(frame.get("capture_timestamp_ns"), "capture_timestamp_ns", 0)
        if key in frames:
            raise ValueError("Duplicate frame identity")
        frames[key] = frame
    if not frames:
        raise ValueError("Trace has no source capture records")
    events = {}
    for raw in trace.get("events", []):
        event = ModelEventV1.from_dict(raw)
        key = (event.session_id, event.source_frame_id)
        if key not in frames or frames[key]["capture_timestamp_ns"] != event.capture_timestamp_ns:
            raise ValueError("Original capture provenance changed")
        if event.event_id in events:
            raise ValueError("Duplicate event ID")
        events[event.event_id] = event
    outcomes = {}
    for outcome in trace.get("specialist_outcomes", []):
        key = (outcome.get("session_id"), outcome.get("source_frame_id"))
        if key not in frames or key in outcomes:
            raise ValueError("Invalid/duplicate specialist outcome frame")
        if outcome.get("status") not in {"completed", "skipped", "unavailable", "failed"}:
            raise ValueError("Invalid specialist execution status")
        if outcome["status"] != "completed":
            if outcome.get("evidence") != "UNKNOWN" or outcome.get("event_ids") != []:
                raise ValueError("Skipped/unavailable/failed specialist must stay UNKNOWN")
        ids = outcome.get("event_ids")
        if not isinstance(ids, list) or any(event_id not in events for event_id in ids):
            raise ValueError("Invalid specialist event IDs")
        if any((events[e].session_id, events[e].source_frame_id) != key for e in ids):
            raise ValueError("Specialist outcome/event capture mismatch")
        outcomes[key] = outcome
    for event in events.values():
        if event.metadata.get("producer") == "e1_small_object_specialist":
            key = (event.session_id, event.source_frame_id)
            if key not in outcomes or event.event_id not in outcomes[key]["event_ids"]:
                raise ValueError("Unaccounted specialist event; UNKNOWN cannot conceal detections")
    checked, seen_cases = [], set()
    for case in cases:
        case_id = required(case.get("case_id"), "case_id")
        if case_id in seen_cases:
            raise ValueError("Duplicate case ID")
        seen_cases.add(case_id)
        assertions = case.get("assertions", [])
        if not assertions:
            raise ValueError("A scenario without assertions cannot pass")
        for assertion in assertions:
            kind = assertion.get("kind")
            if kind in {"same_track", "distinct_tracks"}:
                ids = assertion.get("event_ids", [])
                if len(ids) < 2 or len(set(ids)) != len(ids) or any(e not in events for e in ids):
                    raise ValueError("Tracking assertion needs distinct existing event IDs")
                selected = [events[e] for e in ids]
                if len({e.session_id for e in selected}) != 1 or any(e.track_id is None for e in selected):
                    raise ValueError("Tracking assertion requires actual within-session Rust tracks")
                count = len({e.track_id for e in selected})
                if (kind == "same_track" and count != 1) or (kind == "distinct_tracks" and count != len(ids)):
                    raise ValueError(f"{case_id}: {kind} failed")
            elif kind == "event":
                event = events.get(assertion.get("event_id"))
                if event is None or event.class_id != assertion.get("class_id"):
                    raise ValueError(f"{case_id}: expected event/class missing")
                for field in ("capture_timestamp_ns", "source_frame_id", "session_id"):
                    if field in assertion and getattr(event, field) != assertion[field]:
                        raise ValueError(f"{case_id}: {field} changed")
            elif kind == "unknown":
                outcome = outcomes.get((assertion.get("session_id"), assertion.get("source_frame_id")))
                if outcome is None or outcome.get("evidence") != "UNKNOWN" or outcome.get("event_ids") != []:
                    raise ValueError(f"{case_id}: UNKNOWN not preserved")
            elif kind == "no_event":
                key = (assertion.get("session_id"), assertion.get("source_frame_id"))
                if key not in outcomes or outcomes[key]["status"] != "completed":
                    raise ValueError("No-event assertion requires completed specialist inference")
                if any(events[e].class_id == assertion["class_id"] for e in outcomes[key]["event_ids"]):
                    raise ValueError(f"{case_id}: unexpected class detected")
            else:
                raise ValueError(f"Unknown scenario assertion: {kind}")
        checked.append(case_id)
    return {"trace_assertions_passed": True, "cases": checked,
            "trace_sha256": fingerprint(trace), "scenario_sha256": fingerprint(spec),
            "native_build_id": trace["native_build_id"],
            "offline_device_acceptance": "pending_operator_evidence",
            "production_accepted": False}

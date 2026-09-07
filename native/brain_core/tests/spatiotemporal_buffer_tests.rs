use std::collections::BTreeMap;

use brain_core::api::model_event::{ModelEventV1, ValidityIntervalV1, MODEL_EVENT_SCHEMA_VERSION};
use brain_core::api::spatiotemporal_buffer::SpatiotemporalRingBufferV1;

fn event(
    event_id: &str,
    class_id: &str,
    capture_timestamp_ns: u64,
    inference_timestamp_ns: u64,
) -> ModelEventV1 {
    ModelEventV1 {
        schema_version: MODEL_EVENT_SCHEMA_VERSION.into(),
        session_id: "session-001".into(),
        event_id: event_id.into(),
        source_frame_id: Some(capture_timestamp_ns),
        capture_timestamp_ns,
        inference_timestamp_ns,
        model_id: "test-model".into(),
        model_version: "1.0.0".into(),
        track_id: Some("PERSON_TRACK_001".into()),
        class_id: class_id.into(),
        confidence: Some(0.9),
        quality: Some(0.9),
        geometry: None,
        validity_interval: ValidityIntervalV1 {
            start_timestamp_ns: capture_timestamp_ns,
            end_timestamp_ns: Some(capture_timestamp_ns + 100),
        },
        metadata: BTreeMap::new(),
    }
}

#[test]
fn aligns_asynchronous_results_by_capture_time_not_completion_time() {
    let mut buffer = SpatiotemporalRingBufferV1::new("session-001".into(), 8).unwrap();

    buffer.push(event("late-capture", "phone_visible", 20, 50)).unwrap();
    buffer.push(event("early-capture", "hand_reach", 10, 60)).unwrap();

    let captures: Vec<u64> = buffer
        .snapshot()
        .into_iter()
        .map(|item| item.capture_timestamp_ns)
        .collect();
    assert_eq!(captures, vec![10, 20]);
}

#[test]
fn remains_bounded_and_evicts_oldest_capture_time() {
    let mut buffer = SpatiotemporalRingBufferV1::new("session-001".into(), 2).unwrap();
    buffer.push(event("e1", "normal", 10, 11)).unwrap();
    buffer.push(event("e2", "normal", 20, 21)).unwrap();

    let result = buffer.push(event("e3", "normal", 30, 31)).unwrap();
    assert_eq!(result.evicted_event_id.as_deref(), Some("e1"));
    assert!(result.retained);
    assert_eq!(buffer.len(), 2);

    let stale = buffer.push(event("old-result", "normal", 5, 40)).unwrap();
    assert_eq!(stale.evicted_event_id.as_deref(), Some("old-result"));
    assert!(!stale.retained);
    assert_eq!(
        buffer
            .snapshot()
            .into_iter()
            .map(|item| item.event_id)
            .collect::<Vec<_>>(),
        vec!["e2".to_string(), "e3".to_string()]
    );
}

#[test]
fn rejects_cross_session_and_duplicate_events() {
    let mut buffer = SpatiotemporalRingBufferV1::new("session-001".into(), 4).unwrap();
    buffer.push(event("e1", "normal", 10, 11)).unwrap();
    assert!(buffer.push(event("e1", "normal", 11, 12)).is_err());

    let mut wrong_session = event("e2", "normal", 12, 13);
    wrong_session.session_id = "session-002".into();
    assert!(buffer.push(wrong_session).is_err());
}

#[test]
fn queries_validity_and_latest_track_evidence_without_interpolation() {
    let mut buffer = SpatiotemporalRingBufferV1::new("session-001".into(), 8).unwrap();
    buffer.push(event("e1", "gaze_right", 100, 110)).unwrap();
    buffer.push(event("e2", "gaze_right", 300, 310)).unwrap();

    let active = buffer.events_active_at(150);
    assert_eq!(active.len(), 1);
    assert_eq!(active[0].event_id, "e1");

    let latest = buffer
        .latest_for_class("gaze_right", Some("PERSON_TRACK_001"), 250)
        .unwrap();
    assert_eq!(latest.event_id, "e1");

    assert!(buffer
        .latest_for_class("eyes_left", Some("PERSON_TRACK_001"), 250)
        .is_none());
}

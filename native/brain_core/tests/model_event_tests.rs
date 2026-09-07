use std::collections::BTreeMap;

use brain_core::api::model_event::{
    BoundingBoxV1, KeypointV1, ModelEventV1, ModelGeometryV1, ValidityIntervalV1,
    MODEL_EVENT_CORE_FIELDS, MODEL_EVENT_SCHEMA_VERSION,
};
use serde_json::{json, Value};

fn sample_event() -> ModelEventV1 {
    let mut metadata = BTreeMap::new();
    metadata.insert("modality".into(), json!("vision"));
    metadata.insert("observable_behaviour_only".into(), json!(true));

    ModelEventV1 {
        schema_version: MODEL_EVENT_SCHEMA_VERSION.into(),
        session_id: "session-001".into(),
        event_id: "event-001".into(),
        source_frame_id: Some(42),
        capture_timestamp_ns: 10_200_000_000,
        inference_timestamp_ns: 10_451_000_000,
        model_id: "e1-object-detector".into(),
        model_version: "1.0.0".into(),
        track_id: Some("PERSON_TRACK_001".into()),
        class_id: "phone_visible".into(),
        confidence: Some(0.91),
        quality: Some(0.88),
        geometry: Some(ModelGeometryV1 {
            coordinate_space: Some("normalized_frame".into()),
            bounding_box: Some(BoundingBoxV1 {
                x: 0.60,
                y: 0.55,
                width: 0.12,
                height: 0.20,
            }),
            keypoints: vec![KeypointV1 {
                x: 0.66,
                y: 0.64,
                confidence: Some(0.80),
                label: Some("object_center".into()),
            }],
            vector: None,
            region_id: Some("lower_right".into()),
        }),
        validity_interval: ValidityIntervalV1 {
            start_timestamp_ns: 10_200_000_000,
            end_timestamp_ns: Some(10_700_000_000),
        },
        metadata,
    }
}

#[test]
fn serializes_every_frozen_core_field_and_roundtrips() {
    let event = sample_event();
    let encoded = event.to_json().unwrap();
    let value: Value = serde_json::from_str(&encoded).unwrap();
    let object = value.as_object().unwrap();

    for field in MODEL_EVENT_CORE_FIELDS {
        assert!(object.contains_key(field), "missing serialized field {field}");
    }
    assert_eq!(value["capture_timestamp_ns"], json!(10_200_000_000_u64));
    assert_eq!(value["inference_timestamp_ns"], json!(10_451_000_000_u64));

    let decoded = ModelEventV1::from_json(&encoded).unwrap();
    assert_eq!(decoded, event);
}

#[test]
fn unknown_optional_evidence_is_preserved_as_null_not_invented() {
    let mut event = sample_event();
    event.source_frame_id = None;
    event.track_id = None;
    event.confidence = None;
    event.quality = None;
    event.geometry = None;

    let encoded = event.to_json().unwrap();
    let value: Value = serde_json::from_str(&encoded).unwrap();

    assert!(value["source_frame_id"].is_null());
    assert!(value["track_id"].is_null());
    assert!(value["confidence"].is_null());
    assert!(value["quality"].is_null());
    assert!(value["geometry"].is_null());
}

#[test]
fn rejects_temporal_misalignment_and_invalid_ranges() {
    let mut event = sample_event();
    event.inference_timestamp_ns = event.capture_timestamp_ns - 1;
    assert!(event.validate().is_err());

    let mut event = sample_event();
    event.confidence = Some(1.1);
    assert!(event.validate().is_err());

    let mut event = sample_event();
    event.validity_interval.end_timestamp_ns = Some(
        event.validity_interval.start_timestamp_ns - 1,
    );
    assert!(event.validate().is_err());
}

#[test]
fn json_ingestion_rejects_missing_frozen_core_fields() {
    let mut value: Value = serde_json::from_str(&sample_event().to_json().unwrap()).unwrap();
    value.as_object_mut().unwrap().remove("quality");

    let error = ModelEventV1::from_json(&value.to_string()).unwrap_err();
    assert!(error.contains("missing ModelEventV1 core fields"));
    assert!(error.contains("quality"));
}

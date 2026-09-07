use std::collections::HashMap;
use std::sync::Mutex;

use flutter_rust_bridge::frb;
use once_cell::sync::Lazy;
use serde::{Deserialize, Serialize};

use super::model_event::ModelEventV1;
use super::spatiotemporal_buffer::{RingBufferInsertResultV1, SpatiotemporalRingBufferV1};

const DEFAULT_MODEL_EVENT_CAPACITY: usize = 4096;
const MAX_MODEL_EVENT_CAPACITY: usize = 100_000;

static MODEL_EVENT_MEMORY: Lazy<Mutex<HashMap<String, SpatiotemporalRingBufferV1>>> =
    Lazy::new(|| Mutex::new(HashMap::new()));

#[frb]
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct ModelEventIngestResultV1 {
    pub session_id: String,
    pub event_id: String,
    pub retained: bool,
    pub evicted_event_id: Option<String>,
    pub len: u64,
    pub capacity: u64,
}

#[frb]
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct ModelEventMemoryStatusV1 {
    pub session_id: String,
    pub exists: bool,
    pub len: u64,
    pub capacity: u64,
}

/// Transitional JSON ingress for the frozen ModelEventV1 contract.
///
/// JSON is intentionally used at the integration boundary while the event bus
/// is being migrated. The internal memory is Rust-owned and typed. A compact
/// binary transport can replace this ingress later without changing the event
/// semantics.
#[frb(sync)]
pub fn ingest_model_event_v1_json(
    event_json: String,
    requested_capacity: Option<u64>,
) -> Result<ModelEventIngestResultV1, String> {
    let event = ModelEventV1::from_json(&event_json)?;
    let session_id = event.session_id.clone();
    let event_id = event.event_id.clone();
    let capacity = normalize_capacity(requested_capacity)?;

    let mut memory = MODEL_EVENT_MEMORY
        .lock()
        .map_err(|_| "model event memory lock is poisoned".to_string())?;
    let buffer = if let Some(existing) = memory.get_mut(&session_id) {
        existing
    } else {
        memory.insert(
            session_id.clone(),
            SpatiotemporalRingBufferV1::new(session_id.clone(), capacity)?,
        );
        memory
            .get_mut(&session_id)
            .ok_or_else(|| "failed to initialize model event memory".to_string())?
    };

    let result = buffer.push(event)?;
    Ok(to_ingest_result(session_id, event_id, result))
}

#[frb(sync)]
pub fn model_event_memory_status_v1(
    session_id: String,
) -> Result<ModelEventMemoryStatusV1, String> {
    let session_id = require_session_id(session_id)?;
    let memory = MODEL_EVENT_MEMORY
        .lock()
        .map_err(|_| "model event memory lock is poisoned".to_string())?;
    let Some(buffer) = memory.get(&session_id) else {
        return Ok(ModelEventMemoryStatusV1 {
            session_id,
            exists: false,
            len: 0,
            capacity: 0,
        });
    };
    Ok(ModelEventMemoryStatusV1 {
        session_id,
        exists: true,
        len: buffer.len() as u64,
        capacity: buffer.capacity() as u64,
    })
}

#[frb(sync)]
pub fn read_model_events_between_v1_json(
    session_id: String,
    start_capture_timestamp_ns: u64,
    end_capture_timestamp_ns: u64,
) -> Result<String, String> {
    let session_id = require_session_id(session_id)?;
    let memory = MODEL_EVENT_MEMORY
        .lock()
        .map_err(|_| "model event memory lock is poisoned".to_string())?;
    let events = match memory.get(&session_id) {
        Some(buffer) => buffer.events_between(
            start_capture_timestamp_ns,
            end_capture_timestamp_ns,
        )?,
        None => Vec::new(),
    };
    serde_json::to_string(&events).map_err(|error| error.to_string())
}

#[frb(sync)]
pub fn read_model_events_active_at_v1_json(
    session_id: String,
    timestamp_ns: u64,
) -> Result<String, String> {
    let session_id = require_session_id(session_id)?;
    let memory = MODEL_EVENT_MEMORY
        .lock()
        .map_err(|_| "model event memory lock is poisoned".to_string())?;
    let events = match memory.get(&session_id) {
        Some(buffer) => buffer.events_active_at(timestamp_ns),
        None => Vec::new(),
    };
    serde_json::to_string(&events).map_err(|error| error.to_string())
}

#[frb(sync)]
pub fn clear_model_event_memory_v1(session_id: String) -> Result<bool, String> {
    let session_id = require_session_id(session_id)?;
    let mut memory = MODEL_EVENT_MEMORY
        .lock()
        .map_err(|_| "model event memory lock is poisoned".to_string())?;
    Ok(memory.remove(&session_id).is_some())
}

fn normalize_capacity(requested_capacity: Option<u64>) -> Result<usize, String> {
    let requested = requested_capacity.unwrap_or(DEFAULT_MODEL_EVENT_CAPACITY as u64);
    if requested == 0 {
        return Err("model event memory capacity must be greater than zero".into());
    }
    let requested = usize::try_from(requested)
        .map_err(|_| "model event memory capacity does not fit this platform".to_string())?;
    if requested > MAX_MODEL_EVENT_CAPACITY {
        return Err(format!(
            "model event memory capacity exceeds maximum {MAX_MODEL_EVENT_CAPACITY}"
        ));
    }
    Ok(requested)
}

fn require_session_id(session_id: String) -> Result<String, String> {
    let trimmed = session_id.trim();
    if trimmed.is_empty() {
        return Err("session_id must be a non-empty string".into());
    }
    Ok(trimmed.to_string())
}

fn to_ingest_result(
    session_id: String,
    event_id: String,
    result: RingBufferInsertResultV1,
) -> ModelEventIngestResultV1 {
    ModelEventIngestResultV1 {
        session_id,
        event_id,
        retained: result.retained,
        evicted_event_id: result.evicted_event_id,
        len: result.len as u64,
        capacity: result.capacity as u64,
    }
}

#[cfg(test)]
mod tests {
    use std::collections::BTreeMap;

    use super::*;
    use crate::api::model_event::{ValidityIntervalV1, MODEL_EVENT_SCHEMA_VERSION};

    fn event_json(session: &str, event_id: &str, capture: u64, inference: u64) -> String {
        ModelEventV1 {
            schema_version: MODEL_EVENT_SCHEMA_VERSION.into(),
            session_id: session.into(),
            event_id: event_id.into(),
            source_frame_id: Some(capture),
            capture_timestamp_ns: capture,
            inference_timestamp_ns: inference,
            model_id: "e1-yolo-exam-review".into(),
            model_version: "development-baseline-1".into(),
            track_id: None,
            class_id: "person".into(),
            confidence: Some(0.9),
            quality: Some(0.8),
            geometry: None,
            validity_interval: ValidityIntervalV1 {
                start_timestamp_ns: capture,
                end_timestamp_ns: Some(capture),
            },
            metadata: BTreeMap::new(),
        }
        .to_json()
        .unwrap()
    }

    #[test]
    fn ingest_is_session_scoped_and_capture_time_ordered() {
        let session = "model-memory-test-order";
        clear_model_event_memory_v1(session.into()).unwrap();
        ingest_model_event_v1_json(event_json(session, "late", 20, 30), Some(4)).unwrap();
        ingest_model_event_v1_json(event_json(session, "early", 10, 40), Some(4)).unwrap();

        let raw = read_model_events_between_v1_json(session.into(), 0, 100).unwrap();
        let events: Vec<ModelEventV1> = serde_json::from_str(&raw).unwrap();
        assert_eq!(events.len(), 2);
        assert_eq!(events[0].event_id, "early");
        assert_eq!(events[1].event_id, "late");
        clear_model_event_memory_v1(session.into()).unwrap();
    }

    #[test]
    fn ingest_rejects_duplicate_event_ids() {
        let session = "model-memory-test-duplicate";
        clear_model_event_memory_v1(session.into()).unwrap();
        let raw = event_json(session, "same", 10, 11);
        ingest_model_event_v1_json(raw.clone(), Some(4)).unwrap();
        assert!(ingest_model_event_v1_json(raw, Some(4)).is_err());
        clear_model_event_memory_v1(session.into()).unwrap();
    }

    #[test]
    fn clear_removes_only_requested_session() {
        let first = "model-memory-test-clear-a";
        let second = "model-memory-test-clear-b";
        clear_model_event_memory_v1(first.into()).unwrap();
        clear_model_event_memory_v1(second.into()).unwrap();
        ingest_model_event_v1_json(event_json(first, "a", 1, 2), Some(4)).unwrap();
        ingest_model_event_v1_json(event_json(second, "b", 1, 2), Some(4)).unwrap();

        assert!(clear_model_event_memory_v1(first.into()).unwrap());
        assert!(!model_event_memory_status_v1(first.into()).unwrap().exists);
        assert!(model_event_memory_status_v1(second.into()).unwrap().exists);
        clear_model_event_memory_v1(second.into()).unwrap();
    }
}

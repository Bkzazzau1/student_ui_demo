use std::cmp::Ordering;
use std::collections::{HashSet, VecDeque};

use serde::{Deserialize, Serialize};

use super::model_event::ModelEventV1;

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct RingBufferInsertResultV1 {
    pub retained: bool,
    pub evicted_event_id: Option<String>,
    pub len: usize,
    pub capacity: usize,
}

#[derive(Debug, Clone)]
pub struct SpatiotemporalRingBufferV1 {
    session_id: String,
    capacity: usize,
    events: VecDeque<ModelEventV1>,
    event_ids: HashSet<String>,
}

impl SpatiotemporalRingBufferV1 {
    pub fn new(session_id: String, capacity: usize) -> Result<Self, String> {
        if session_id.trim().is_empty() {
            return Err("session_id must be a non-empty string".into());
        }
        if capacity == 0 {
            return Err("capacity must be greater than zero".into());
        }
        Ok(Self {
            session_id: session_id.trim().to_string(),
            capacity,
            events: VecDeque::with_capacity(capacity),
            event_ids: HashSet::with_capacity(capacity),
        })
    }

    pub fn session_id(&self) -> &str {
        &self.session_id
    }

    pub fn capacity(&self) -> usize {
        self.capacity
    }

    pub fn len(&self) -> usize {
        self.events.len()
    }

    pub fn is_empty(&self) -> bool {
        self.events.is_empty()
    }

    pub fn push(&mut self, event: ModelEventV1) -> Result<RingBufferInsertResultV1, String> {
        event.validate()?;
        if event.session_id != self.session_id {
            return Err(format!(
                "event session_id {} does not match ring-buffer session_id {}",
                event.session_id, self.session_id
            ));
        }
        if self.event_ids.contains(&event.event_id) {
            return Err(format!("duplicate event_id {}", event.event_id));
        }

        let event_id = event.event_id.clone();
        let insert_at = self
            .events
            .iter()
            .position(|existing| event_order(&event, existing) == Ordering::Less)
            .unwrap_or(self.events.len());

        self.events.insert(insert_at, event);
        self.event_ids.insert(event_id.clone());

        let mut evicted_event_id = None;
        if self.events.len() > self.capacity {
            if let Some(evicted) = self.events.pop_front() {
                self.event_ids.remove(&evicted.event_id);
                evicted_event_id = Some(evicted.event_id);
            }
        }

        Ok(RingBufferInsertResultV1 {
            retained: self.event_ids.contains(&event_id),
            evicted_event_id,
            len: self.events.len(),
            capacity: self.capacity,
        })
    }

    pub fn events_between(
        &self,
        start_capture_timestamp_ns: u64,
        end_capture_timestamp_ns: u64,
    ) -> Result<Vec<ModelEventV1>, String> {
        if end_capture_timestamp_ns < start_capture_timestamp_ns {
            return Err("end_capture_timestamp_ns must be >= start_capture_timestamp_ns".into());
        }
        Ok(self
            .events
            .iter()
            .filter(|event| {
                event.capture_timestamp_ns >= start_capture_timestamp_ns
                    && event.capture_timestamp_ns <= end_capture_timestamp_ns
            })
            .cloned()
            .collect())
    }

    pub fn events_active_at(&self, timestamp_ns: u64) -> Vec<ModelEventV1> {
        self.events
            .iter()
            .filter(|event| {
                event.validity_interval.start_timestamp_ns <= timestamp_ns
                    && event
                        .validity_interval
                        .end_timestamp_ns
                        .is_none_or(|end| end >= timestamp_ns)
            })
            .cloned()
            .collect()
    }

    pub fn latest_for_class(
        &self,
        class_id: &str,
        track_id: Option<&str>,
        at_or_before_capture_timestamp_ns: u64,
    ) -> Option<ModelEventV1> {
        self.events
            .iter()
            .rev()
            .find(|event| {
                event.capture_timestamp_ns <= at_or_before_capture_timestamp_ns
                    && event.class_id == class_id
                    && match track_id {
                        Some(expected_track_id) => event.track_id.as_deref() == Some(expected_track_id),
                        None => true,
                    }
            })
            .cloned()
    }

    pub fn snapshot(&self) -> Vec<ModelEventV1> {
        self.events.iter().cloned().collect()
    }

    pub fn clear(&mut self) {
        self.events.clear();
        self.event_ids.clear();
    }
}

fn event_order(left: &ModelEventV1, right: &ModelEventV1) -> Ordering {
    left.capture_timestamp_ns
        .cmp(&right.capture_timestamp_ns)
        .then_with(|| left.inference_timestamp_ns.cmp(&right.inference_timestamp_ns))
        .then_with(|| left.event_id.cmp(&right.event_id))
}

use std::collections::HashMap;

use serde_json::json;

use super::model_event::{BoundingBoxV1, ModelEventV1};

const MAX_CONTINUITY_GAP_NS: u64 = 2_000_000_000;
const GAP_RECOVERY_THRESHOLD_NS: u64 = 500_000_000;
const MIN_IOU_FOR_MATCH: f32 = 0.10;
const BASE_MAX_CENTER_DISTANCE: f32 = 0.12;
const MAX_CENTER_DISTANCE: f32 = 0.20;
const MIN_ASSOCIATION_SCORE: f32 = 0.18;

#[derive(Debug, Clone, PartialEq)]
pub(crate) struct PersonTrackEnrichmentV1 {
    pub track_id: String,
    pub is_new_track: bool,
    pub track_state: String,
    pub duration_ns: u64,
    pub hit_count: u64,
    pub gap_recovered: bool,
    pub gap_recovery_count: u64,
    pub association_score: Option<f32>,
    pub motion_state: String,
}

#[derive(Debug, Clone)]
struct PersonTrackStateV1 {
    track_id: String,
    first_seen_ns: u64,
    last_seen_ns: u64,
    last_source_frame_id: Option<u64>,
    last_box: BoundingBoxV1,
    velocity_x_per_second: f32,
    velocity_y_per_second: f32,
    hit_count: u64,
    gap_recovery_count: u64,
}

#[derive(Debug, Default)]
pub(crate) struct PersonTrackerV1 {
    next_track_number: u64,
    latest_capture_timestamp_ns: Option<u64>,
    tracks: HashMap<String, PersonTrackStateV1>,
}

impl PersonTrackerV1 {
    pub(crate) fn new() -> Self {
        Self {
            next_track_number: 1,
            latest_capture_timestamp_ns: None,
            tracks: HashMap::new(),
        }
    }

    /// Enrich a person observation with a persistent track ID when the evidence
    /// is strong enough. Existing upstream track IDs are never overwritten.
    ///
    /// The tracker is deliberately conservative. It performs short-term
    /// geometry/motion association only; it does not claim long-gap biometric
    /// re-identification. Late out-of-order frames remain untracked rather than
    /// being force-associated with newer state.
    pub(crate) fn enrich_event(
        &mut self,
        event: &mut ModelEventV1,
    ) -> Option<PersonTrackEnrichmentV1> {
        if !is_person_class(&event.class_id) || event.track_id.is_some() {
            return None;
        }

        if let Some(latest) = self.latest_capture_timestamp_ns {
            if event.capture_timestamp_ns < latest {
                event
                    .metadata
                    .insert("tracking_status".into(), json!("late_frame_unresolved"));
                event
                    .metadata
                    .insert("persistent_tracking_available".into(), json!(true));
                return None;
            }
        }

        let Some(current_box) = event
            .geometry
            .as_ref()
            .and_then(|geometry| geometry.bounding_box.as_ref())
            .filter(|bbox| valid_normalized_box(bbox))
            .cloned()
        else {
            event
                .metadata
                .insert("tracking_status".into(), json!("geometry_unavailable"));
            event
                .metadata
                .insert("persistent_tracking_available".into(), json!(true));
            return None;
        };

        self.latest_capture_timestamp_ns = Some(
            self.latest_capture_timestamp_ns
                .map_or(event.capture_timestamp_ns, |latest| {
                    latest.max(event.capture_timestamp_ns)
                }),
        );
        self.expire_stale_tracks(event.capture_timestamp_ns);

        let best_match = self.best_match(event, &current_box);
        let enrichment = match best_match {
            Some((track_id, association_score)) => self.update_track(
                &track_id,
                event.source_frame_id,
                event.capture_timestamp_ns,
                current_box,
                association_score,
            ),
            None => self.create_track(
                event.source_frame_id,
                event.capture_timestamp_ns,
                current_box,
            ),
        };

        event.track_id = Some(enrichment.track_id.clone());
        attach_tracking_metadata(event, &enrichment);
        Some(enrichment)
    }

    fn best_match(
        &self,
        event: &ModelEventV1,
        current_box: &BoundingBoxV1,
    ) -> Option<(String, f32)> {
        let mut best: Option<(String, f32)> = None;

        for track in self.tracks.values() {
            if track_seen_in_same_frame(track, event) {
                continue;
            }
            if event.capture_timestamp_ns < track.last_seen_ns {
                continue;
            }

            let gap_ns = event.capture_timestamp_ns - track.last_seen_ns;
            if gap_ns > MAX_CONTINUITY_GAP_NS {
                continue;
            }

            let predicted = predicted_box(track, gap_ns);
            let overlap = iou(&predicted, current_box);
            let distance = center_distance(&predicted, current_box);
            let gap_ratio = (gap_ns as f32 / MAX_CONTINUITY_GAP_NS as f32).clamp(0.0, 1.0);
            let max_distance = BASE_MAX_CENTER_DISTANCE
                + (MAX_CENTER_DISTANCE - BASE_MAX_CENTER_DISTANCE) * gap_ratio;
            let proximity = (1.0 - distance / max_distance.max(0.001)).clamp(0.0, 1.0);
            let score = overlap * 0.75 + proximity * 0.25;

            if overlap < MIN_IOU_FOR_MATCH && distance > max_distance {
                continue;
            }
            if score < MIN_ASSOCIATION_SCORE {
                continue;
            }

            match &best {
                Some((_, best_score)) if *best_score >= score => {}
                _ => best = Some((track.track_id.clone(), score)),
            }
        }

        best
    }

    fn create_track(
        &mut self,
        source_frame_id: Option<u64>,
        capture_timestamp_ns: u64,
        current_box: BoundingBoxV1,
    ) -> PersonTrackEnrichmentV1 {
        let track_id = format!("PERSON_TRACK_{:06}", self.next_track_number);
        self.next_track_number = self.next_track_number.saturating_add(1);

        self.tracks.insert(
            track_id.clone(),
            PersonTrackStateV1 {
                track_id: track_id.clone(),
                first_seen_ns: capture_timestamp_ns,
                last_seen_ns: capture_timestamp_ns,
                last_source_frame_id: source_frame_id,
                last_box: current_box,
                velocity_x_per_second: 0.0,
                velocity_y_per_second: 0.0,
                hit_count: 1,
                gap_recovery_count: 0,
            },
        );

        PersonTrackEnrichmentV1 {
            track_id,
            is_new_track: true,
            track_state: "tentative".into(),
            duration_ns: 0,
            hit_count: 1,
            gap_recovered: false,
            gap_recovery_count: 0,
            association_score: None,
            motion_state: "unknown".into(),
        }
    }

    fn update_track(
        &mut self,
        track_id: &str,
        source_frame_id: Option<u64>,
        capture_timestamp_ns: u64,
        current_box: BoundingBoxV1,
        association_score: f32,
    ) -> PersonTrackEnrichmentV1 {
        let track = self
            .tracks
            .get_mut(track_id)
            .expect("best_match only returns existing track IDs");

        let gap_ns = capture_timestamp_ns.saturating_sub(track.last_seen_ns);
        let gap_recovered = gap_ns >= GAP_RECOVERY_THRESHOLD_NS;
        if gap_recovered {
            track.gap_recovery_count = track.gap_recovery_count.saturating_add(1);
        }

        let previous_box = track.last_box.clone();
        if gap_ns > 0 {
            let seconds = gap_ns as f32 / 1_000_000_000.0;
            let (old_x, old_y) = center(&previous_box);
            let (new_x, new_y) = center(&current_box);
            let observed_vx = ((new_x - old_x) / seconds).clamp(-1.0, 1.0);
            let observed_vy = ((new_y - old_y) / seconds).clamp(-1.0, 1.0);
            track.velocity_x_per_second = track.velocity_x_per_second * 0.60 + observed_vx * 0.40;
            track.velocity_y_per_second = track.velocity_y_per_second * 0.60 + observed_vy * 0.40;
        }

        track.last_seen_ns = capture_timestamp_ns;
        track.last_source_frame_id = source_frame_id;
        track.last_box = current_box.clone();
        track.hit_count = track.hit_count.saturating_add(1);

        PersonTrackEnrichmentV1 {
            track_id: track.track_id.clone(),
            is_new_track: false,
            track_state: if track.hit_count >= 2 {
                "confirmed".into()
            } else {
                "tentative".into()
            },
            duration_ns: capture_timestamp_ns.saturating_sub(track.first_seen_ns),
            hit_count: track.hit_count,
            gap_recovered,
            gap_recovery_count: track.gap_recovery_count,
            association_score: Some(association_score.clamp(0.0, 1.0)),
            motion_state: motion_state(&previous_box, &current_box),
        }
    }

    fn expire_stale_tracks(&mut self, capture_timestamp_ns: u64) {
        self.tracks.retain(|_, track| {
            capture_timestamp_ns.saturating_sub(track.last_seen_ns) <= MAX_CONTINUITY_GAP_NS
        });
    }
}

fn is_person_class(class_id: &str) -> bool {
    matches!(
        class_id.trim().to_ascii_lowercase().as_str(),
        "person" | "partial_person" | "additional_person"
    )
}

fn valid_normalized_box(bbox: &BoundingBoxV1) -> bool {
    bbox.x.is_finite()
        && bbox.y.is_finite()
        && bbox.width.is_finite()
        && bbox.height.is_finite()
        && bbox.width > 0.0
        && bbox.height > 0.0
        && bbox.x >= 0.0
        && bbox.y >= 0.0
        && bbox.x <= 1.0
        && bbox.y <= 1.0
        && bbox.x + bbox.width <= 1.0001
        && bbox.y + bbox.height <= 1.0001
}

fn track_seen_in_same_frame(track: &PersonTrackStateV1, event: &ModelEventV1) -> bool {
    match (track.last_source_frame_id, event.source_frame_id) {
        (Some(previous), Some(current)) => previous == current,
        _ => track.last_seen_ns == event.capture_timestamp_ns,
    }
}

fn predicted_box(track: &PersonTrackStateV1, gap_ns: u64) -> BoundingBoxV1 {
    let seconds = (gap_ns as f32 / 1_000_000_000.0).clamp(0.0, 1.0);
    let predicted_x = (track.last_box.x + track.velocity_x_per_second * seconds).clamp(0.0, 1.0);
    let predicted_y = (track.last_box.y + track.velocity_y_per_second * seconds).clamp(0.0, 1.0);
    BoundingBoxV1 {
        x: predicted_x.min((1.0 - track.last_box.width).max(0.0)),
        y: predicted_y.min((1.0 - track.last_box.height).max(0.0)),
        width: track.last_box.width,
        height: track.last_box.height,
    }
}

fn center(bbox: &BoundingBoxV1) -> (f32, f32) {
    (bbox.x + bbox.width * 0.5, bbox.y + bbox.height * 0.5)
}

fn center_distance(left: &BoundingBoxV1, right: &BoundingBoxV1) -> f32 {
    let (left_x, left_y) = center(left);
    let (right_x, right_y) = center(right);
    let dx = left_x - right_x;
    let dy = left_y - right_y;
    (dx * dx + dy * dy).sqrt()
}

fn iou(left: &BoundingBoxV1, right: &BoundingBoxV1) -> f32 {
    let left_x2 = left.x + left.width;
    let left_y2 = left.y + left.height;
    let right_x2 = right.x + right.width;
    let right_y2 = right.y + right.height;

    let intersection_width = (left_x2.min(right_x2) - left.x.max(right.x)).max(0.0);
    let intersection_height = (left_y2.min(right_y2) - left.y.max(right.y)).max(0.0);
    let intersection = intersection_width * intersection_height;
    let union = left.width * left.height + right.width * right.height - intersection;
    if union <= 0.0 {
        0.0
    } else {
        (intersection / union).clamp(0.0, 1.0)
    }
}

fn motion_state(previous: &BoundingBoxV1, current: &BoundingBoxV1) -> String {
    let previous_area = previous.width * previous.height;
    let current_area = current.width * current.height;
    if previous_area <= 0.0 {
        return "unknown".into();
    }
    let ratio = current_area / previous_area;
    if ratio >= 1.12 {
        "approaching".into()
    } else if ratio <= 0.88 {
        "receding".into()
    } else {
        "stable".into()
    }
}

fn attach_tracking_metadata(event: &mut ModelEventV1, enrichment: &PersonTrackEnrichmentV1) {
    event
        .metadata
        .insert("persistent_tracking_available".into(), json!(true));
    event
        .metadata
        .insert("tracking_source".into(), json!("rust_iou_motion_v1"));
    event
        .metadata
        .insert("tracking_status".into(), json!(enrichment.track_state));
    event
        .metadata
        .insert("track_duration_ns".into(), json!(enrichment.duration_ns));
    event
        .metadata
        .insert("track_hits".into(), json!(enrichment.hit_count));
    event.metadata.insert(
        "short_gap_recovered".into(),
        json!(enrichment.gap_recovered),
    );
    event.metadata.insert(
        "gap_recovery_count".into(),
        json!(enrichment.gap_recovery_count),
    );
    event.metadata.insert(
        "association_score".into(),
        enrichment
            .association_score
            .map_or(serde_json::Value::Null, |score| json!(score)),
    );
    event
        .metadata
        .insert("motion_state".into(), json!(enrichment.motion_state));
    event
        .metadata
        .insert("new_track".into(), json!(enrichment.is_new_track));
}

#[cfg(test)]
mod tests {
    use std::collections::BTreeMap;

    use super::*;
    use crate::api::model_event::{
        MODEL_EVENT_SCHEMA_VERSION, ModelGeometryV1, ValidityIntervalV1,
    };

    fn person_event(frame_id: u64, capture: u64, x: f32, width: f32) -> ModelEventV1 {
        ModelEventV1 {
            schema_version: MODEL_EVENT_SCHEMA_VERSION.into(),
            session_id: "tracking-test".into(),
            event_id: format!("event-{frame_id}-{x}"),
            source_frame_id: Some(frame_id),
            capture_timestamp_ns: capture,
            inference_timestamp_ns: capture + 10,
            model_id: "e1-yolo-exam-review".into(),
            model_version: "development-baseline-1".into(),
            track_id: None,
            class_id: "person".into(),
            confidence: Some(0.9),
            quality: Some(0.8),
            geometry: Some(ModelGeometryV1 {
                coordinate_space: Some("normalized_frame".into()),
                bounding_box: Some(BoundingBoxV1 {
                    x,
                    y: 0.20,
                    width,
                    height: 0.60,
                }),
                keypoints: Vec::new(),
                vector: None,
                region_id: Some("middle_center".into()),
            }),
            validity_interval: ValidityIntervalV1 {
                start_timestamp_ns: capture,
                end_timestamp_ns: Some(capture),
            },
            metadata: BTreeMap::new(),
        }
    }

    #[test]
    fn keeps_stable_id_for_consistent_person_across_frames() {
        let mut tracker = PersonTrackerV1::new();
        let mut first = person_event(1, 1_000_000_000, 0.30, 0.30);
        let first_result = tracker.enrich_event(&mut first).unwrap();
        assert!(first_result.is_new_track);

        let mut second = person_event(2, 1_100_000_000, 0.31, 0.30);
        let second_result = tracker.enrich_event(&mut second).unwrap();
        assert_eq!(first.track_id, second.track_id);
        assert!(!second_result.is_new_track);
        assert_eq!(second_result.track_state, "confirmed");
    }

    #[test]
    fn assigns_distinct_tracks_to_two_people_in_same_frame() {
        let mut tracker = PersonTrackerV1::new();
        let mut left = person_event(1, 1_000_000_000, 0.05, 0.25);
        let mut right = person_event(1, 1_000_000_000, 0.65, 0.25);

        tracker.enrich_event(&mut left).unwrap();
        tracker.enrich_event(&mut right).unwrap();
        assert_ne!(left.track_id, right.track_id);
    }

    #[test]
    fn recovers_short_gap_but_does_not_claim_long_gap_reidentification() {
        let mut tracker = PersonTrackerV1::new();
        let mut first = person_event(1, 1_000_000_000, 0.30, 0.30);
        tracker.enrich_event(&mut first).unwrap();

        let mut short_gap = person_event(2, 1_700_000_000, 0.31, 0.30);
        let short_result = tracker.enrich_event(&mut short_gap).unwrap();
        assert_eq!(first.track_id, short_gap.track_id);
        assert!(short_result.gap_recovered);

        let mut long_gap = person_event(3, 4_000_000_000, 0.31, 0.30);
        let long_result = tracker.enrich_event(&mut long_gap).unwrap();
        assert_ne!(short_gap.track_id, long_gap.track_id);
        assert!(long_result.is_new_track);
    }

    #[test]
    fn late_out_of_order_frame_remains_untracked() {
        let mut tracker = PersonTrackerV1::new();
        let mut newer = person_event(2, 2_000_000_000, 0.30, 0.30);
        tracker.enrich_event(&mut newer).unwrap();

        let mut older = person_event(1, 1_000_000_000, 0.30, 0.30);
        assert!(tracker.enrich_event(&mut older).is_none());
        assert!(older.track_id.is_none());
        assert_eq!(
            older.metadata.get("tracking_status").unwrap(),
            &json!("late_frame_unresolved")
        );
    }

    #[test]
    fn non_person_event_is_not_modified() {
        let mut tracker = PersonTrackerV1::new();
        let mut event = person_event(1, 1_000_000_000, 0.30, 0.30);
        event.class_id = "cell_phone".into();
        assert!(tracker.enrich_event(&mut event).is_none());
        assert!(event.track_id.is_none());
        assert!(event.metadata.is_empty());
    }
}

use flutter_rust_bridge::frb;
use serde::{Deserialize, Serialize};

use super::hand_air_board::HandRegionSignal;
use super::native_vision::{decode_yolo_output, NativeVisionDetection};

#[frb]
#[derive(Clone, Debug, Serialize, Deserialize, PartialEq)]
pub struct HandVisionZones {
    pub keyboard_y_min: f32,
    pub stylus_x_min: f32,
    pub stylus_x_max: f32,
    pub stylus_y_min: f32,
    pub face_x_min: f32,
    pub face_x_max: f32,
    pub face_y_min: f32,
    pub face_y_max: f32,
    pub desk_line_y: f32,
}

#[frb]
#[derive(Clone, Debug, Serialize, Deserialize, PartialEq)]
pub struct HandVisionResult {
    pub signal: HandRegionSignal,
    pub detections: Vec<NativeVisionDetection>,
    pub usable: bool,
    pub attention_level: String,
    pub reason: String,
}

#[frb(sync)]
pub fn review_hand_model_output(
    output: Vec<f32>,
    num_predictions: i32,
    num_classes: i32,
    image_width: i32,
    image_height: i32,
    confidence_threshold: f32,
    iou_threshold: f32,
    layout: String,
    class_names: Vec<String>,
    zones: HandVisionZones,
    timestamp_ms: i64,
) -> HandVisionResult {
    let decoded = decode_yolo_output(
        output,
        num_predictions,
        num_classes,
        image_width,
        image_height,
        confidence_threshold,
        iou_threshold,
        layout,
        class_names,
    );

    review_hand_detections(
        decoded.detections,
        image_width,
        image_height,
        zones,
        timestamp_ms,
    )
}

#[frb(sync)]
pub fn review_hand_detections(
    detections: Vec<NativeVisionDetection>,
    image_width: i32,
    image_height: i32,
    zones: HandVisionZones,
    timestamp_ms: i64,
) -> HandVisionResult {
    if image_width <= 0 || image_height <= 0 {
        return empty_result(timestamp_ms, "invalid camera frame dimensions");
    }

    let mut hands: Vec<NativeVisionDetection> = detections
        .into_iter()
        .filter(|detection| {
            let label = detection.label.trim().to_ascii_lowercase();
            (label == "hand" || label == "left_hand" || label == "right_hand")
                && detection.confidence >= 0.25
        })
        .collect();

    hands.sort_by(|a, b| {
        b.confidence
            .partial_cmp(&a.confidence)
            .unwrap_or(std::cmp::Ordering::Equal)
    });

    let hand_count = hands.len() as i32;
    let primary = hands.first();
    if primary.is_none() {
        return HandVisionResult {
            signal: HandRegionSignal {
                hand_visible: false,
                hand_count: 0,
                primary_hand_x: 0.0,
                primary_hand_y: 0.0,
                hand_confidence: 0.0,
                near_keyboard: false,
                near_mouse_or_stylus_area: false,
                near_face: false,
                below_desk_line: false,
                timestamp_ms,
            },
            detections: hands,
            usable: true,
            attention_level: "medium_attention_required".to_string(),
            reason: "no reliable hand detection was found in the sampled camera frame".to_string(),
        };
    }

    let primary = primary.expect("primary hand already checked");
    let x = normalize_coordinate(primary.x_center, image_width as f32);
    let y = normalize_coordinate(primary.y_center, image_height as f32);

    let near_keyboard = y >= zones.keyboard_y_min.clamp(0.0, 1.0);
    let near_mouse_or_stylus_area = x >= zones.stylus_x_min.clamp(0.0, 1.0)
        && x <= zones.stylus_x_max.clamp(0.0, 1.0)
        && y >= zones.stylus_y_min.clamp(0.0, 1.0);
    let near_face = x >= zones.face_x_min.clamp(0.0, 1.0)
        && x <= zones.face_x_max.clamp(0.0, 1.0)
        && y >= zones.face_y_min.clamp(0.0, 1.0)
        && y <= zones.face_y_max.clamp(0.0, 1.0);
    let below_desk_line = y >= zones.desk_line_y.clamp(0.0, 1.0);

    let attention_level = if below_desk_line {
        "high_attention_required"
    } else if near_face {
        "medium_attention_required"
    } else {
        "normal"
    };

    let reason = if below_desk_line {
        "primary hand appears below the configured desk line"
    } else if near_face {
        "primary hand appears near the face region"
    } else if near_mouse_or_stylus_area {
        "primary hand appears in the expected mouse or stylus area"
    } else if near_keyboard {
        "primary hand appears in the expected keyboard area"
    } else {
        "hand is visible outside the configured work regions"
    };

    HandVisionResult {
        signal: HandRegionSignal {
            hand_visible: true,
            hand_count,
            primary_hand_x: x,
            primary_hand_y: y,
            hand_confidence: primary.confidence.clamp(0.0, 1.0),
            near_keyboard,
            near_mouse_or_stylus_area,
            near_face,
            below_desk_line,
            timestamp_ms,
        },
        detections: hands,
        usable: true,
        attention_level: attention_level.to_string(),
        reason: reason.to_string(),
    }
}

fn normalize_coordinate(value: f32, extent: f32) -> f32 {
    if value <= 1.5 {
        value.clamp(0.0, 1.0)
    } else if extent <= 0.0 {
        0.0
    } else {
        (value / extent).clamp(0.0, 1.0)
    }
}

fn empty_result(timestamp_ms: i64, reason: &str) -> HandVisionResult {
    HandVisionResult {
        signal: HandRegionSignal {
            hand_visible: false,
            hand_count: 0,
            primary_hand_x: 0.0,
            primary_hand_y: 0.0,
            hand_confidence: 0.0,
            near_keyboard: false,
            near_mouse_or_stylus_area: false,
            near_face: false,
            below_desk_line: false,
            timestamp_ms,
        },
        detections: Vec::new(),
        usable: false,
        attention_level: "medium_attention_required".to_string(),
        reason: reason.to_string(),
    }
}

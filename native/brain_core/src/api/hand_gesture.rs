use flutter_rust_bridge::frb;
use serde::{Deserialize, Serialize};

#[frb]
#[derive(Clone, Debug, Serialize, Deserialize, PartialEq)]
pub struct HandLandmarkPoint {
    pub index: i32,
    pub x: f32,
    pub y: f32,
    pub z: f32,
    pub confidence: f32,
}

#[frb]
#[derive(Clone, Debug, Serialize, Deserialize, PartialEq)]
pub struct HandGestureInput {
    pub landmarks: Vec<HandLandmarkPoint>,
    pub frame_width: i32,
    pub frame_height: i32,
    pub mirrored: bool,
    pub timestamp_ms: i64,
}

#[frb]
#[derive(Clone, Debug, Serialize, Deserialize, PartialEq)]
pub struct HandGestureResult {
    pub usable: bool,
    pub gesture: String,
    pub finger_count: i32,
    pub index_finger_extended: bool,
    pub index_tip_x: f32,
    pub index_tip_y: f32,
    pub writing_active: bool,
    pub erasing_active: bool,
    pub confidence: f32,
    pub student_message: String,
    pub reason: String,
}

#[frb(sync)]
pub fn analyze_hand_landmarks(input: HandGestureInput) -> HandGestureResult {
    if input.frame_width <= 0 || input.frame_height <= 0 {
        return unusable("invalid camera frame dimensions");
    }

    if input.landmarks.len() < 21 {
        return unusable("21 hand landmarks are required");
    }

    let mut points: Vec<Option<HandLandmarkPoint>> = vec![None; 21];
    for point in input.landmarks {
        if (0..21).contains(&point.index) {
            points[point.index as usize] = Some(point);
        }
    }

    if points.iter().any(|point| point.is_none()) {
        return unusable("one or more hand landmarks are missing");
    }

    let points: Vec<HandLandmarkPoint> = points.into_iter().map(|point| point.unwrap()).collect();
    let average_confidence = points
        .iter()
        .map(|point| point.confidence.clamp(0.0, 1.0))
        .sum::<f32>()
        / 21.0;

    if average_confidence < 0.45 {
        return unusable("hand landmarks are not reliable enough");
    }

    let thumb_extended = thumb_is_extended(&points, input.mirrored);
    let index_extended = finger_is_extended(&points, 5, 6, 8);
    let middle_extended = finger_is_extended(&points, 9, 10, 12);
    let ring_extended = finger_is_extended(&points, 13, 14, 16);
    let little_extended = finger_is_extended(&points, 17, 18, 20);

    let finger_count = [
        thumb_extended,
        index_extended,
        middle_extended,
        ring_extended,
        little_extended,
    ]
    .iter()
    .filter(|extended| **extended)
    .count() as i32;

    let open_palm = finger_count >= 4;
    let index_only = index_extended && !middle_extended && !ring_extended && !little_extended;
    let two_fingers = index_extended && middle_extended && !ring_extended && !little_extended;
    let closed_hand = finger_count == 0;

    let index_tip = &points[8];
    let mut index_tip_x = normalize_coordinate(index_tip.x, input.frame_width as f32);
    let index_tip_y = normalize_coordinate(index_tip.y, input.frame_height as f32);
    if input.mirrored {
        index_tip_x = 1.0 - index_tip_x;
    }

    let (gesture, writing_active, erasing_active, message, reason) = if open_palm {
        (
            "open_palm",
            false,
            false,
            "Air Board is ready. Raise only your index finger to write.",
            "open palm detected",
        )
    } else if index_only {
        (
            "index_only",
            true,
            false,
            "Writing mode active. Move your index finger to write.",
            "only the index finger is extended",
        )
    } else if two_fingers {
        (
            "two_fingers",
            false,
            true,
            "Eraser mode active. Move two fingers over the area to erase.",
            "index and middle fingers are extended",
        )
    } else if closed_hand {
        (
            "closed_hand",
            false,
            false,
            "Writing paused.",
            "closed hand detected",
        )
    } else {
        (
            "other",
            false,
            false,
            "Show an open palm, one index finger, or two fingers.",
            "gesture does not match a supported Air Board command",
        )
    };

    HandGestureResult {
        usable: true,
        gesture: gesture.to_string(),
        finger_count,
        index_finger_extended: index_extended,
        index_tip_x: index_tip_x.clamp(0.0, 1.0),
        index_tip_y: index_tip_y.clamp(0.0, 1.0),
        writing_active,
        erasing_active,
        confidence: average_confidence,
        student_message: message.to_string(),
        reason: reason.to_string(),
    }
}

fn finger_is_extended(
    points: &[HandLandmarkPoint],
    mcp_index: usize,
    pip_index: usize,
    tip_index: usize,
) -> bool {
    let mcp = &points[mcp_index];
    let pip = &points[pip_index];
    let tip = &points[tip_index];

    let vertical_extension = tip.y < pip.y && pip.y < mcp.y;
    let tip_distance = distance(tip, mcp);
    let pip_distance = distance(pip, mcp);
    vertical_extension && tip_distance > pip_distance * 1.18
}

fn thumb_is_extended(points: &[HandLandmarkPoint], mirrored: bool) -> bool {
    let cmc = &points[1];
    let mcp = &points[2];
    let ip = &points[3];
    let tip = &points[4];

    let horizontal_extension = if mirrored {
        tip.x > ip.x && ip.x > mcp.x
    } else {
        tip.x < ip.x && ip.x < mcp.x
    };
    let tip_distance = distance(tip, cmc);
    let mcp_distance = distance(mcp, cmc);
    horizontal_extension && tip_distance > mcp_distance * 1.15
}

fn distance(a: &HandLandmarkPoint, b: &HandLandmarkPoint) -> f32 {
    let dx = a.x - b.x;
    let dy = a.y - b.y;
    let dz = a.z - b.z;
    (dx * dx + dy * dy + dz * dz).sqrt()
}

fn normalize_coordinate(value: f32, dimension: f32) -> f32 {
    if value >= 0.0 && value <= 1.0 {
        value
    } else if dimension > 0.0 {
        value / dimension
    } else {
        0.0
    }
}

fn unusable(reason: &str) -> HandGestureResult {
    HandGestureResult {
        usable: false,
        gesture: "hand_not_clear".to_string(),
        finger_count: 0,
        index_finger_extended: false,
        index_tip_x: 0.0,
        index_tip_y: 0.0,
        writing_active: false,
        erasing_active: false,
        confidence: 0.0,
        student_message: "Please keep your hand clearly visible to the camera.".to_string(),
        reason: reason.to_string(),
    }
}

use flutter_rust_bridge::frb;
use serde::{Deserialize, Serialize};

#[frb]
#[derive(Clone, Debug, Serialize, Deserialize, PartialEq)]
pub struct EyeRegionSignal {
    pub left_eye_open: f32,
    pub right_eye_open: f32,
    pub left_iris_x: f32,
    pub left_iris_y: f32,
    pub right_iris_x: f32,
    pub right_iris_y: f32,
    pub face_confidence: f32,
    pub landmark_confidence: f32,
    pub frame_brightness: f32,
    pub head_yaw: f32,
    pub head_pitch: f32,
    pub head_roll: f32,
}

#[frb]
#[derive(Clone, Debug, Serialize, Deserialize, PartialEq)]
pub struct EyeIntelligenceResult {
    pub usable: bool,
    pub eye_x: f32,
    pub eye_y: f32,
    pub openness_score: f32,
    pub signal_confidence: f32,
    pub head_stable: bool,
    pub attention_level: String,
    pub reason: String,
}

#[frb(sync)]
pub fn analyze_eye_region_signal(signal: EyeRegionSignal) -> EyeIntelligenceResult {
    let openness_score = ((signal.left_eye_open + signal.right_eye_open) / 2.0).clamp(0.0, 1.0);
    let eye_x = ((signal.left_iris_x + signal.right_iris_x) / 2.0).clamp(0.0, 1.0);
    let eye_y = ((signal.left_iris_y + signal.right_iris_y) / 2.0).clamp(0.0, 1.0);

    let lighting_score = if signal.frame_brightness <= 0.0 {
        0.0
    } else if signal.frame_brightness < 35.0 {
        signal.frame_brightness / 35.0
    } else if signal.frame_brightness > 235.0 {
        ((255.0 - signal.frame_brightness) / 20.0).clamp(0.0, 1.0)
    } else {
        1.0
    };

    let head_motion_score = 1.0
        - (signal
            .head_yaw
            .abs()
            .max(signal.head_pitch.abs())
            .max(signal.head_roll.abs())
            / 1.2)
            .clamp(0.0, 1.0);
    let head_stable = head_motion_score >= 0.35;

    let signal_confidence = (signal.face_confidence.clamp(0.0, 1.0) * 0.30)
        + (signal.landmark_confidence.clamp(0.0, 1.0) * 0.30)
        + (openness_score * 0.20)
        + (lighting_score * 0.10)
        + (head_motion_score * 0.10);

    let usable = signal_confidence >= 0.45 && openness_score >= 0.18 && head_stable;

    let (attention_level, reason) = if signal.face_confidence < 0.35 {
        ("medium_attention_required", "face signal is weak")
    } else if signal.landmark_confidence < 0.35 {
        ("medium_attention_required", "eye landmarks are not clear")
    } else if openness_score < 0.18 {
        ("medium_attention_required", "eyes are not clearly visible")
    } else if !head_stable {
        (
            "medium_attention_required",
            "head position is not stable enough for reliable eye analysis",
        )
    } else if !usable {
        (
            "medium_attention_required",
            "eye signal needs better camera quality",
        )
    } else {
        ("normal", "eye signal is usable")
    };

    EyeIntelligenceResult {
        usable,
        eye_x,
        eye_y,
        openness_score,
        signal_confidence: signal_confidence.clamp(0.0, 1.0),
        head_stable,
        attention_level: attention_level.to_string(),
        reason: reason.to_string(),
    }
}

#[frb(sync)]
pub fn describe_eye_zone_for_student(zone: String) -> String {
    match zone.as_str() {
        "air_board" => {
            "Your rough-work board is active. Please continue solving inside the exam screen."
                .to_string()
        }
        "question_area" => "Please continue reading the question carefully.".to_string(),
        "answer_area" => "Please continue your answer inside the exam screen.".to_string(),
        "downward_gaze" => "Please keep your work inside the exam screen.".to_string(),
        "camera_not_reliable" => "Please make sure your face is clearly visible.".to_string(),
        _ => "Please continue your exam carefully.".to_string(),
    }
}

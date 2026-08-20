use flutter_rust_bridge::frb;
use serde::{Deserialize, Serialize};

#[frb]
#[derive(Clone, Debug, Serialize, Deserialize, PartialEq)]
pub struct GazeCalibrationSample {
    pub zone: String,
    pub eye_x: f32,
    pub eye_y: f32,
    pub head_yaw: f32,
    pub head_pitch: f32,
    pub head_roll: f32,
    pub confidence: f32,
    pub timestamp_ms: i64,
}

#[frb]
#[derive(Clone, Debug, Serialize, Deserialize, PartialEq)]
pub struct GazeCalibrationProfile {
    pub usable: bool,
    pub sample_count: i32,
    pub zones: Vec<String>,
    pub center_eye_x: f32,
    pub center_eye_y: f32,
    pub yaw_bias: f32,
    pub pitch_bias: f32,
    pub quality_score: f32,
    pub reason: String,
}

#[frb]
#[derive(Clone, Debug, Serialize, Deserialize, PartialEq)]
pub struct GazeZonePrediction {
    pub zone: String,
    pub confidence: f32,
    pub calibrated: bool,
    pub attention_level: String,
    pub reason: String,
}

#[frb(sync)]
pub fn build_gaze_calibration_profile(
    samples: Vec<GazeCalibrationSample>,
) -> GazeCalibrationProfile {
    let usable_samples: Vec<GazeCalibrationSample> = samples
        .into_iter()
        .filter(|sample| sample.confidence >= 0.45 && !sample.zone.trim().is_empty())
        .collect();

    let sample_count = usable_samples.len() as i32;
    if sample_count < 4 {
        return GazeCalibrationProfile {
            usable: false,
            sample_count,
            zones: unique_zones(&usable_samples),
            center_eye_x: 0.5,
            center_eye_y: 0.5,
            yaw_bias: 0.0,
            pitch_bias: 0.0,
            quality_score: 0.0,
            reason: "not enough reliable calibration samples".to_string(),
        };
    }

    let center_samples: Vec<&GazeCalibrationSample> = usable_samples
        .iter()
        .filter(|sample| sample.zone == "camera" || sample.zone == "answer_area")
        .collect();
    let anchor_samples: Vec<&GazeCalibrationSample> = if center_samples.is_empty() {
        usable_samples.iter().collect()
    } else {
        center_samples
    };

    let divisor = anchor_samples.len().max(1) as f32;
    let center_eye_x = anchor_samples
        .iter()
        .map(|sample| sample.eye_x)
        .sum::<f32>()
        / divisor;
    let center_eye_y = anchor_samples
        .iter()
        .map(|sample| sample.eye_y)
        .sum::<f32>()
        / divisor;
    let yaw_bias = anchor_samples
        .iter()
        .map(|sample| sample.head_yaw)
        .sum::<f32>()
        / divisor;
    let pitch_bias = anchor_samples
        .iter()
        .map(|sample| sample.head_pitch)
        .sum::<f32>()
        / divisor;
    let average_confidence = usable_samples
        .iter()
        .map(|sample| sample.confidence)
        .sum::<f32>()
        / sample_count as f32;
    let zone_count = unique_zones(&usable_samples).len() as f32;
    let quality_score =
        ((average_confidence * 0.7) + (zone_count.min(7.0) / 7.0 * 0.3)).clamp(0.0, 1.0);

    GazeCalibrationProfile {
        usable: quality_score >= 0.55,
        sample_count,
        zones: unique_zones(&usable_samples),
        center_eye_x,
        center_eye_y,
        yaw_bias,
        pitch_bias,
        quality_score,
        reason: if quality_score >= 0.55 {
            "gaze calibration is usable".to_string()
        } else {
            "gaze calibration quality is low".to_string()
        },
    }
}

#[frb(sync)]
pub fn predict_calibrated_gaze_zone(
    profile: GazeCalibrationProfile,
    eye_x: f32,
    eye_y: f32,
    head_yaw: f32,
    head_pitch: f32,
    signal_confidence: f32,
) -> GazeZonePrediction {
    if !profile.usable || signal_confidence < 0.35 {
        return GazeZonePrediction {
            zone: "camera_not_reliable".to_string(),
            confidence: signal_confidence.clamp(0.0, 1.0),
            calibrated: profile.usable,
            attention_level: "medium_attention_required".to_string(),
            reason: "gaze signal is not reliable enough".to_string(),
        };
    }

    let dx = eye_x - profile.center_eye_x;
    let dy = eye_y - profile.center_eye_y;
    let yaw_delta = head_yaw - profile.yaw_bias;
    let pitch_delta = head_pitch - profile.pitch_bias;

    let horizontal = dx + yaw_delta * 0.35;
    let vertical = dy + pitch_delta * 0.35;

    let zone = if vertical > 0.28 {
        "downward_gaze"
    } else if horizontal < -0.25 {
        "question_area"
    } else if horizontal > 0.25 {
        "air_board"
    } else if vertical < -0.22 {
        "top_screen_area"
    } else {
        "answer_area"
    };

    let distance = horizontal.abs().max(vertical.abs()).min(1.0);
    let confidence = (signal_confidence * 0.75 + distance * 0.25).clamp(0.0, 1.0);

    GazeZonePrediction {
        zone: zone.to_string(),
        confidence,
        calibrated: true,
        attention_level: "normal".to_string(),
        reason: "gaze zone predicted from personal calibration".to_string(),
    }
}

fn unique_zones(samples: &[GazeCalibrationSample]) -> Vec<String> {
    let mut zones = Vec::new();
    for sample in samples {
        if !zones.contains(&sample.zone) {
            zones.push(sample.zone.clone());
        }
    }
    zones
}

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

#[frb]
#[derive(Clone, Debug, Serialize, Deserialize, PartialEq)]
pub struct GazeCalibrationZoneV2 {
    pub name: String,
    pub sample_count: i32,
    pub eye_x: f32,
    pub eye_y: f32,
    pub yaw: f32,
    pub pitch: f32,
    pub eye_x_stddev: f32,
    pub eye_y_stddev: f32,
}

#[frb]
#[derive(Clone, Debug, Serialize, Deserialize, PartialEq)]
pub struct GazeCalibrationProfileV2 {
    pub profile_version: i32,
    pub usable: bool,
    pub student_id: String,
    pub device_id: String,
    pub exam_id: String,
    pub attempt_id: String,
    pub camera_id: String,
    pub screen_width: i32,
    pub screen_height: i32,
    pub display_scale: f32,
    pub model_id: String,
    pub model_sha256: String,
    pub created_at_ms: i64,
    pub expires_at_ms: i64,
    pub sample_count: i32,
    pub center_eye_x: f32,
    pub center_eye_y: f32,
    pub yaw_bias: f32,
    pub pitch_bias: f32,
    pub roll_bias: f32,
    pub horizontal_stddev: f32,
    pub vertical_stddev: f32,
    pub yaw_stddev: f32,
    pub pitch_stddev: f32,
    pub quality_score: f32,
    pub zones: Vec<GazeCalibrationZoneV2>,
    pub reason: String,
}

#[frb]
#[derive(Clone, Debug, Serialize, Deserialize, PartialEq)]
pub struct GazeZonePredictionV2 {
    pub zone: String,
    pub confidence: f32,
    pub calibrated: bool,
    pub actionable: bool,
    pub deviation_score: f32,
    pub attention_level: String,
    pub reason: String,
}

#[frb(sync)]
#[allow(clippy::too_many_arguments)]
pub fn build_gaze_calibration_profile_v2(
    samples: Vec<GazeCalibrationSample>,
    student_id: String,
    device_id: String,
    exam_id: String,
    attempt_id: String,
    camera_id: String,
    screen_width: i32,
    screen_height: i32,
    display_scale: f32,
    model_id: String,
    model_sha256: String,
    created_at_ms: i64,
    expires_at_ms: i64,
) -> GazeCalibrationProfileV2 {
    const REQUIRED_ZONES: [&str; 5] = [
        "camera",
        "question_area",
        "answer_area",
        "air_board",
        "top_screen_area",
    ];
    let identity_valid = !student_id.trim().is_empty()
        && !device_id.trim().is_empty()
        && !exam_id.trim().is_empty()
        && !attempt_id.trim().is_empty()
        && !camera_id.trim().is_empty()
        && !model_id.trim().is_empty()
        && model_sha256.len() == 64
        && model_sha256.chars().all(|value| value.is_ascii_hexdigit())
        && screen_width > 0
        && screen_height > 0
        && display_scale > 0.0
        && expires_at_ms > created_at_ms;
    let usable_samples: Vec<GazeCalibrationSample> = samples
        .into_iter()
        .filter(|sample| {
            sample.confidence >= 0.65
                && sample.eye_x.is_finite()
                && sample.eye_y.is_finite()
                && sample.head_yaw.is_finite()
                && sample.head_pitch.is_finite()
                && sample.head_roll.is_finite()
                && REQUIRED_ZONES.contains(&sample.zone.as_str())
        })
        .collect();
    let mut zones = Vec::new();
    for name in REQUIRED_ZONES {
        let members: Vec<&GazeCalibrationSample> = usable_samples
            .iter()
            .filter(|sample| sample.zone == name)
            .collect();
        if members.is_empty() {
            continue;
        }
        let eye_x = mean(members.iter().map(|sample| sample.eye_x));
        let eye_y = mean(members.iter().map(|sample| sample.eye_y));
        zones.push(GazeCalibrationZoneV2 {
            name: name.to_string(),
            sample_count: members.len() as i32,
            eye_x,
            eye_y,
            yaw: mean(members.iter().map(|sample| sample.head_yaw)),
            pitch: mean(members.iter().map(|sample| sample.head_pitch)),
            eye_x_stddev: stddev(members.iter().map(|sample| sample.eye_x), eye_x).max(0.025),
            eye_y_stddev: stddev(members.iter().map(|sample| sample.eye_y), eye_y).max(0.025),
        });
    }
    let center: Vec<&GazeCalibrationSample> = usable_samples
        .iter()
        .filter(|sample| sample.zone == "camera" || sample.zone == "answer_area")
        .collect();
    let center_eye_x = mean(center.iter().map(|sample| sample.eye_x));
    let center_eye_y = mean(center.iter().map(|sample| sample.eye_y));
    let yaw_bias = mean(center.iter().map(|sample| sample.head_yaw));
    let pitch_bias = mean(center.iter().map(|sample| sample.head_pitch));
    let roll_bias = mean(center.iter().map(|sample| sample.head_roll));
    let horizontal_stddev =
        stddev(center.iter().map(|sample| sample.eye_x), center_eye_x).max(0.025);
    let vertical_stddev = stddev(center.iter().map(|sample| sample.eye_y), center_eye_y).max(0.025);
    let yaw_stddev = stddev(center.iter().map(|sample| sample.head_yaw), yaw_bias).max(0.04);
    let pitch_stddev = stddev(center.iter().map(|sample| sample.head_pitch), pitch_bias).max(0.04);
    let complete_zones = zones.iter().filter(|zone| zone.sample_count >= 3).count();
    let average_confidence = mean(usable_samples.iter().map(|sample| sample.confidence));
    let stability = (1.0
        - ((horizontal_stddev + vertical_stddev + yaw_stddev + pitch_stddev) / 4.0))
        .clamp(0.0, 1.0);
    let coverage = complete_zones as f32 / REQUIRED_ZONES.len() as f32;
    let quality_score =
        (average_confidence * 0.55 + coverage * 0.25 + stability * 0.20).clamp(0.0, 1.0);
    let usable = identity_valid
        && complete_zones == REQUIRED_ZONES.len()
        && usable_samples.len() >= REQUIRED_ZONES.len() * 3
        && quality_score >= 0.68;
    GazeCalibrationProfileV2 {
        profile_version: 2,
        usable,
        student_id,
        device_id,
        exam_id,
        attempt_id,
        camera_id,
        screen_width,
        screen_height,
        display_scale,
        model_id,
        model_sha256: model_sha256.to_ascii_lowercase(),
        created_at_ms,
        expires_at_ms,
        sample_count: usable_samples.len() as i32,
        center_eye_x,
        center_eye_y,
        yaw_bias,
        pitch_bias,
        roll_bias,
        horizontal_stddev,
        vertical_stddev,
        yaw_stddev,
        pitch_stddev,
        quality_score,
        zones,
        reason: if usable {
            "multi-target gaze calibration profile is usable"
        } else if !identity_valid {
            "calibration profile binding is invalid"
        } else {
            "calibration needs at least three reliable samples for every target"
        }
        .to_string(),
    }
}

#[frb(sync)]
pub fn predict_calibrated_gaze_zone_v2(
    profile: GazeCalibrationProfileV2,
    eye_x: f32,
    eye_y: f32,
    head_yaw: f32,
    head_pitch: f32,
    signal_confidence: f32,
    now_ms: i64,
) -> GazeZonePredictionV2 {
    if !profile.usable || now_ms >= profile.expires_at_ms || signal_confidence < 0.55 {
        return GazeZonePredictionV2 {
            zone: "camera_not_reliable".into(),
            confidence: signal_confidence.clamp(0.0, 1.0),
            calibrated: profile.usable && now_ms < profile.expires_at_ms,
            actionable: false,
            deviation_score: 0.0,
            attention_level: "normal".into(),
            reason: "calibration or live gaze signal is not reliable enough".into(),
        };
    }
    let mut nearest: Option<(&GazeCalibrationZoneV2, f32)> = None;
    for zone in &profile.zones {
        let eye_dx = (eye_x - zone.eye_x) / zone.eye_x_stddev.max(0.025);
        let eye_dy = (eye_y - zone.eye_y) / zone.eye_y_stddev.max(0.025);
        let yaw = (head_yaw - zone.yaw) / profile.yaw_stddev.max(0.04);
        let pitch = (head_pitch - zone.pitch) / profile.pitch_stddev.max(0.04);
        let distance =
            (eye_dx * eye_dx + eye_dy * eye_dy + yaw * yaw * 0.35 + pitch * pitch * 0.35).sqrt();
        if nearest.is_none_or(|(_, best)| distance < best) {
            nearest = Some((zone, distance));
        }
    }
    let (zone, nearest_distance) = nearest.expect("usable profiles contain zones");
    let center_dx = (eye_x - profile.center_eye_x) / profile.horizontal_stddev.max(0.025);
    let center_dy = (eye_y - profile.center_eye_y) / profile.vertical_stddev.max(0.025);
    let center_yaw = (head_yaw - profile.yaw_bias) / profile.yaw_stddev.max(0.04);
    let center_pitch = (head_pitch - profile.pitch_bias) / profile.pitch_stddev.max(0.04);
    let deviation_score = center_dx
        .abs()
        .max(center_dy.abs())
        .max(center_yaw.abs() * 0.7)
        .max(center_pitch.abs() * 0.7);
    let recognized = nearest_distance <= 5.0;
    let actionable = signal_confidence >= 0.72 && profile.quality_score >= 0.68;
    GazeZonePredictionV2 {
        zone: if recognized {
            zone.name.clone()
        } else {
            "outside_calibrated_screen".into()
        },
        confidence: (signal_confidence * (1.0 - (nearest_distance / 10.0).min(0.7)))
            .clamp(0.0, 1.0),
        calibrated: true,
        actionable,
        deviation_score,
        attention_level: if actionable && deviation_score >= 3.0 {
            "medium_attention_required"
        } else {
            "normal"
        }
        .into(),
        reason: "gaze zone compared with personal multi-target variance profile".into(),
    }
}

fn mean(values: impl Iterator<Item = f32>) -> f32 {
    let collected: Vec<f32> = values.collect();
    if collected.is_empty() {
        0.0
    } else {
        collected.iter().sum::<f32>() / collected.len() as f32
    }
}

fn stddev(values: impl Iterator<Item = f32>, average: f32) -> f32 {
    let collected: Vec<f32> = values.collect();
    if collected.len() < 2 {
        return 0.0;
    }
    (collected
        .iter()
        .map(|value| (value - average).powi(2))
        .sum::<f32>()
        / collected.len() as f32)
        .sqrt()
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

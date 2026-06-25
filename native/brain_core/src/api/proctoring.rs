use std::collections::BTreeSet;
use std::io::Cursor;
use std::sync::{Arc, Mutex};

use flutter_rust_bridge::frb;
use once_cell::sync::Lazy;
use serde::Deserialize;
use tract_onnx::prelude::*;

#[frb]
#[derive(Clone, Debug)]
pub struct AcousticSampleDecision {
    pub updated_loss_streak: u32,
    pub should_trigger_scan: bool,
    pub normalized_tether_signal: f64,
}

#[frb]
#[derive(Clone, Debug)]
pub struct AcousticAnalysisDecision {
    pub dbfs: f64,
    pub updated_loss_streak: u32,
    pub should_trigger_scan: bool,
    pub normalized_tether_signal: f64,
    pub updated_speech_streak: u32,
    pub should_trigger_speech: bool,
    pub updated_last_speech_strike_at_ms: i64,
}

#[frb]
#[derive(Clone, Debug)]
pub struct MotionAnalysisDecision {
    pub moved: bool,
    pub should_log_violation: bool,
    pub should_trigger_scan: bool,
    pub updated_last_violation_at_ms: i64,
    pub updated_window_start_ms: i64,
    pub updated_burst_count: u32,
}

#[frb]
#[derive(Clone, Debug)]
pub struct RotationAnalysisDecision {
    pub updated_accumulated: f64,
    pub updated_progress: f64,
    pub rotation_confirmed: bool,
}

#[frb]
#[derive(Clone, Debug)]
pub struct FaceAnalysisDecision {
    pub should_flag_multi_face: bool,
    pub should_warn_gaze: bool,
    pub updated_last_multi_face_strike_at_ms: i64,
    pub updated_last_gaze_warning_at_ms: i64,
    pub updated_gaze_away_started_at_ms: Option<i64>,
}

#[frb]
#[derive(Clone, Debug)]
pub struct EnvironmentFrameDecision {
    pub normalized_lighting_score: f64,
    pub rotation_confirmed: bool,
    pub forbidden_objects: Vec<String>,
}

#[frb]
#[derive(Clone, Debug)]
pub struct ScanFrameDecision {
    pub lighting_score: f64,
    pub object_labels: Vec<String>,
    pub face_count: u32,
    pub estimated_yaw: f64,
    pub estimated_pitch: f64,
}

#[frb]
#[derive(Clone, Debug)]
pub struct GazeHeadPoseDecision {
    pub gaze_x: f64,
    pub gaze_y: f64,
    pub gaze_z: f64,
    pub yaw_proxy: f64,
    pub pitch_proxy: f64,
    pub roll_proxy: f64,
    pub confidence: f64,
    pub stable_head_pose: bool,
    pub looking_away: bool,
    pub label: String,
}

#[frb]
#[derive(Clone, Debug)]
pub struct VisionModelStatus {
    pub loaded: bool,
    pub model_name: String,
    pub input_width: u32,
    pub input_height: u32,
    pub confidence_threshold: f64,
    pub label_count: u32,
    pub message: String,
}

#[derive(Clone, Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct VisionModelManifest {
    model_name: Option<String>,
    input_width: usize,
    input_height: usize,
    output_labels: Vec<String>,
    confidence_threshold: Option<f32>,
    input_channels: Option<usize>,
}

type VisionPlan = Arc<TypedRunnableModel>;

#[derive(Debug)]
struct VisionRuntime {
    manifest: VisionModelManifest,
    model: VisionPlan,
}

static VISION_RUNTIME: Lazy<Mutex<Option<VisionRuntime>>> = Lazy::new(|| Mutex::new(None));

#[frb(sync)]
pub fn process_acoustic_sample(
    dbfs: f64,
    loss_threshold_dbfs: f64,
    loss_streak: u32,
    loss_samples_to_trigger: u32,
) -> AcousticSampleDecision {
    let below_threshold = dbfs <= loss_threshold_dbfs;
    let updated_loss_streak = if below_threshold {
        loss_streak.saturating_add(1)
    } else {
        0
    };
    let should_trigger_scan =
        loss_samples_to_trigger > 0 && updated_loss_streak >= loss_samples_to_trigger;

    AcousticSampleDecision {
        updated_loss_streak,
        should_trigger_scan,
        normalized_tether_signal: normalize_signal_from_dbfs(dbfs),
    }
}

#[frb(sync)]
pub fn analyze_acoustic_chunk(
    pcm16_bytes: Vec<u8>,
    loss_threshold_dbfs: f64,
    loss_streak: u32,
    loss_samples_to_trigger: u32,
    speech_threshold_dbfs: f64,
    speech_streak: u32,
    speech_samples_to_trigger: u32,
    last_speech_strike_at_ms: i64,
    speech_cooldown_ms: i64,
    now_ms: i64,
) -> AcousticAnalysisDecision {
    let dbfs = pcm16le_rms_dbfs(&pcm16_bytes);

    let below_threshold = dbfs <= loss_threshold_dbfs;
    let updated_loss_streak = if below_threshold {
        loss_streak.saturating_add(1)
    } else {
        0
    };
    let should_trigger_scan =
        loss_samples_to_trigger > 0 && updated_loss_streak >= loss_samples_to_trigger;

    let speech_detected = dbfs > speech_threshold_dbfs;
    let next_speech_streak = if speech_detected {
        speech_streak.saturating_add(1)
    } else {
        0
    };

    let speech_ready =
        speech_samples_to_trigger > 0 && next_speech_streak >= speech_samples_to_trigger;
    let speech_off_cooldown = now_ms.saturating_sub(last_speech_strike_at_ms) >= speech_cooldown_ms;
    let should_trigger_speech = speech_ready && speech_off_cooldown;
    let updated_last_speech_strike_at_ms = if should_trigger_speech {
        now_ms
    } else {
        last_speech_strike_at_ms
    };
    let updated_speech_streak = if should_trigger_speech {
        0
    } else {
        next_speech_streak
    };

    AcousticAnalysisDecision {
        dbfs,
        updated_loss_streak,
        should_trigger_scan,
        normalized_tether_signal: normalize_signal_from_dbfs(dbfs),
        updated_speech_streak,
        should_trigger_speech,
        updated_last_speech_strike_at_ms,
    }
}

#[frb(sync)]
pub fn analyze_motion_sample(
    x: f64,
    y: f64,
    z: f64,
    x_threshold: f64,
    y_threshold: f64,
    z_threshold: f64,
    now_ms: i64,
    last_violation_at_ms: i64,
    cooldown_ms: i64,
    window_start_ms: i64,
    window_ms: i64,
    burst_count: u32,
    burst_threshold: u32,
) -> MotionAnalysisDecision {
    let moved = x.abs() > x_threshold || y.abs() > y_threshold || z.abs() < z_threshold;
    if !moved {
        return MotionAnalysisDecision {
            moved,
            should_log_violation: false,
            should_trigger_scan: false,
            updated_last_violation_at_ms: last_violation_at_ms,
            updated_window_start_ms: window_start_ms,
            updated_burst_count: burst_count,
        };
    }

    if now_ms.saturating_sub(last_violation_at_ms) < cooldown_ms {
        return MotionAnalysisDecision {
            moved,
            should_log_violation: false,
            should_trigger_scan: false,
            updated_last_violation_at_ms: last_violation_at_ms,
            updated_window_start_ms: window_start_ms,
            updated_burst_count: burst_count,
        };
    }

    let mut updated_window_start_ms = window_start_ms;
    let mut updated_burst_count = burst_count;
    let mut should_trigger_scan = false;

    if burst_threshold > 0 {
        if now_ms.saturating_sub(window_start_ms) > window_ms {
            updated_window_start_ms = now_ms;
            updated_burst_count = 1;
        } else {
            updated_burst_count = updated_burst_count.saturating_add(1);
        }

        if updated_burst_count >= burst_threshold {
            should_trigger_scan = true;
            updated_burst_count = 0;
            updated_window_start_ms = now_ms;
        }
    }

    MotionAnalysisDecision {
        moved,
        should_log_violation: true,
        should_trigger_scan,
        updated_last_violation_at_ms: now_ms,
        updated_window_start_ms,
        updated_burst_count,
    }
}

#[frb(sync)]
pub fn update_rotation_progress(
    x: f64,
    y: f64,
    z: f64,
    accumulated: f64,
    current_progress: f64,
    delta_scale: f64,
    min_delta: f64,
    target_accumulated: f64,
) -> RotationAnalysisDecision {
    let delta = (x.abs() + y.abs() + z.abs()) * delta_scale;
    if delta <= min_delta {
        return RotationAnalysisDecision {
            updated_accumulated: accumulated,
            updated_progress: current_progress,
            rotation_confirmed: current_progress >= 1.0,
        };
    }

    let updated_accumulated = accumulated + delta;
    let computed_progress = if target_accumulated <= 0.0 {
        1.0
    } else {
        (updated_accumulated / target_accumulated).clamp(0.0, 1.0)
    };
    let updated_progress = computed_progress.max(current_progress);

    RotationAnalysisDecision {
        updated_accumulated,
        updated_progress,
        rotation_confirmed: updated_progress >= 1.0,
    }
}

#[frb(sync)]
pub fn analyze_face_state(
    face_count: u32,
    include_gaze: bool,
    yaw: f64,
    pitch: f64,
    now_ms: i64,
    last_multi_face_strike_at_ms: i64,
    multi_face_cooldown_ms: i64,
    gaze_away_started_at_ms: Option<i64>,
    gaze_away_duration_ms: i64,
    last_gaze_warning_at_ms: i64,
    gaze_warning_cooldown_ms: i64,
    yaw_threshold: f64,
    pitch_threshold: f64,
) -> FaceAnalysisDecision {
    let should_flag_multi_face = face_count > 1
        && now_ms.saturating_sub(last_multi_face_strike_at_ms) >= multi_face_cooldown_ms;
    let updated_last_multi_face_strike_at_ms = if should_flag_multi_face {
        now_ms
    } else {
        last_multi_face_strike_at_ms
    };

    let mut should_warn_gaze = false;
    let mut updated_last_gaze_warning_at_ms = last_gaze_warning_at_ms;
    let mut updated_gaze_away_started_at_ms;

    if include_gaze {
        let gaze_away = yaw.abs() > yaw_threshold || pitch.abs() > pitch_threshold;
        if gaze_away {
            let away_started = gaze_away_started_at_ms.unwrap_or(now_ms);
            updated_gaze_away_started_at_ms = Some(away_started);

            let duration_elapsed = now_ms.saturating_sub(away_started) >= gaze_away_duration_ms;
            let warning_off_cooldown =
                now_ms.saturating_sub(last_gaze_warning_at_ms) >= gaze_warning_cooldown_ms;

            if duration_elapsed && warning_off_cooldown {
                should_warn_gaze = true;
                updated_last_gaze_warning_at_ms = now_ms;
                updated_gaze_away_started_at_ms = Some(now_ms);
            }
        } else {
            updated_gaze_away_started_at_ms = None;
        }
    } else {
        updated_gaze_away_started_at_ms = gaze_away_started_at_ms;
    }

    FaceAnalysisDecision {
        should_flag_multi_face,
        should_warn_gaze,
        updated_last_multi_face_strike_at_ms,
        updated_last_gaze_warning_at_ms,
        updated_gaze_away_started_at_ms,
    }
}

#[frb(sync)]
pub fn analyze_environment_frame(
    object_labels: Vec<String>,
    lighting_score: f64,
    rotation_covered: bool,
    forbidden_keywords: Vec<String>,
) -> EnvironmentFrameDecision {
    let forbidden_patterns = forbidden_keywords
        .into_iter()
        .map(|keyword| normalize_label(&keyword))
        .filter(|keyword| !keyword.is_empty())
        .collect::<Vec<_>>();

    let forbidden_objects = object_labels
        .into_iter()
        .map(|label| normalize_label(&label))
        .filter(|label| !label.is_empty())
        .filter(|label| {
            forbidden_patterns
                .iter()
                .any(|keyword| label.contains(keyword))
        })
        .collect::<BTreeSet<_>>()
        .into_iter()
        .collect::<Vec<_>>();

    EnvironmentFrameDecision {
        normalized_lighting_score: lighting_score.clamp(0.0, 1.0),
        rotation_confirmed: rotation_covered,
        forbidden_objects,
    }
}

#[frb(sync)]
pub fn estimate_lighting_from_luma(luma_bytes: Vec<u8>, sample_stride: u32) -> f64 {
    if luma_bytes.is_empty() {
        return 0.0;
    }

    let stride = sample_stride.max(1) as usize;
    let mut total = 0u64;
    let mut count = 0u64;

    for index in (0..luma_bytes.len()).step_by(stride) {
        total = total.saturating_add(luma_bytes[index] as u64);
        count = count.saturating_add(1);
    }

    if count == 0 {
        return 0.0;
    }

    ((total as f64 / count as f64) / 255.0).clamp(0.0, 1.0)
}

#[frb(sync)]
pub fn analyze_gaze_head_pose_frame(
    plane0_bytes: Vec<u8>,
    width: u32,
    height: u32,
    bytes_per_row: u32,
    previous_yaw: f64,
    previous_pitch: f64,
    previous_roll: f64,
) -> Option<GazeHeadPoseDecision> {
    if plane0_bytes.is_empty() || width == 0 || height == 0 || bytes_per_row == 0 {
        return None;
    }

    let width = width as usize;
    let height = height as usize;
    let row_stride = bytes_per_row as usize;
    let step_x = (width / 36).max(1);
    let step_y = (height / 28).max(1);
    let center_x = width as f64 / 2.0;
    let center_y = height as f64 / 2.0;
    let radius_x = width as f64 * 0.38;
    let radius_y = height as f64 * 0.42;

    if radius_x <= 0.0 || radius_y <= 0.0 {
        return None;
    }

    let mut total = 0.0;
    let mut weighted_x = 0.0;
    let mut weighted_y = 0.0;
    let mut left = 0.0;
    let mut right = 0.0;
    let mut top = 0.0;
    let mut bottom = 0.0;
    let mut diagonal_a = 0.0;
    let mut diagonal_b = 0.0;

    for y in (0..height).step_by(step_y) {
        let dy = (y as f64 - center_y) / radius_y;
        for x in (0..width).step_by(step_x) {
            let dx = (x as f64 - center_x) / radius_x;
            if dx * dx + dy * dy > 1.0 {
                continue;
            }

            let index = y.saturating_mul(row_stride).saturating_add(x);
            let Some(byte) = plane0_bytes.get(index) else {
                continue;
            };

            let luma = *byte as f64 / 255.0;
            let weight = (1.0 - luma).clamp(0.0, 1.0) + 0.04;
            total += weight;
            weighted_x += x as f64 * weight;
            weighted_y += y as f64 * weight;
            if (x as f64) < center_x {
                left += weight;
            } else {
                right += weight;
            }
            if (y as f64) < center_y {
                top += weight;
            } else {
                bottom += weight;
            }
            if x as f64 / width as f64 > y as f64 / height as f64 {
                diagonal_a += weight;
            } else {
                diagonal_b += weight;
            }
        }
    }

    if total <= 0.001 {
        return None;
    }

    let gaze_x = ((weighted_x / total) - center_x) / center_x;
    let gaze_y = ((weighted_y / total) - center_y) / center_y;
    let yaw = ((right - left) / total).clamp(-1.0, 1.0);
    let pitch = ((bottom - top) / total).clamp(-1.0, 1.0);
    let roll = ((diagonal_a - diagonal_b) / total).clamp(-1.0, 1.0);
    let movement = ((yaw - previous_yaw).abs()
        + (pitch - previous_pitch).abs()
        + (roll - previous_roll).abs())
        / 3.0;
    let gaze_magnitude = (gaze_x * gaze_x + gaze_y * gaze_y).sqrt();
    let head_magnitude = (yaw * yaw + pitch * pitch + roll * roll).sqrt();
    let looking_away = gaze_magnitude > 0.34 || yaw.abs() > 0.30 || pitch.abs() > 0.34;
    let stable_head_pose = movement < 0.18 && head_magnitude < 0.68;
    let confidence = (0.55 + (total / 220.0).min(0.40) - movement.min(0.22)).clamp(0.0, 1.0);
    let label = if looking_away {
        "possible_looking_away"
    } else if stable_head_pose {
        "focused_forward"
    } else {
        "head_motion_detected"
    };

    Some(GazeHeadPoseDecision {
        gaze_x: gaze_x.clamp(-1.0, 1.0),
        gaze_y: gaze_y.clamp(-1.0, 1.0),
        gaze_z: 1.0,
        yaw_proxy: yaw,
        pitch_proxy: pitch,
        roll_proxy: roll,
        confidence,
        stable_head_pose,
        looking_away,
        label: label.to_string(),
    })
}

#[frb(sync)]
pub fn load_vision_model(manifest_json: String, model_bytes: Vec<u8>) -> VisionModelStatus {
    match load_vision_model_inner(manifest_json, model_bytes) {
        Ok(status) => status,
        Err(message) => VisionModelStatus {
            loaded: false,
            model_name: "unloaded".to_string(),
            input_width: 0,
            input_height: 0,
            confidence_threshold: 0.0,
            label_count: 0,
            message,
        },
    }
}

#[frb(sync)]
pub fn clear_vision_model() {
    if let Ok(mut guard) = VISION_RUNTIME.lock() {
        *guard = None;
    }
}

#[frb(sync)]
pub fn current_vision_model_status() -> VisionModelStatus {
    match VISION_RUNTIME.lock() {
        Ok(guard) => {
            if let Some(runtime) = guard.as_ref() {
                VisionModelStatus {
                    loaded: true,
                    model_name: runtime
                        .manifest
                        .model_name
                        .clone()
                        .unwrap_or_else(|| "rust-vision-model".to_string()),
                    input_width: runtime.manifest.input_width as u32,
                    input_height: runtime.manifest.input_height as u32,
                    confidence_threshold: runtime.manifest.confidence_threshold.unwrap_or(0.7)
                        as f64,
                    label_count: runtime.manifest.output_labels.len() as u32,
                    message: "loaded".to_string(),
                }
            } else {
                VisionModelStatus {
                    loaded: false,
                    model_name: "unloaded".to_string(),
                    input_width: 0,
                    input_height: 0,
                    confidence_threshold: 0.0,
                    label_count: 0,
                    message: "no model loaded".to_string(),
                }
            }
        }
        Err(_) => VisionModelStatus {
            loaded: false,
            model_name: "unloaded".to_string(),
            input_width: 0,
            input_height: 0,
            confidence_threshold: 0.0,
            label_count: 0,
            message: "vision runtime lock poisoned".to_string(),
        },
    }
}

#[frb(sync)]
pub fn analyze_scan_frame(
    plane0_bytes: Vec<u8>,
    width: u32,
    height: u32,
    bytes_per_row: u32,
    pixel_format: String,
) -> ScanFrameDecision {
    let width = width.max(1) as usize;
    let height = height.max(1) as usize;
    let row_stride = bytes_per_row.max(1) as usize;
    let luma = extract_luma_buffer(
        &plane0_bytes,
        width,
        height,
        row_stride,
        &pixel_format.to_ascii_lowercase(),
    );
    if let Ok(model_labels) = run_vision_model(&luma, width, height) {
        let lighting_score = estimate_lighting_from_luma(luma.clone(), 8);
        return ScanFrameDecision {
            lighting_score,
            object_labels: model_labels,
            face_count: 0,
            estimated_yaw: 0.0,
            estimated_pitch: 0.0,
        };
    }

    let lighting_score = estimate_lighting_from_luma(luma.clone(), 8);
    let object_labels = detect_rectangular_device_labels(&luma, width, height);

    ScanFrameDecision {
        lighting_score,
        object_labels,
        face_count: 0,
        estimated_yaw: 0.0,
        estimated_pitch: 0.0,
    }
}

fn pcm16le_rms_dbfs(bytes: &[u8]) -> f64 {
    let mut sample_count = 0usize;
    let mut sum_squares = 0.0f64;

    for chunk in bytes.chunks_exact(2) {
        let sample = i16::from_le_bytes([chunk[0], chunk[1]]) as f64 / 32768.0;
        sum_squares += sample * sample;
        sample_count += 1;
    }

    if sample_count == 0 {
        return -90.0;
    }

    let rms = (sum_squares / sample_count as f64).sqrt();
    if rms <= 1e-9 {
        -90.0
    } else {
        clamp_dbfs(20.0 * rms.log10())
    }
}

fn normalize_signal_from_dbfs(dbfs: f64) -> f64 {
    ((dbfs + 90.0) / 90.0).clamp(0.0, 1.0)
}

fn clamp_dbfs(dbfs: f64) -> f64 {
    dbfs.clamp(-90.0, 0.0)
}

fn normalize_label(label: &str) -> String {
    label
        .to_lowercase()
        .split_whitespace()
        .collect::<Vec<_>>()
        .join(" ")
}

fn is_background_label(label: &str) -> bool {
    matches!(normalize_label(label).as_str(), "" | "background" | "none")
}

fn extract_luma_buffer(
    bytes: &[u8],
    width: usize,
    height: usize,
    row_stride: usize,
    pixel_format: &str,
) -> Vec<u8> {
    match pixel_format {
        "bgra8888" => {
            let mut out = Vec::with_capacity(width * height);
            for y in 0..height {
                let row_start = y.saturating_mul(row_stride);
                for x in 0..width {
                    let pixel_start = row_start.saturating_add(x.saturating_mul(4));
                    if pixel_start + 2 >= bytes.len() {
                        out.push(0);
                        continue;
                    }

                    let b = bytes[pixel_start] as f64;
                    let g = bytes[pixel_start + 1] as f64;
                    let r = bytes[pixel_start + 2] as f64;
                    let luma = (0.114 * b + 0.587 * g + 0.299 * r)
                        .round()
                        .clamp(0.0, 255.0);
                    out.push(luma as u8);
                }
            }
            out
        }
        _ => {
            let mut out = Vec::with_capacity(width * height);
            for y in 0..height {
                let row_start = y.saturating_mul(row_stride);
                for x in 0..width {
                    let index = row_start.saturating_add(x);
                    out.push(*bytes.get(index).unwrap_or(&0));
                }
            }
            out
        }
    }
}

fn detect_rectangular_device_labels(luma: &[u8], width: usize, height: usize) -> Vec<String> {
    if luma.is_empty() || width == 0 || height == 0 {
        return Vec::new();
    }

    let sample_step = ((width.max(height) / 96).max(2)).min(8);
    let grid_w = ((width + sample_step - 1) / sample_step).max(1);
    let grid_h = ((height + sample_step - 1) / sample_step).max(1);

    let mut sampled = vec![0u8; grid_w * grid_h];
    let mut total = 0u64;
    let mut count = 0u64;
    for gy in 0..grid_h {
        for gx in 0..grid_w {
            let src_x = (gx * sample_step).min(width - 1);
            let src_y = (gy * sample_step).min(height - 1);
            let value = luma[src_y * width + src_x];
            sampled[gy * grid_w + gx] = value;
            total = total.saturating_add(value as u64);
            count = count.saturating_add(1);
        }
    }

    if count == 0 {
        return Vec::new();
    }

    let mean = total as f64 / count as f64;
    let threshold = (mean - 26.0).clamp(12.0, 170.0) as u8;
    let total_cells = (grid_w * grid_h) as f64;
    let mut visited = vec![false; sampled.len()];
    let mut labels = BTreeSet::new();

    for gy in 0..grid_h {
        for gx in 0..grid_w {
            let index = gy * grid_w + gx;
            if visited[index] || sampled[index] > threshold {
                continue;
            }

            let mut stack = vec![(gx, gy)];
            visited[index] = true;
            let mut area = 0usize;
            let mut min_x = gx;
            let mut max_x = gx;
            let mut min_y = gy;
            let mut max_y = gy;

            while let Some((cx, cy)) = stack.pop() {
                area += 1;
                min_x = min_x.min(cx);
                max_x = max_x.max(cx);
                min_y = min_y.min(cy);
                max_y = max_y.max(cy);

                let neighbors = [
                    (cx.wrapping_sub(1), cy, cx > 0),
                    (cx + 1, cy, cx + 1 < grid_w),
                    (cx, cy.wrapping_sub(1), cy > 0),
                    (cx, cy + 1, cy + 1 < grid_h),
                ];

                for (nx, ny, valid) in neighbors {
                    if !valid {
                        continue;
                    }
                    let neighbor_index = ny * grid_w + nx;
                    if visited[neighbor_index] || sampled[neighbor_index] > threshold {
                        continue;
                    }
                    visited[neighbor_index] = true;
                    stack.push((nx, ny));
                }
            }

            let bbox_w = max_x - min_x + 1;
            let bbox_h = max_y - min_y + 1;
            let bbox_area = (bbox_w * bbox_h).max(1);
            let fill_ratio = area as f64 / bbox_area as f64;
            let area_ratio = area as f64 / total_cells;
            let aspect = bbox_w as f64 / bbox_h as f64;
            let center_y_ratio = ((min_y + max_y) as f64 / 2.0) / grid_h as f64;

            if fill_ratio < 0.42 || area_ratio < 0.008 {
                continue;
            }

            if (0.35..=0.82).contains(&aspect) && area_ratio <= 0.22 {
                labels.insert("phone".to_string());
                continue;
            }

            if (1.25..=2.8).contains(&aspect) && area_ratio >= 0.035 && center_y_ratio >= 0.45 {
                labels.insert("laptop".to_string());
            }
        }
    }

    labels.into_iter().collect()
}

fn load_vision_model_inner(
    manifest_json: String,
    model_bytes: Vec<u8>,
) -> Result<VisionModelStatus, String> {
    let manifest: VisionModelManifest =
        serde_json::from_str(&manifest_json).map_err(|err| format!("invalid manifest: {err}"))?;
    if manifest.input_width == 0 || manifest.input_height == 0 {
        return Err("manifest input dimensions must be greater than zero".to_string());
    }
    if manifest.output_labels.is_empty() {
        return Err("manifest output labels must not be empty".to_string());
    }
    if model_bytes.is_empty() {
        return Err("model asset bytes are empty".to_string());
    }

    let channels = manifest.input_channels.unwrap_or(1).max(1);
    let mut cursor = Cursor::new(model_bytes);
    let model = tract_onnx::onnx()
        .model_for_read(&mut cursor)
        .map_err(|err| format!("onnx load failed: {err}"))?
        .with_input_fact(
            0,
            f32::fact([1, channels, manifest.input_height, manifest.input_width]).into(),
        )
        .map_err(|err| format!("onnx input fact failed: {err}"))?
        .into_optimized()
        .map_err(|err| format!("onnx optimize failed: {err}"))?
        .into_runnable()
        .map_err(|err| format!("onnx runnable build failed: {err}"))?;

    let status = VisionModelStatus {
        loaded: true,
        model_name: manifest
            .model_name
            .clone()
            .unwrap_or_else(|| "rust-vision-model".to_string()),
        input_width: manifest.input_width as u32,
        input_height: manifest.input_height as u32,
        confidence_threshold: manifest.confidence_threshold.unwrap_or(0.7) as f64,
        label_count: manifest.output_labels.len() as u32,
        message: "loaded".to_string(),
    };

    let runtime = VisionRuntime { manifest, model };
    let mut guard = VISION_RUNTIME
        .lock()
        .map_err(|_| "vision runtime lock poisoned".to_string())?;
    *guard = Some(runtime);
    Ok(status)
}

fn run_vision_model(luma: &[u8], width: usize, height: usize) -> Result<Vec<String>, String> {
    let guard = VISION_RUNTIME
        .lock()
        .map_err(|_| "vision runtime lock poisoned".to_string())?;
    let Some(runtime) = guard.as_ref() else {
        return Err("vision model not loaded".to_string());
    };

    let resized = resize_luma_nn(
        luma,
        width,
        height,
        runtime.manifest.input_width,
        runtime.manifest.input_height,
    );
    let channels = runtime.manifest.input_channels.unwrap_or(1).max(1);
    let input_len = runtime.manifest.input_width * runtime.manifest.input_height * channels;
    let mut input = Vec::with_capacity(input_len);

    if channels == 1 {
        input.extend(resized.iter().map(|px| *px as f32 / 255.0));
    } else {
        for px in &resized {
            let value = *px as f32 / 255.0;
            for _ in 0..channels {
                input.push(value);
            }
        }
    }

    let input_tensor = Tensor::from_shape(
        &[
            1,
            channels,
            runtime.manifest.input_height,
            runtime.manifest.input_width,
        ],
        &input,
    )
    .map_err(|err| format!("tensor build failed: {err}"))?;

    let result = runtime
        .model
        .run(tvec!(input_tensor.into()))
        .map_err(|err| format!("onnx inference failed: {err}"))?;
    if result.is_empty() {
        return Err("onnx inference returned no outputs".to_string());
    }

    let output_tensor = result[0]
        .clone()
        .into_tensor()
        .cast_to::<f32>()
        .map_err(|err| format!("onnx output cast failed: {err}"))?
        .into_owned();
    let scores = output_tensor
        .try_as_dense()
        .map_err(|err| format!("onnx output dense conversion failed: {err}"))?
        .as_slice::<f32>()
        .map_err(|err| format!("onnx output parse failed: {err}"))?
        .to_vec();
    if scores.is_empty() {
        return Err("onnx output tensor is empty".to_string());
    }

    let threshold = runtime.manifest.confidence_threshold.unwrap_or(0.7);
    let mut ranked = scores
        .iter()
        .copied()
        .enumerate()
        .filter_map(|(index, score)| {
            let label = runtime.manifest.output_labels.get(index)?;
            Some((label.clone(), score))
        })
        .collect::<Vec<_>>();
    ranked.sort_by(|a, b| b.1.total_cmp(&a.1));

    let mut labels = ranked
        .iter()
        .filter(|(label, score)| !is_background_label(label.as_str()) && *score >= threshold)
        .map(|(label, _)| label.clone())
        .collect::<Vec<_>>();

    if labels.is_empty() {
        for (label, score) in &ranked {
            if is_background_label(label.as_str()) {
                continue;
            }
            if *score >= threshold * 0.75 {
                labels.push(label.clone());
            }
            break;
        }
    }

    Ok(labels)
}

fn resize_luma_nn(
    input: &[u8],
    input_width: usize,
    input_height: usize,
    output_width: usize,
    output_height: usize,
) -> Vec<u8> {
    if input.is_empty() || input_width == 0 || input_height == 0 {
        return vec![0; output_width.saturating_mul(output_height)];
    }

    let mut out = Vec::with_capacity(output_width * output_height);
    for y in 0..output_height {
        let src_y = (y * input_height / output_height).min(input_height - 1);
        for x in 0..output_width {
            let src_x = (x * input_width / output_width).min(input_width - 1);
            out.push(input[src_y * input_width + src_x]);
        }
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    static TEST_GUARD: Lazy<Mutex<()>> = Lazy::new(|| Mutex::new(()));

    fn load_bootstrap_model() -> Option<VisionModelStatus> {
        clear_vision_model();
        let manifest =
            std::fs::read_to_string("../../assets/ml_models/vision_manifest.json").ok()?;
        let model =
            std::fs::read("../../assets/ml_models/forbidden_devices_classifier.onnx").ok()?;
        Some(load_vision_model(manifest, model))
    }

    fn make_frame_with_phone() -> Vec<u8> {
        let mut frame = vec![220u8; 128 * 128];
        for y in 16..104 {
            for x in 44..82 {
                frame[y * 128 + x] = 28;
            }
        }
        for y in 20..100 {
            for x in 48..78 {
                frame[y * 128 + x] = 112;
            }
        }
        frame
    }

    #[test]
    fn bootstrap_model_loads_from_bundled_assets() {
        let _guard = TEST_GUARD.lock().unwrap();
        let Some(status) = load_bootstrap_model() else {
            eprintln!("bootstrap vision model assets not present; skipping optional model test");
            return;
        };
        assert!(status.loaded, "{}", status.message);
        assert_eq!(status.model_name, "rust-vision-synth-bootstrap");
    }

    #[test]
    fn bootstrap_model_detects_phone_like_frame() {
        let _guard = TEST_GUARD.lock().unwrap();
        let Some(status) = load_bootstrap_model() else {
            eprintln!("bootstrap vision model assets not present; skipping optional model test");
            return;
        };
        assert!(status.loaded, "{}", status.message);

        let decision = analyze_scan_frame(make_frame_with_phone(), 128, 128, 128, "luma8".into());
        assert!(
            decision.object_labels.iter().any(|label| label == "phone"),
            "expected phone label, got {:?}",
            decision.object_labels
        );
    }
}

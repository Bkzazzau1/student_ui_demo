use std::io::Cursor;
use std::sync::{Arc, Mutex};

use flutter_rust_bridge::frb;
use once_cell::sync::Lazy;
use serde::{Deserialize, Serialize};
use tract_onnx::prelude::*;

use super::hand_gesture::{analyze_hand_landmarks, HandGestureInput, HandGestureResult, HandLandmarkPoint};

#[frb]
#[derive(Clone, Debug, Serialize, Deserialize, PartialEq)]
pub struct HandLandmarkModelStatus {
    pub loaded: bool,
    pub model_name: String,
    pub input_width: i32,
    pub input_height: i32,
    pub landmark_count: i32,
    pub message: String,
}

#[frb]
#[derive(Clone, Debug, Serialize, Deserialize, PartialEq)]
pub struct HandLandmarkInferenceResult {
    pub landmarks: Vec<HandLandmarkPoint>,
    pub gesture: HandGestureResult,
    pub usable: bool,
    pub reason: String,
}

#[derive(Clone, Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct HandLandmarkManifest {
    model_name: Option<String>,
    input_width: usize,
    input_height: usize,
    input_channels: Option<usize>,
    landmark_count: Option<usize>,
    output_layout: Option<String>,
    coordinate_mode: Option<String>,
    confidence_index: Option<usize>,
}

type LandmarkPlan = Arc<TypedRunnableModel>;

#[derive(Debug)]
struct HandLandmarkRuntime {
    manifest: HandLandmarkManifest,
    model: LandmarkPlan,
}

static HAND_LANDMARK_RUNTIME: Lazy<Mutex<Option<HandLandmarkRuntime>>> =
    Lazy::new(|| Mutex::new(None));

#[frb(sync)]
pub fn load_hand_landmark_model(
    manifest_json: String,
    model_bytes: Vec<u8>,
) -> HandLandmarkModelStatus {
    match load_model_inner(manifest_json, model_bytes) {
        Ok(status) => status,
        Err(message) => HandLandmarkModelStatus {
            loaded: false,
            model_name: "unloaded".to_string(),
            input_width: 0,
            input_height: 0,
            landmark_count: 0,
            message,
        },
    }
}

#[frb(sync)]
pub fn clear_hand_landmark_model() {
    if let Ok(mut guard) = HAND_LANDMARK_RUNTIME.lock() {
        *guard = None;
    }
}

#[frb(sync)]
pub fn current_hand_landmark_model_status() -> HandLandmarkModelStatus {
    match HAND_LANDMARK_RUNTIME.lock() {
        Ok(guard) => match guard.as_ref() {
            Some(runtime) => status_from_manifest(&runtime.manifest, "loaded"),
            None => unloaded_status("no hand landmark model loaded"),
        },
        Err(_) => unloaded_status("hand landmark runtime lock poisoned"),
    }
}

#[frb(sync)]
pub fn analyze_hand_landmark_rgb_crop(
    rgb_bytes: Vec<u8>,
    crop_width: i32,
    crop_height: i32,
    mirrored: bool,
    timestamp_ms: i64,
) -> HandLandmarkInferenceResult {
    if crop_width <= 0 || crop_height <= 0 {
        return unusable_result("invalid hand crop dimensions");
    }

    match run_landmark_model(&rgb_bytes, crop_width as usize, crop_height as usize) {
        Ok((output, manifest)) => decode_landmark_output(
            output,
            manifest.landmark_count.unwrap_or(21),
            manifest
                .output_layout
                .unwrap_or_else(|| "flat_xyz".to_string()),
            manifest
                .coordinate_mode
                .unwrap_or_else(|| "normalized".to_string()),
            manifest.confidence_index,
            crop_width,
            crop_height,
            mirrored,
            timestamp_ms,
        ),
        Err(message) => unusable_result(&message),
    }
}

#[frb(sync)]
pub fn review_hand_landmark_output(
    output: Vec<f32>,
    landmark_count: i32,
    output_layout: String,
    coordinate_mode: String,
    confidence_index: Option<i32>,
    frame_width: i32,
    frame_height: i32,
    mirrored: bool,
    timestamp_ms: i64,
) -> HandLandmarkInferenceResult {
    decode_landmark_output(
        output,
        landmark_count.max(1) as usize,
        output_layout,
        coordinate_mode,
        confidence_index.map(|value| value.max(0) as usize),
        frame_width,
        frame_height,
        mirrored,
        timestamp_ms,
    )
}

fn decode_landmark_output(
    output: Vec<f32>,
    landmark_count: usize,
    output_layout: String,
    coordinate_mode: String,
    confidence_index: Option<usize>,
    frame_width: i32,
    frame_height: i32,
    mirrored: bool,
    timestamp_ms: i64,
) -> HandLandmarkInferenceResult {
    if landmark_count < 21 || frame_width <= 0 || frame_height <= 0 {
        return unusable_result("hand landmark output configuration is invalid");
    }

    let layout = output_layout.trim().to_ascii_lowercase();
    let coordinate_mode = coordinate_mode.trim().to_ascii_lowercase();
    let values_per_landmark = if layout.contains("xyzc") { 4 } else { 3 };
    let required = landmark_count.saturating_mul(values_per_landmark);
    if output.len() < required {
        return unusable_result("hand landmark model output does not contain enough values");
    }

    let global_confidence = confidence_index
        .and_then(|index| output.get(index).copied())
        .unwrap_or(0.85)
        .clamp(0.0, 1.0);

    let mut landmarks = Vec::with_capacity(21);
    for index in 0..21usize {
        let base = index.saturating_mul(values_per_landmark);
        let mut x = output[base];
        let mut y = output[base + 1];
        let z = output[base + 2];
        let confidence = if values_per_landmark == 4 {
            output[base + 3].clamp(0.0, 1.0)
        } else {
            global_confidence
        };

        if coordinate_mode == "pixels" || coordinate_mode == "pixel" {
            x /= frame_width as f32;
            y /= frame_height as f32;
        }

        landmarks.push(HandLandmarkPoint {
            index: index as i32,
            x: x.clamp(0.0, 1.0),
            y: y.clamp(0.0, 1.0),
            z,
            confidence,
        });
    }

    let gesture = analyze_hand_landmarks(HandGestureInput {
        landmarks: landmarks.clone(),
        frame_width,
        frame_height,
        mirrored,
        timestamp_ms,
    });

    HandLandmarkInferenceResult {
        usable: gesture.usable,
        reason: if gesture.usable {
            "hand landmarks and gesture were analyzed locally".to_string()
        } else {
            gesture.reason.clone()
        },
        landmarks,
        gesture,
    }
}

fn load_model_inner(
    manifest_json: String,
    model_bytes: Vec<u8>,
) -> Result<HandLandmarkModelStatus, String> {
    let manifest: HandLandmarkManifest = serde_json::from_str(&manifest_json)
        .map_err(|error| format!("invalid hand landmark manifest: {error}"))?;

    if manifest.input_width == 0 || manifest.input_height == 0 {
        return Err("hand landmark model input dimensions must be greater than zero".to_string());
    }
    if manifest.landmark_count.unwrap_or(21) < 21 {
        return Err("hand landmark model must provide at least 21 landmarks".to_string());
    }
    if model_bytes.is_empty() {
        return Err("hand landmark model asset bytes are empty".to_string());
    }

    let channels = manifest.input_channels.unwrap_or(3).max(1);
    let mut cursor = Cursor::new(model_bytes);
    let model = tract_onnx::onnx()
        .model_for_read(&mut cursor)
        .map_err(|error| format!("hand landmark ONNX load failed: {error}"))?
        .with_input_fact(
            0,
            f32::fact([1, channels, manifest.input_height, manifest.input_width]).into(),
        )
        .map_err(|error| format!("hand landmark input fact failed: {error}"))?
        .into_optimized()
        .map_err(|error| format!("hand landmark optimize failed: {error}"))?
        .into_runnable()
        .map_err(|error| format!("hand landmark runnable build failed: {error}"))?;

    let status = status_from_manifest(&manifest, "loaded");
    let runtime = HandLandmarkRuntime { manifest, model };
    let mut guard = HAND_LANDMARK_RUNTIME
        .lock()
        .map_err(|_| "hand landmark runtime lock poisoned".to_string())?;
    *guard = Some(runtime);
    Ok(status)
}

fn run_landmark_model(
    rgb_bytes: &[u8],
    width: usize,
    height: usize,
) -> Result<(Vec<f32>, HandLandmarkManifest), String> {
    let guard = HAND_LANDMARK_RUNTIME
        .lock()
        .map_err(|_| "hand landmark runtime lock poisoned".to_string())?;
    let Some(runtime) = guard.as_ref() else {
        return Err("hand landmark model is not loaded".to_string());
    };

    let expected = width.saturating_mul(height).saturating_mul(3);
    if expected == 0 || rgb_bytes.len() < expected {
        return Err("hand crop does not contain enough RGB bytes".to_string());
    }

    let input = resize_rgb_chw(
        rgb_bytes,
        width,
        height,
        runtime.manifest.input_width,
        runtime.manifest.input_height,
    );
    let tensor = tract_ndarray::Array4::from_shape_vec(
        (
            1,
            3,
            runtime.manifest.input_height,
            runtime.manifest.input_width,
        ),
        input,
    )
    .map_err(|error| format!("hand landmark input tensor failed: {error}"))?
    .into_tensor();

    let outputs = runtime
        .model
        .run(tvec!(tensor.into()))
        .map_err(|error| format!("hand landmark inference failed: {error}"))?;
    let first = outputs
        .first()
        .ok_or_else(|| "hand landmark model returned no output".to_string())?;
    let view = first
        .to_array_view::<f32>()
        .map_err(|error| format!("hand landmark output type failed: {error}"))?;

    Ok((view.iter().copied().collect(), runtime.manifest.clone()))
}

fn resize_rgb_chw(
    rgb: &[u8],
    source_width: usize,
    source_height: usize,
    target_width: usize,
    target_height: usize,
) -> Vec<f32> {
    let plane_size = target_width.saturating_mul(target_height);
    let mut output = vec![0.0_f32; plane_size.saturating_mul(3)];

    for target_y in 0..target_height {
        let source_y = target_y.saturating_mul(source_height) / target_height.max(1);
        for target_x in 0..target_width {
            let source_x = target_x.saturating_mul(source_width) / target_width.max(1);
            let source_index = (source_y.saturating_mul(source_width).saturating_add(source_x))
                .saturating_mul(3);
            let target_index = target_y.saturating_mul(target_width).saturating_add(target_x);
            if source_index + 2 >= rgb.len() || target_index >= plane_size {
                continue;
            }
            output[target_index] = rgb[source_index] as f32 / 255.0;
            output[plane_size + target_index] = rgb[source_index + 1] as f32 / 255.0;
            output[plane_size * 2 + target_index] = rgb[source_index + 2] as f32 / 255.0;
        }
    }
    output
}

fn status_from_manifest(manifest: &HandLandmarkManifest, message: &str) -> HandLandmarkModelStatus {
    HandLandmarkModelStatus {
        loaded: true,
        model_name: manifest
            .model_name
            .clone()
            .unwrap_or_else(|| "kslas-local-hand-landmark".to_string()),
        input_width: manifest.input_width as i32,
        input_height: manifest.input_height as i32,
        landmark_count: manifest.landmark_count.unwrap_or(21) as i32,
        message: message.to_string(),
    }
}

fn unloaded_status(message: &str) -> HandLandmarkModelStatus {
    HandLandmarkModelStatus {
        loaded: false,
        model_name: "unloaded".to_string(),
        input_width: 0,
        input_height: 0,
        landmark_count: 0,
        message: message.to_string(),
    }
}

fn unusable_result(reason: &str) -> HandLandmarkInferenceResult {
    HandLandmarkInferenceResult {
        landmarks: Vec::new(),
        gesture: HandGestureResult {
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
        },
        usable: false,
        reason: reason.to_string(),
    }
}

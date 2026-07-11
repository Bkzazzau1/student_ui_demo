use std::io::Cursor;
use std::sync::{Arc, Mutex};

use flutter_rust_bridge::frb;
use once_cell::sync::Lazy;
use serde::{Deserialize, Serialize};
use tract_onnx::prelude::*;

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

#[frb]
#[derive(Clone, Debug, Serialize, Deserialize, PartialEq)]
pub struct HandVisionModelStatus {
    pub loaded: bool,
    pub model_name: String,
    pub input_width: i32,
    pub input_height: i32,
    pub confidence_threshold: f32,
    pub iou_threshold: f32,
    pub message: String,
}

#[derive(Clone, Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct HandVisionManifest {
    model_name: Option<String>,
    input_width: usize,
    input_height: usize,
    input_channels: Option<usize>,
    num_predictions: usize,
    num_classes: usize,
    output_layout: Option<String>,
    class_names: Vec<String>,
    confidence_threshold: Option<f32>,
    iou_threshold: Option<f32>,
}

type HandVisionPlan = Arc<TypedRunnableModel>;

#[derive(Debug)]
struct HandVisionRuntime {
    manifest: HandVisionManifest,
    model: HandVisionPlan,
}

static HAND_VISION_RUNTIME: Lazy<Mutex<Option<HandVisionRuntime>>> =
    Lazy::new(|| Mutex::new(None));

#[frb(sync)]
pub fn load_hand_vision_model(
    manifest_json: String,
    model_bytes: Vec<u8>,
) -> HandVisionModelStatus {
    match load_hand_vision_model_inner(manifest_json, model_bytes) {
        Ok(status) => status,
        Err(message) => HandVisionModelStatus {
            loaded: false,
            model_name: "unloaded".to_string(),
            input_width: 0,
            input_height: 0,
            confidence_threshold: 0.0,
            iou_threshold: 0.0,
            message,
        },
    }
}

#[frb(sync)]
pub fn clear_hand_vision_model() {
    if let Ok(mut guard) = HAND_VISION_RUNTIME.lock() {
        *guard = None;
    }
}

#[frb(sync)]
pub fn current_hand_vision_model_status() -> HandVisionModelStatus {
    match HAND_VISION_RUNTIME.lock() {
        Ok(guard) => match guard.as_ref() {
            Some(runtime) => status_from_manifest(&runtime.manifest, "loaded"),
            None => HandVisionModelStatus {
                loaded: false,
                model_name: "unloaded".to_string(),
                input_width: 0,
                input_height: 0,
                confidence_threshold: 0.0,
                iou_threshold: 0.0,
                message: "no hand model loaded".to_string(),
            },
        },
        Err(_) => HandVisionModelStatus {
            loaded: false,
            model_name: "unloaded".to_string(),
            input_width: 0,
            input_height: 0,
            confidence_threshold: 0.0,
            iou_threshold: 0.0,
            message: "hand vision runtime lock poisoned".to_string(),
        },
    }
}

#[frb(sync)]
pub fn analyze_hand_rgb_frame(
    rgb_bytes: Vec<u8>,
    image_width: i32,
    image_height: i32,
    zones: HandVisionZones,
    timestamp_ms: i64,
) -> HandVisionResult {
    if image_width <= 0 || image_height <= 0 {
        return empty_result(timestamp_ms, "invalid camera frame dimensions");
    }

    match run_hand_model(&rgb_bytes, image_width as usize, image_height as usize) {
        Ok((output, manifest)) => review_hand_model_output(
            output,
            manifest.num_predictions as i32,
            manifest.num_classes as i32,
            image_width,
            image_height,
            manifest.confidence_threshold.unwrap_or(0.35),
            manifest.iou_threshold.unwrap_or(0.45),
            manifest
                .output_layout
                .unwrap_or_else(|| "channels_first_yolov8".to_string()),
            manifest.class_names,
            zones,
            timestamp_ms,
        ),
        Err(message) => empty_result(timestamp_ms, &message),
    }
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
    let reviewed = decode_yolo_output(
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
        reviewed.detections,
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
    let Some(primary) = hands.first() else {
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
    };

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

fn load_hand_vision_model_inner(
    manifest_json: String,
    model_bytes: Vec<u8>,
) -> Result<HandVisionModelStatus, String> {
    let manifest: HandVisionManifest =
        serde_json::from_str(&manifest_json).map_err(|error| format!("invalid hand manifest: {error}"))?;

    if manifest.input_width == 0 || manifest.input_height == 0 {
        return Err("hand model input dimensions must be greater than zero".to_string());
    }
    if manifest.num_predictions == 0 || manifest.num_classes == 0 {
        return Err("hand model output dimensions must be greater than zero".to_string());
    }
    if manifest.class_names.len() < manifest.num_classes {
        return Err("hand model class names do not match numClasses".to_string());
    }
    if model_bytes.is_empty() {
        return Err("hand model asset bytes are empty".to_string());
    }

    let channels = manifest.input_channels.unwrap_or(3).max(1);
    let mut cursor = Cursor::new(model_bytes);
    let model = tract_onnx::onnx()
        .model_for_read(&mut cursor)
        .map_err(|error| format!("hand ONNX load failed: {error}"))?
        .with_input_fact(
            0,
            f32::fact([1, channels, manifest.input_height, manifest.input_width]).into(),
        )
        .map_err(|error| format!("hand ONNX input fact failed: {error}"))?
        .into_optimized()
        .map_err(|error| format!("hand ONNX optimize failed: {error}"))?
        .into_runnable()
        .map_err(|error| format!("hand ONNX runnable build failed: {error}"))?;

    let status = status_from_manifest(&manifest, "loaded");
    let runtime = HandVisionRuntime {
        manifest,
        model: Arc::new(model),
    };
    let mut guard = HAND_VISION_RUNTIME
        .lock()
        .map_err(|_| "hand vision runtime lock poisoned".to_string())?;
    *guard = Some(runtime);
    Ok(status)
}

fn run_hand_model(
    rgb_bytes: &[u8],
    width: usize,
    height: usize,
) -> Result<(Vec<f32>, HandVisionManifest), String> {
    let guard = HAND_VISION_RUNTIME
        .lock()
        .map_err(|_| "hand vision runtime lock poisoned".to_string())?;
    let Some(runtime) = guard.as_ref() else {
        return Err("hand model is not loaded".to_string());
    };

    let expected = width.saturating_mul(height).saturating_mul(3);
    if rgb_bytes.len() < expected || expected == 0 {
        return Err("sampled camera frame does not contain enough RGB bytes".to_string());
    }

    let resized = resize_rgb_chw(
        rgb_bytes,
        width,
        height,
        runtime.manifest.input_width,
        runtime.manifest.input_height,
    );
    let tensor = Tensor::from_shape(
        &[
            1,
            3,
            runtime.manifest.input_height,
            runtime.manifest.input_width,
        ],
        &resized,
    )
    .map_err(|error| format!("hand input tensor build failed: {error}"))?;

    let outputs = runtime
        .model
        .run(tvec!(tensor.into()))
        .map_err(|error| format!("hand ONNX inference failed: {error}"))?;
    let Some(first) = outputs.first() else {
        return Err("hand ONNX inference returned no output".to_string());
    };
    let tensor = first
        .clone()
        .into_tensor()
        .cast_to::<f32>()
        .map_err(|error| format!("hand ONNX output cast failed: {error}"))?
        .into_owned();
    let output = tensor
        .try_as_dense()
        .map_err(|error| format!("hand ONNX output dense conversion failed: {error}"))?
        .as_slice::<f32>()
        .map_err(|error| format!("hand ONNX output parse failed: {error}"))?
        .to_vec();

    Ok((output, runtime.manifest.clone()))
}

fn resize_rgb_chw(
    input: &[u8],
    input_width: usize,
    input_height: usize,
    output_width: usize,
    output_height: usize,
) -> Vec<f32> {
    let plane_size = output_width.saturating_mul(output_height);
    let mut output = vec![0.0_f32; plane_size.saturating_mul(3)];
    if input_width == 0 || input_height == 0 || output_width == 0 || output_height == 0 {
        return output;
    }

    for y in 0..output_height {
        let source_y = (y * input_height / output_height).min(input_height - 1);
        for x in 0..output_width {
            let source_x = (x * input_width / output_width).min(input_width - 1);
            let source = (source_y * input_width + source_x) * 3;
            let target = y * output_width + x;
            output[target] = input[source] as f32 / 255.0;
            output[plane_size + target] = input[source + 1] as f32 / 255.0;
            output[plane_size * 2 + target] = input[source + 2] as f32 / 255.0;
        }
    }
    output
}

fn status_from_manifest(manifest: &HandVisionManifest, message: &str) -> HandVisionModelStatus {
    HandVisionModelStatus {
        loaded: true,
        model_name: manifest
            .model_name
            .clone()
            .unwrap_or_else(|| "local-hand-detector".to_string()),
        input_width: manifest.input_width as i32,
        input_height: manifest.input_height as i32,
        confidence_threshold: manifest.confidence_threshold.unwrap_or(0.35),
        iou_threshold: manifest.iou_threshold.unwrap_or(0.45),
        message: message.to_string(),
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

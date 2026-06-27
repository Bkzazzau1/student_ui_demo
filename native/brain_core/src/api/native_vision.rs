use flutter_rust_bridge::frb;
use serde::{Deserialize, Serialize};

#[frb]
#[derive(Clone, Debug, Serialize, Deserialize, PartialEq)]
pub struct NativeVisionDetection {
    pub class_id: i32,
    pub label: String,
    pub confidence: f32,
    pub x_center: f32,
    pub y_center: f32,
    pub width: f32,
    pub height: f32,
    pub x_min: f32,
    pub y_min: f32,
    pub x_max: f32,
    pub y_max: f32,
}

#[frb]
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct NativeVisionFrameQuality {
    pub is_usable: bool,
    pub brightness: f32,
    pub contrast: f32,
    pub sharpness: f32,
    pub reason: String,
}

#[frb]
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct NativeObjectReviewResult {
    pub detections: Vec<NativeVisionDetection>,
    pub people_count: i32,
    pub phone_count: i32,
    pub book_count: i32,
    pub paper_count: i32,
    pub needs_review: bool,
    pub attention_level: String,
    pub reason: String,
}

#[frb]
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct NativeHeadPoseReviewResult {
    pub usable: bool,
    pub looking_away: bool,
    pub yaw_score: f32,
    pub pitch_score: f32,
    pub roll_score: f32,
    pub attention_level: String,
    pub reason: String,
}

#[frb(sync)]
pub fn analyze_rgb_frame_quality(width: i32, height: i32, rgb_bytes: Vec<u8>) -> NativeVisionFrameQuality {
    if width <= 0 || height <= 0 {
        return frame_quality(false, 0.0, 0.0, 0.0, "invalid frame dimensions");
    }

    let pixel_count = (width as usize).saturating_mul(height as usize);
    if rgb_bytes.len() < pixel_count.saturating_mul(3) || pixel_count == 0 {
        return frame_quality(false, 0.0, 0.0, 0.0, "not enough RGB bytes for frame");
    }

    let mut luma_values = Vec::with_capacity(pixel_count);
    let mut sum = 0.0_f32;
    for pixel in rgb_bytes.chunks_exact(3).take(pixel_count) {
        let luma = 0.299 * pixel[0] as f32 + 0.587 * pixel[1] as f32 + 0.114 * pixel[2] as f32;
        luma_values.push(luma);
        sum += luma;
    }

    let mean = sum / pixel_count as f32;
    let variance = luma_values
        .iter()
        .map(|value| {
            let diff = *value - mean;
            diff * diff
        })
        .sum::<f32>()
        / pixel_count as f32;
    let contrast = variance.sqrt();
    let sharpness = approximate_sharpness(&luma_values, width as usize, height as usize);

    let is_usable = mean >= 35.0 && mean <= 235.0 && contrast >= 8.0 && sharpness >= 3.0;
    let reason = if mean < 35.0 {
        "frame is too dark"
    } else if mean > 235.0 {
        "frame is overexposed"
    } else if contrast < 8.0 {
        "frame has low contrast"
    } else if sharpness < 3.0 {
        "frame may be blurry"
    } else {
        "frame quality is usable"
    };

    frame_quality(is_usable, mean, contrast, sharpness, reason)
}

#[frb(sync)]
pub fn decode_yolo_output(
    output: Vec<f32>,
    num_predictions: i32,
    num_classes: i32,
    image_width: i32,
    image_height: i32,
    confidence_threshold: f32,
    iou_threshold: f32,
    layout: String,
    class_names: Vec<String>,
) -> NativeObjectReviewResult {
    if num_predictions <= 0 || num_classes <= 0 || image_width <= 0 || image_height <= 0 {
        return object_review(Vec::new(), "model output shape is invalid");
    }

    let decoded = decode_predictions(
        &output,
        num_predictions as usize,
        num_classes as usize,
        image_width as f32,
        image_height as f32,
        confidence_threshold.max(0.01),
        &layout,
        &class_names,
    );
    let detections = non_max_suppression(decoded, iou_threshold.clamp(0.05, 0.95));
    object_review(detections, "object review complete")
}

#[frb(sync)]
pub fn review_object_detections(
    detections: Vec<NativeVisionDetection>,
    iou_threshold: f32,
) -> NativeObjectReviewResult {
    let filtered = non_max_suppression(detections, iou_threshold.clamp(0.05, 0.95));
    object_review(filtered, "object review complete")
}

#[frb(sync)]
pub fn analyze_head_pose_geometry(
    left_eye_x: f32,
    left_eye_y: f32,
    right_eye_x: f32,
    right_eye_y: f32,
    nose_x: f32,
    nose_y: f32,
    mouth_x: f32,
    mouth_y: f32,
    face_width: f32,
    face_height: f32,
) -> NativeHeadPoseReviewResult {
    let _ = mouth_x;
    if face_width <= 0.0 || face_height <= 0.0 {
        return head_pose(false, true, 1.0, 1.0, 1.0, "urgent_review_required", "invalid face geometry");
    }

    let eye_mid_x = (left_eye_x + right_eye_x) / 2.0;
    let eye_mid_y = (left_eye_y + right_eye_y) / 2.0;
    let eye_dx = right_eye_x - left_eye_x;
    let eye_dy = right_eye_y - left_eye_y;
    let roll_score = (eye_dy.atan2(eye_dx).abs() / 0.55).clamp(0.0, 1.0);

    let yaw_score = ((nose_x - eye_mid_x).abs() / (face_width * 0.18)).clamp(0.0, 1.0);
    let mouth_eye_distance = (mouth_y - eye_mid_y).abs();
    let nose_eye_distance = (nose_y - eye_mid_y).abs();
    let vertical_ratio = if mouth_eye_distance <= 0.001 {
        1.0
    } else {
        nose_eye_distance / mouth_eye_distance
    };
    let pitch_score = ((vertical_ratio - 0.42).abs() / 0.25).clamp(0.0, 1.0);

    let combined = yaw_score.max(pitch_score).max(roll_score);
    let looking_away = combined >= 0.72;
    let attention_level = if combined >= 0.9 {
        "urgent_review_required"
    } else if combined >= 0.72 {
        "high_attention_required"
    } else {
        "normal"
    };
    let reason = if looking_away {
        "head pose may need human review"
    } else {
        "head pose is within expected range"
    };

    head_pose(true, looking_away, yaw_score, pitch_score, roll_score, attention_level, reason)
}

fn decode_predictions(
    output: &[f32],
    num_predictions: usize,
    num_classes: usize,
    image_width: f32,
    image_height: f32,
    confidence_threshold: f32,
    layout: &str,
    class_names: &[String],
) -> Vec<NativeVisionDetection> {
    let normalized_layout = layout.trim().to_lowercase();
    let attributes_yolov8 = 4 + num_classes;
    let attributes_yolov5 = 5 + num_classes;

    let mut detections = Vec::new();
    for index in 0..num_predictions {
        let prediction = if normalized_layout == "channels_first_yolov8" {
            gather_channels_first(output, index, num_predictions, attributes_yolov8)
        } else if normalized_layout == "rows_yolov5" {
            gather_row(output, index, attributes_yolov5)
        } else {
            gather_row(output, index, attributes_yolov8)
        };

        if prediction.len() != attributes_yolov8 && prediction.len() != attributes_yolov5 {
            continue;
        }

        let cx = prediction[0];
        let cy = prediction[1];
        let width = prediction[2].abs();
        let height = prediction[3].abs();
        let (class_start, objectness) = if prediction.len() == attributes_yolov5 {
            (5, prediction[4].clamp(0.0, 1.0))
        } else {
            (4, 1.0)
        };

        let mut best_class = 0usize;
        let mut best_score = 0.0_f32;
        for class_index in 0..num_classes {
            let score = prediction[class_start + class_index].clamp(0.0, 1.0) * objectness;
            if score > best_score {
                best_score = score;
                best_class = class_index;
            }
        }
        if best_score < confidence_threshold {
            continue;
        }

        let (x_center, y_center, box_width, box_height) = normalize_box(cx, cy, width, height, image_width, image_height);
        let x_min = (x_center - box_width / 2.0).clamp(0.0, image_width);
        let y_min = (y_center - box_height / 2.0).clamp(0.0, image_height);
        let x_max = (x_center + box_width / 2.0).clamp(0.0, image_width);
        let y_max = (y_center + box_height / 2.0).clamp(0.0, image_height);

        detections.push(NativeVisionDetection {
            class_id: best_class as i32,
            label: class_names
                .get(best_class)
                .cloned()
                .unwrap_or_else(|| format!("class_{best_class}")),
            confidence: best_score,
            x_center,
            y_center,
            width: box_width,
            height: box_height,
            x_min,
            y_min,
            x_max,
            y_max,
        });
    }
    detections
}

fn gather_row(output: &[f32], index: usize, attributes: usize) -> Vec<f32> {
    let start = index.saturating_mul(attributes);
    let end = start.saturating_add(attributes);
    if end > output.len() {
        return Vec::new();
    }
    output[start..end].to_vec()
}

fn gather_channels_first(output: &[f32], index: usize, num_predictions: usize, attributes: usize) -> Vec<f32> {
    let mut row = Vec::with_capacity(attributes);
    for attr in 0..attributes {
        let offset = attr.saturating_mul(num_predictions).saturating_add(index);
        if offset >= output.len() {
            return Vec::new();
        }
        row.push(output[offset]);
    }
    row
}

fn normalize_box(cx: f32, cy: f32, width: f32, height: f32, image_width: f32, image_height: f32) -> (f32, f32, f32, f32) {
    if cx <= 1.5 && cy <= 1.5 && width <= 1.5 && height <= 1.5 {
        (
            cx * image_width,
            cy * image_height,
            width * image_width,
            height * image_height,
        )
    } else {
        (cx, cy, width, height)
    }
}

fn non_max_suppression(mut detections: Vec<NativeVisionDetection>, iou_threshold: f32) -> Vec<NativeVisionDetection> {
    detections.sort_by(|a, b| b.confidence.partial_cmp(&a.confidence).unwrap_or(std::cmp::Ordering::Equal));
    let mut kept: Vec<NativeVisionDetection> = Vec::new();
    'candidate: for detection in detections {
        for existing in &kept {
            if detection.class_id == existing.class_id && iou(&detection, existing) > iou_threshold {
                continue 'candidate;
            }
        }
        kept.push(detection);
    }
    kept
}

fn iou(a: &NativeVisionDetection, b: &NativeVisionDetection) -> f32 {
    let x_left = a.x_min.max(b.x_min);
    let y_top = a.y_min.max(b.y_min);
    let x_right = a.x_max.min(b.x_max);
    let y_bottom = a.y_max.min(b.y_max);
    if x_right <= x_left || y_bottom <= y_top {
        return 0.0;
    }
    let intersection = (x_right - x_left) * (y_bottom - y_top);
    let area_a = (a.x_max - a.x_min).max(0.0) * (a.y_max - a.y_min).max(0.0);
    let area_b = (b.x_max - b.x_min).max(0.0) * (b.y_max - b.y_min).max(0.0);
    intersection / (area_a + area_b - intersection).max(0.0001)
}

fn object_review(detections: Vec<NativeVisionDetection>, default_reason: &str) -> NativeObjectReviewResult {
    let people_count = detections.iter().filter(|d| is_person(&d.label)).count() as i32;
    let phone_count = detections.iter().filter(|d| is_phone(&d.label)).count() as i32;
    let book_count = detections.iter().filter(|d| is_book(&d.label)).count() as i32;
    let paper_count = detections.iter().filter(|d| is_paper(&d.label)).count() as i32;

    let needs_review = people_count > 1 || phone_count > 0 || book_count > 0 || paper_count > 0;
    let attention_level = if phone_count > 0 || people_count > 1 {
        "high_attention_required"
    } else if book_count > 0 || paper_count > 0 {
        "medium_attention_required"
    } else {
        "normal"
    };
    let reason = if phone_count > 0 {
        "phone-like object may need human review"
    } else if people_count > 1 {
        "more than one person may be visible"
    } else if book_count > 0 || paper_count > 0 {
        "book or paper-like object may need review"
    } else {
        default_reason
    };

    NativeObjectReviewResult {
        detections,
        people_count,
        phone_count,
        book_count,
        paper_count,
        needs_review,
        attention_level: attention_level.to_string(),
        reason: reason.to_string(),
    }
}

fn is_person(label: &str) -> bool {
    label.eq_ignore_ascii_case("person") || label.eq_ignore_ascii_case("human")
}

fn is_phone(label: &str) -> bool {
    let lower = label.to_lowercase();
    lower.contains("phone") || lower.contains("cell") || lower.contains("mobile")
}

fn is_book(label: &str) -> bool {
    let lower = label.to_lowercase();
    lower.contains("book")
}

fn is_paper(label: &str) -> bool {
    let lower = label.to_lowercase();
    lower.contains("paper") || lower.contains("document") || lower.contains("notebook")
}

fn approximate_sharpness(luma: &[f32], width: usize, height: usize) -> f32 {
    if width < 3 || height < 3 {
        return 0.0;
    }
    let mut total = 0.0_f32;
    let mut count = 0usize;
    for y in 1..(height - 1) {
        for x in 1..(width - 1) {
            let center = luma[y * width + x] * 4.0;
            let neighbors = luma[y * width + x - 1]
                + luma[y * width + x + 1]
                + luma[(y - 1) * width + x]
                + luma[(y + 1) * width + x];
            total += (center - neighbors).abs();
            count += 1;
        }
    }
    if count == 0 { 0.0 } else { total / count as f32 }
}

fn frame_quality(is_usable: bool, brightness: f32, contrast: f32, sharpness: f32, reason: &str) -> NativeVisionFrameQuality {
    NativeVisionFrameQuality {
        is_usable,
        brightness,
        contrast,
        sharpness,
        reason: reason.to_string(),
    }
}

fn head_pose(
    usable: bool,
    looking_away: bool,
    yaw_score: f32,
    pitch_score: f32,
    roll_score: f32,
    attention_level: &str,
    reason: &str,
) -> NativeHeadPoseReviewResult {
    NativeHeadPoseReviewResult {
        usable,
        looking_away,
        yaw_score,
        pitch_score,
        roll_score,
        attention_level: attention_level.to_string(),
        reason: reason.to_string(),
    }
}

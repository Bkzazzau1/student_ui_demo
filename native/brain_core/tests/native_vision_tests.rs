use brain_core::api::{
    NativeVisionDetection, analyze_head_pose_geometry, analyze_rgb_frame_quality,
    decode_yolo_output, review_object_detections,
};

#[test]
fn frame_quality_rejects_dark_frame() {
    let frame = vec![0_u8; 12 * 12 * 3];
    let result = analyze_rgb_frame_quality(12, 12, frame);

    assert!(!result.is_usable);
    assert!(result.reason.contains("dark"));
}

#[test]
fn frame_quality_accepts_contrasty_frame() {
    let mut frame = Vec::new();
    for index in 0..(16 * 16) {
        let value = if index % 2 == 0 { 30_u8 } else { 230_u8 };
        frame.extend_from_slice(&[value, value, value]);
    }

    let result = analyze_rgb_frame_quality(16, 16, frame);

    assert!(result.is_usable);
    assert!(result.contrast > 8.0);
    assert!(result.sharpness > 3.0);
}

#[test]
fn yolo_rows_decode_detects_phone_and_person() {
    let class_names = vec![
        "person".to_string(),
        "cell phone".to_string(),
        "book".to_string(),
    ];
    let output = vec![
        320.0, 240.0, 100.0, 180.0, 0.92, 0.04, 0.02, 100.0, 120.0, 40.0, 60.0, 0.05, 0.91, 0.02,
    ];

    let result = decode_yolo_output(
        output,
        2,
        3,
        640,
        480,
        0.5,
        0.45,
        "rows_yolov8".to_string(),
        class_names,
    );

    assert_eq!(result.people_count, 1);
    assert_eq!(result.phone_count, 1);
    assert!(result.needs_review);
    assert_eq!(result.attention_level, "high_attention_required");
}

#[test]
fn yolo_channels_first_decode_is_supported() {
    let class_names = vec!["person".to_string(), "cell phone".to_string()];
    let output = vec![
        0.5, 0.2, 0.5, 0.3, 0.2, 0.1, 0.4, 0.1, 0.95, 0.01, 0.02, 0.9,
    ];

    let result = decode_yolo_output(
        output,
        2,
        2,
        640,
        480,
        0.5,
        0.45,
        "channels_first_yolov8".to_string(),
        class_names,
    );

    assert_eq!(result.detections.len(), 2);
    assert_eq!(result.people_count, 1);
    assert_eq!(result.phone_count, 1);
}

#[test]
fn nms_removes_overlapping_same_class_detection() {
    let detections = vec![
        detection(0, "person", 0.95, 100.0, 100.0, 60.0, 60.0),
        detection(0, "person", 0.80, 105.0, 105.0, 60.0, 60.0),
        detection(1, "cell phone", 0.90, 300.0, 300.0, 40.0, 40.0),
    ];

    let result = review_object_detections(detections, 0.45);

    assert_eq!(result.detections.len(), 2);
    assert_eq!(result.people_count, 1);
    assert_eq!(result.phone_count, 1);
}

#[test]
fn head_pose_flags_large_yaw() {
    let result =
        analyze_head_pose_geometry(40.0, 40.0, 80.0, 40.0, 74.0, 60.0, 60.0, 90.0, 100.0, 120.0);

    assert!(result.usable);
    assert!(result.looking_away);
    assert_eq!(result.attention_level, "high_attention_required");
}

#[test]
fn head_pose_accepts_centered_face() {
    // Real frontal proportions: the nose sits about 0.61 of the way from the
    // eyes to the mouth.
    let result =
        analyze_head_pose_geometry(40.0, 40.0, 80.0, 40.0, 60.0, 60.0, 60.0, 72.8, 100.0, 120.0);

    assert!(result.usable);
    assert!(!result.looking_away);
    assert!(result.pitch_score.abs() < 0.1);
}

#[test]
fn head_pose_allows_reading_the_bottom_of_the_screen() {
    // About 20 degrees down: nose ratio 0.78.
    let result =
        analyze_head_pose_geometry(40.0, 40.0, 80.0, 40.0, 60.0, 60.0, 60.0, 65.6, 100.0, 120.0);

    assert!(!result.looking_away);
    assert!(result.pitch_score > 0.5);
}

#[test]
fn head_pose_flags_looking_up_and_tells_left_from_right() {
    // About 25 degrees up: nose ratio 0.37.
    let up =
        analyze_head_pose_geometry(40.0, 40.0, 80.0, 40.0, 60.0, 60.0, 60.0, 94.0, 100.0, 120.0);
    assert!(up.looking_away);
    assert!(up.pitch_score < -0.72);

    let right =
        analyze_head_pose_geometry(40.0, 40.0, 80.0, 40.0, 74.0, 60.0, 60.0, 72.8, 100.0, 120.0);
    let left =
        analyze_head_pose_geometry(40.0, 40.0, 80.0, 40.0, 46.0, 60.0, 60.0, 72.8, 100.0, 120.0);
    assert!(right.yaw_score > 0.7);
    assert!(left.yaw_score < -0.7);
}

fn detection(
    class_id: i32,
    label: &str,
    confidence: f32,
    cx: f32,
    cy: f32,
    width: f32,
    height: f32,
) -> NativeVisionDetection {
    NativeVisionDetection {
        class_id,
        label: label.to_string(),
        confidence,
        x_center: cx,
        y_center: cy,
        width,
        height,
        x_min: cx - width / 2.0,
        y_min: cy - height / 2.0,
        x_max: cx + width / 2.0,
        y_max: cy + height / 2.0,
    }
}

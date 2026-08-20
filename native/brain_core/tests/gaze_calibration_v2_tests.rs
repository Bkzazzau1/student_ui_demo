use brain_core::api::{
    GazeCalibrationSample, build_gaze_calibration_profile_v2, predict_calibrated_gaze_zone_v2,
};

fn samples() -> Vec<GazeCalibrationSample> {
    let targets = [
        ("camera", 0.50, 0.45),
        ("question_area", 0.28, 0.48),
        ("answer_area", 0.50, 0.58),
        ("air_board", 0.74, 0.56),
        ("top_screen_area", 0.50, 0.25),
    ];
    targets
        .iter()
        .flat_map(|(zone, x, y)| {
            (0..4).map(move |index| GazeCalibrationSample {
                zone: (*zone).into(),
                eye_x: x + index as f32 * 0.002,
                eye_y: y + index as f32 * 0.002,
                head_yaw: 0.01,
                head_pitch: -0.01,
                head_roll: 0.0,
                confidence: 0.92,
                timestamp_ms: index,
            })
        })
        .collect()
}

fn profile() -> brain_core::api::GazeCalibrationProfileV2 {
    build_gaze_calibration_profile_v2(
        samples(),
        "student-1".into(),
        "device-1".into(),
        "exam-1".into(),
        "attempt-1".into(),
        "camera-1".into(),
        1920,
        1080,
        1.0,
        "face-landmarker-v1".into(),
        "a".repeat(64),
        100,
        10_000,
    )
}

#[test]
fn builds_bound_multi_target_profile() {
    let result = profile();
    assert!(result.usable, "{}", result.reason);
    assert_eq!(result.zones.len(), 5);
    assert_eq!(result.sample_count, 20);
}

#[test]
fn predicts_nearest_personal_zone_and_deviation() {
    let result = predict_calibrated_gaze_zone_v2(profile(), 0.745, 0.565, 0.01, -0.01, 0.91, 500);
    assert_eq!(result.zone, "air_board");
    assert!(result.actionable);
    assert!(result.deviation_score > 2.0);
}

#[test]
fn expired_profile_is_never_actionable() {
    let result = predict_calibrated_gaze_zone_v2(profile(), 0.5, 0.45, 0.0, 0.0, 0.9, 10_001);
    assert!(!result.actionable);
    assert_eq!(result.zone, "camera_not_reliable");
}

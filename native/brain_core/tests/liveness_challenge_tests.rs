use brain_core::api::{LivenessObservation, analyze_liveness_challenge};

fn sample(time: i64, eye: f32, yaw: f32) -> LivenessObservation {
    LivenessObservation {
        timestamp_ms: time,
        face_confidence: 0.91,
        left_eye_open: eye,
        right_eye_open: eye,
        head_yaw: yaw,
        head_pitch: 0.0,
        motion_score: 0.04,
        repeated_frame: false,
        flat_texture: false,
    }
}

#[test]
fn accepts_open_closed_open_blink_sequence() {
    let result = analyze_liveness_challenge(
        "blink".into(),
        vec![
            sample(100, 0.3, 0.0),
            sample(200, 0.29, 0.0),
            sample(300, 0.08, 0.0),
            sample(400, 0.28, 0.0),
        ],
        0,
        2_000,
        500,
    );
    assert_eq!(result.state, "live_challenge_passed");
    assert!(result.completed);
}

#[test]
fn does_not_accept_closed_eyes_without_reopening() {
    let result = analyze_liveness_challenge(
        "blink".into(),
        vec![
            sample(100, 0.3, 0.0),
            sample(200, 0.08, 0.0),
            sample(300, 0.07, 0.0),
            sample(400, 0.08, 0.0),
        ],
        0,
        2_000,
        500,
    );
    assert_eq!(result.state, "liveness_uncertain");
}

#[test]
fn repeated_flat_frames_request_review_not_accusation() {
    let mut observations = Vec::new();
    for index in 0..8 {
        let mut value = sample(index * 100, 0.3, 0.0);
        value.repeated_frame = true;
        value.flat_texture = true;
        value.motion_score = 0.0;
        observations.push(value);
    }
    let result = analyze_liveness_challenge("turn_left".into(), observations, 0, 2_000, 900);
    assert_eq!(result.state, "possible_presentation_attack");
    assert!(!result.completed);
    assert!(result.reason.contains("human review"));
}

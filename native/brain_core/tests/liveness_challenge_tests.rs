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

fn run(challenge: &str, observations: Vec<LivenessObservation>, now: i64) -> String {
    analyze_liveness_challenge(challenge.into(), observations, 0, 8_000, now).state
}

fn series(values: &[f32], eye: bool) -> Vec<LivenessObservation> {
    values
        .iter()
        .enumerate()
        .map(|(i, value)| {
            let time = 300 * (i as i64 + 1);
            if eye {
                sample(time, *value, 0.0)
            } else {
                sample(time, 0.3, *value)
            }
        })
        .collect()
}

#[test]
fn accepts_open_closed_open_blink_sequence() {
    let observations = series(&[0.3, 0.29, 0.3, 0.08, 0.28, 0.3], true);
    assert_eq!(run("blink", observations, 2_000), "live_challenge_passed");
}

#[test]
fn blink_is_relative_to_the_students_own_open_eyes() {
    // Narrow open eyes (0.18) never reached the old absolute 0.22 "open".
    let observations = series(&[0.18, 0.18, 0.17, 0.06, 0.18, 0.18, 0.18], true);
    assert_eq!(run("blink", observations, 2_500), "live_challenge_passed");
}

#[test]
fn does_not_accept_closed_eyes_without_reopening() {
    let observations = series(&[0.3, 0.3, 0.3, 0.08, 0.07, 0.08], true);
    assert_eq!(run("blink", observations, 2_000), "liveness_uncertain");
}

#[test]
fn a_photo_that_is_already_turned_does_not_pass() {
    // A still photo turned about 12 degrees: yaw 0.25 in every frame.
    let observations = series(&[0.25; 10], false);
    assert_ne!(
        run("turn_left", observations, 3_100),
        "live_challenge_passed"
    );
}

#[test]
fn a_real_turn_from_the_students_own_start_passes() {
    let yaws = [0.02, 0.03, 0.10, 0.22, 0.38, 0.40];
    assert_eq!(
        run("turn_left", series(&yaws, false), 2_000),
        "live_challenge_passed"
    );
    // The same movement does not satisfy the opposite challenge.
    assert_ne!(
        run("turn_right", series(&yaws, false), 2_000),
        "live_challenge_passed"
    );
}

#[test]
fn movement_after_the_deadline_does_not_count() {
    let mut observations = series(&[0.0; 6], false);
    observations.push(sample(60_000, 0.3, 0.5));
    assert_ne!(
        run("turn_left", observations, 60_001),
        "live_challenge_passed"
    );
}

#[test]
fn identical_frames_are_flagged_from_six_frames() {
    let observations = series(&[0.0; 6], false)
        .into_iter()
        .enumerate()
        .map(|(i, mut value)| {
            value.repeated_frame = i > 0;
            value.motion_score = 0.0;
            value
        })
        .collect();
    assert_eq!(
        run("turn_left", observations, 2_000),
        "possible_presentation_attack"
    );
}

#[test]
fn needs_six_frames_before_passing() {
    let observations = series(&[0.0, 0.0, 0.4, 0.4], false);
    assert_eq!(run("turn_left", observations, 1_300), "liveness_uncertain");
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

use flutter_rust_bridge::frb;
use serde::{Deserialize, Serialize};

#[frb]
#[derive(Clone, Debug, Serialize, Deserialize, PartialEq)]
pub struct LivenessObservation {
    pub timestamp_ms: i64,
    pub face_confidence: f32,
    pub left_eye_open: f32,
    pub right_eye_open: f32,
    pub head_yaw: f32,
    pub head_pitch: f32,
    pub motion_score: f32,
    pub repeated_frame: bool,
    pub flat_texture: bool,
}

#[frb]
#[derive(Clone, Debug, Serialize, Deserialize, PartialEq)]
pub struct LivenessChallengeResult {
    pub state: String,
    pub challenge: String,
    pub completed: bool,
    pub reliable: bool,
    pub progress: f32,
    pub spoof_risk_score: f32,
    pub usable_observations: i32,
    pub reason: String,
}

/// Frames needed before a challenge can pass, so the presentation-attack
/// check has always run on enough frames first.
const MIN_FRAMES_TO_PASS: usize = 6;

/// A head turn or look-up must move this far (in the yaw/pitch proxy, where
/// 0.30 is about 13-15 degrees) from the session's own first frames. An
/// absolute threshold let a photo that was already turned, or tilted
/// in-plane, pass without any movement.
const MIN_HEAD_MOVEMENT: f32 = 0.30;

/// Eye-span-relative landmark motion below which a frame counts as still.
const LOW_MOTION: f32 = 0.01;

const SPOOF_THRESHOLD: f32 = 0.62;

/// Evaluates observable motion only. It never makes a misconduct decision.
///
/// Observations carry eye openness (eye aspect ratio), roll-compensated head
/// yaw/pitch proxies and landmark motion measured in pixels relative to the
/// eye span, so results do not depend on the camera frame's shape.
#[frb(sync)]
pub fn analyze_liveness_challenge(
    challenge: String,
    observations: Vec<LivenessObservation>,
    started_at_ms: i64,
    deadline_ms: i64,
    now_ms: i64,
) -> LivenessChallengeResult {
    if !matches!(
        challenge.as_str(),
        "blink" | "turn_left" | "turn_right" | "look_up"
    ) {
        return uncertain(&challenge, "unsupported liveness challenge", 0, 0.0, 0.0);
    }
    if deadline_ms <= started_at_ms || now_ms < started_at_ms {
        return uncertain(&challenge, "invalid challenge timing", 0, 0.0, 0.0);
    }
    // Frames after the deadline do not count: the challenge must be met in
    // time.
    let usable: Vec<&LivenessObservation> = observations
        .iter()
        .filter(|sample| {
            sample.timestamp_ms >= started_at_ms
                && sample.timestamp_ms <= now_ms
                && sample.timestamp_ms <= deadline_ms
                && sample.face_confidence >= 0.65
                && sample.left_eye_open.is_finite()
                && sample.right_eye_open.is_finite()
                && sample.head_yaw.is_finite()
                && sample.head_pitch.is_finite()
        })
        .collect();
    let count = usable.len() as i32;
    let expired = now_ms > deadline_ms;
    if usable.len() < MIN_FRAMES_TO_PASS {
        let reason = if expired {
            "challenge expired without enough reliable face observations"
        } else {
            "collecting reliable face observations"
        };
        return uncertain(
            &challenge,
            reason,
            count,
            count as f32 / MIN_FRAMES_TO_PASS as f32,
            0.0,
        );
    }

    // Repeats and stillness are properties of consecutive frame pairs; the
    // first frame has no predecessor and must not dilute them.
    let pairs = (usable.len() - 1) as f32;
    let repeated = usable[1..]
        .iter()
        .filter(|sample| sample.repeated_frame)
        .count() as f32;
    let low_motion = usable[1..]
        .iter()
        .filter(|sample| sample.motion_score < LOW_MOTION)
        .count() as f32;
    let flat = usable.iter().filter(|sample| sample.flat_texture).count() as f32;
    let total = usable.len() as f32;
    let spoof_risk =
        ((repeated / pairs) * 0.5 + (flat / total) * 0.35 + (low_motion / pairs) * 0.15)
            .clamp(0.0, 1.0);
    if spoof_risk >= SPOOF_THRESHOLD {
        return LivenessChallengeResult {
            state: "possible_presentation_attack".into(),
            challenge,
            completed: false,
            reliable: true,
            progress: 0.0,
            spoof_risk_score: spoof_risk,
            usable_observations: count,
            reason: "reliable observations contain repeated, flat, or motionless frame patterns; human review or another challenge is required".into(),
        };
    }

    // Sign convention, cross-checked against `FaceLandmarkMatrix.yaw` and on
    // real faces: positive yaw = nose toward image-right = the student's own
    // left in an unmirrored frame, so "turn left" increases yaw. Negative
    // pitch = looking up.
    let (base_yaw, base_pitch) = baseline_pose(&usable);
    let completed = match challenge.as_str() {
        "blink" => completed_blink(&usable),
        "turn_left" => usable
            .iter()
            .any(|sample| sample.head_yaw - base_yaw >= MIN_HEAD_MOVEMENT),
        "turn_right" => usable
            .iter()
            .any(|sample| base_yaw - sample.head_yaw >= MIN_HEAD_MOVEMENT),
        "look_up" => usable
            .iter()
            .any(|sample| base_pitch - sample.head_pitch >= MIN_HEAD_MOVEMENT),
        _ => false,
    };
    if completed {
        return LivenessChallengeResult {
            state: "live_challenge_passed".into(),
            challenge,
            completed: true,
            reliable: true,
            progress: 1.0,
            spoof_risk_score: spoof_risk,
            usable_observations: count,
            reason: "the requested live facial movement was observed across reliable frames".into(),
        };
    }

    uncertain(
        &challenge,
        if expired {
            "challenge expired before the requested movement was observed"
        } else {
            "waiting for the requested live facial movement"
        },
        count,
        movement_progress(&challenge, &usable, base_yaw, base_pitch),
        spoof_risk,
    )
}

/// Head pose before the student moves: the median of the first two usable
/// frames.
fn baseline_pose(samples: &[&LivenessObservation]) -> (f32, f32) {
    let first: Vec<&&LivenessObservation> = samples.iter().take(2).collect();
    let yaw = first.iter().map(|sample| sample.head_yaw).sum::<f32>() / first.len() as f32;
    let pitch = first.iter().map(|sample| sample.head_pitch).sum::<f32>() / first.len() as f32;
    (yaw, pitch)
}

fn openness(sample: &LivenessObservation) -> f32 {
    (sample.left_eye_open + sample.right_eye_open) / 2.0
}

/// The student's own open-eye level: the 75th percentile of eye openness in
/// the session, which a blink of a few frames does not move. Absolute
/// thresholds failed students whose open eyes measure narrow.
fn open_eye_level(samples: &[&LivenessObservation]) -> f32 {
    let mut values: Vec<f32> = samples.iter().map(|sample| openness(sample)).collect();
    values.sort_by(|a, b| a.partial_cmp(b).unwrap_or(std::cmp::Ordering::Equal));
    values[((values.len() - 1) * 3) / 4]
}

/// Open, then closed (at most 45% of the student's open level), then open
/// again (at least 75%).
fn completed_blink(samples: &[&LivenessObservation]) -> bool {
    let level = open_eye_level(samples);
    if level < 0.10 {
        return false;
    }
    let open = level * 0.75;
    let closed = level * 0.45;
    let mut saw_open = false;
    let mut saw_closed_after_open = false;
    for sample in samples {
        let value = openness(sample);
        if value >= open {
            if saw_closed_after_open {
                return true;
            }
            saw_open = true;
        } else if saw_open && value <= closed {
            saw_closed_after_open = true;
        }
    }
    false
}

fn movement_progress(
    challenge: &str,
    samples: &[&LivenessObservation],
    base_yaw: f32,
    base_pitch: f32,
) -> f32 {
    match challenge {
        "blink" => {
            let level = open_eye_level(samples).max(0.10);
            let min_open = samples
                .iter()
                .map(|sample| openness(sample))
                .fold(1.0_f32, f32::min);
            (level - min_open) / (level * 0.55)
        }
        "turn_left" => {
            samples
                .iter()
                .map(|sample| sample.head_yaw - base_yaw)
                .fold(0.0, f32::max)
                / MIN_HEAD_MOVEMENT
        }
        "turn_right" => {
            samples
                .iter()
                .map(|sample| base_yaw - sample.head_yaw)
                .fold(0.0, f32::max)
                / MIN_HEAD_MOVEMENT
        }
        "look_up" => {
            samples
                .iter()
                .map(|sample| base_pitch - sample.head_pitch)
                .fold(0.0, f32::max)
                / MIN_HEAD_MOVEMENT
        }
        _ => 0.0,
    }
    .clamp(0.0, 0.9)
}

fn uncertain(
    challenge: &str,
    reason: &str,
    count: i32,
    progress: f32,
    spoof_risk: f32,
) -> LivenessChallengeResult {
    LivenessChallengeResult {
        state: "liveness_uncertain".into(),
        challenge: challenge.into(),
        completed: false,
        reliable: false,
        progress: progress.clamp(0.0, 0.9),
        spoof_risk_score: spoof_risk.clamp(0.0, 1.0),
        usable_observations: count,
        reason: reason.into(),
    }
}

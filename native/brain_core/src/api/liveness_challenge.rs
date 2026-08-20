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

/// Evaluates observable motion only. It never makes a misconduct decision.
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
    let usable: Vec<&LivenessObservation> = observations
        .iter()
        .filter(|sample| {
            sample.timestamp_ms >= started_at_ms
                && sample.timestamp_ms <= now_ms
                && sample.face_confidence >= 0.65
                && sample.left_eye_open.is_finite()
                && sample.right_eye_open.is_finite()
                && sample.head_yaw.is_finite()
                && sample.head_pitch.is_finite()
        })
        .collect();
    let count = usable.len() as i32;
    if usable.len() < 4 {
        let reason = if now_ms > deadline_ms {
            "challenge expired without enough reliable face observations"
        } else {
            "collecting reliable face observations"
        };
        return uncertain(&challenge, reason, count, count as f32 / 4.0, 0.0);
    }

    let repeated = usable.iter().filter(|sample| sample.repeated_frame).count() as f32;
    let flat = usable.iter().filter(|sample| sample.flat_texture).count() as f32;
    let low_motion = usable
        .iter()
        .filter(|sample| sample.motion_score < 0.004)
        .count() as f32;
    let total = usable.len() as f32;
    let spoof_risk =
        ((repeated / total) * 0.5 + (flat / total) * 0.35 + (low_motion / total) * 0.15)
            .clamp(0.0, 1.0);
    if usable.len() >= 6 && spoof_risk >= 0.62 {
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

    let completed = match challenge.as_str() {
        "blink" => completed_blink(&usable),
        "turn_left" => usable.iter().any(|sample| sample.head_yaw <= -0.22),
        "turn_right" => usable.iter().any(|sample| sample.head_yaw >= 0.22),
        "look_up" => usable.iter().any(|sample| sample.head_pitch <= -0.18),
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

    let expired = now_ms > deadline_ms;
    uncertain(
        &challenge,
        if expired {
            "challenge expired before the requested movement was observed"
        } else {
            "waiting for the requested live facial movement"
        },
        count,
        movement_progress(&challenge, &usable),
        spoof_risk,
    )
}

fn completed_blink(samples: &[&LivenessObservation]) -> bool {
    let mut saw_open = false;
    let mut saw_closed_after_open = false;
    for sample in samples {
        let openness = (sample.left_eye_open + sample.right_eye_open) / 2.0;
        if openness >= 0.22 {
            if saw_closed_after_open {
                return true;
            }
            saw_open = true;
        } else if saw_open && openness <= 0.12 {
            saw_closed_after_open = true;
        }
    }
    false
}

fn movement_progress(challenge: &str, samples: &[&LivenessObservation]) -> f32 {
    match challenge {
        "blink" => {
            let min_open = samples
                .iter()
                .map(|sample| (sample.left_eye_open + sample.right_eye_open) / 2.0)
                .fold(1.0_f32, f32::min);
            ((0.22 - min_open) / 0.10).clamp(0.0, 0.9)
        }
        "turn_left" => {
            samples
                .iter()
                .map(|sample| -sample.head_yaw)
                .fold(0.0, f32::max)
                / 0.22
        }
        "turn_right" => {
            samples
                .iter()
                .map(|sample| sample.head_yaw)
                .fold(0.0, f32::max)
                / 0.22
        }
        "look_up" => {
            samples
                .iter()
                .map(|sample| -sample.head_pitch)
                .fold(0.0, f32::max)
                / 0.18
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

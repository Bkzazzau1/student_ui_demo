use std::slice;

use crate::api::analyze_gaze_head_pose_frame;

#[repr(C)]
#[derive(Clone, Copy, Debug, Default)]
pub struct FfiGazeHeadPoseDecision {
    pub available: u8,
    pub gaze_x: f64,
    pub gaze_y: f64,
    pub gaze_z: f64,
    pub yaw_proxy: f64,
    pub pitch_proxy: f64,
    pub roll_proxy: f64,
    pub confidence: f64,
    pub stable_head_pose: u8,
    pub looking_away: u8,
    pub label_code: u32,
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn brain_core_analyze_gaze_head_pose_luma(
    plane_ptr: *const u8,
    plane_len: usize,
    width: u32,
    height: u32,
    bytes_per_row: u32,
    previous_yaw: f64,
    previous_pitch: f64,
    previous_roll: f64,
) -> FfiGazeHeadPoseDecision {
    if plane_ptr.is_null() || plane_len == 0 {
        return FfiGazeHeadPoseDecision::default();
    }

    let bytes = unsafe { slice::from_raw_parts(plane_ptr, plane_len) };
    let Some(decision) = analyze_gaze_head_pose_frame(
        bytes.to_vec(),
        width,
        height,
        bytes_per_row,
        previous_yaw,
        previous_pitch,
        previous_roll,
    ) else {
        return FfiGazeHeadPoseDecision::default();
    };

    FfiGazeHeadPoseDecision {
        available: 1,
        gaze_x: decision.gaze_x,
        gaze_y: decision.gaze_y,
        gaze_z: decision.gaze_z,
        yaw_proxy: decision.yaw_proxy,
        pitch_proxy: decision.pitch_proxy,
        roll_proxy: decision.roll_proxy,
        confidence: decision.confidence,
        stable_head_pose: u8::from(decision.stable_head_pose),
        looking_away: u8::from(decision.looking_away),
        label_code: label_code(&decision.label),
    }
}

fn label_code(label: &str) -> u32 {
    match label {
        "possible_looking_away" => 1,
        "focused_forward" => 2,
        "head_motion_detected" => 3,
        _ => 0,
    }
}

use flutter_rust_bridge::frb;
use serde::{Deserialize, Serialize};

use super::air_board::AirBoardActivitySummary;

#[frb]
#[derive(Clone, Debug, Serialize, Deserialize, PartialEq)]
pub struct HandRegionSignal {
    pub hand_visible: bool,
    pub hand_count: i32,
    pub primary_hand_x: f32,
    pub primary_hand_y: f32,
    pub hand_confidence: f32,
    pub near_keyboard: bool,
    pub near_mouse_or_stylus_area: bool,
    pub near_face: bool,
    pub below_desk_line: bool,
    pub timestamp_ms: i64,
}

#[frb]
#[derive(Clone, Debug, Serialize, Deserialize, PartialEq)]
pub struct HandAirBoardContext {
    pub air_board: AirBoardActivitySummary,
    pub hand: HandRegionSignal,
    pub gaze_zone: String,
    pub screen_zone: String,
    pub now_ms: i64,
}

#[frb]
#[derive(Clone, Debug, Serialize, Deserialize, PartialEq)]
pub struct HandAirBoardDecision {
    pub behaviour_label: String,
    pub attention_level: String,
    pub hand_matches_air_board: bool,
    pub review_required: bool,
    pub student_message: String,
    pub reviewer_summary: String,
}

#[frb(sync)]
pub fn analyze_hand_air_board_context(context: HandAirBoardContext) -> HandAirBoardDecision {
    let hand_reliable = context.hand.hand_visible && context.hand.hand_confidence >= 0.45;
    let air_board_active = context.air_board.active;
    let air_board_writing = context.air_board.currently_writing;
    let hand_in_expected_work_area =
        context.hand.near_keyboard || context.hand.near_mouse_or_stylus_area;

    if air_board_writing
        && hand_reliable
        && hand_in_expected_work_area
        && !context.hand.near_face
        && !context.hand.below_desk_line
    {
        return HandAirBoardDecision {
            behaviour_label: "hand_matches_rough_work".to_string(),
            attention_level: "normal".to_string(),
            hand_matches_air_board: true,
            review_required: false,
            student_message:
                "Your rough-work board is active. Please continue solving inside the exam screen."
                    .to_string(),
            reviewer_summary:
                "Camera hand signal matches active rough-work activity on the Air Board."
                    .to_string(),
        };
    }

    if air_board_writing && !hand_reliable {
        return HandAirBoardDecision {
            behaviour_label: "rough_work_active_hand_not_clear".to_string(),
            attention_level: "medium_attention_required".to_string(),
            hand_matches_air_board: false,
            review_required: true,
            student_message: "Please keep your hands and writing area clearly visible while using the rough-work board.".to_string(),
            reviewer_summary: "Air Board writing was active, but the camera hand signal was not reliable enough.".to_string(),
        };
    }

    if air_board_writing && context.hand.below_desk_line {
        return HandAirBoardDecision {
            behaviour_label: "rough_work_active_hand_below_desk".to_string(),
            attention_level: "high_attention_required".to_string(),
            hand_matches_air_board: false,
            review_required: true,
            student_message: "Please keep your hands visible and continue inside the exam screen.".to_string(),
            reviewer_summary: "Air Board writing was active while the hand appeared below the desk line. Human review is recommended.".to_string(),
        };
    }

    if air_board_writing && context.hand.near_face {
        return HandAirBoardDecision {
            behaviour_label: "rough_work_active_hand_near_face".to_string(),
            attention_level: "medium_attention_required".to_string(),
            hand_matches_air_board: false,
            review_required: true,
            student_message:
                "Please keep your hands in the writing area while using the rough-work board."
                    .to_string(),
            reviewer_summary:
                "Air Board writing was active while the hand appeared near the face area."
                    .to_string(),
        };
    }

    if air_board_active && hand_reliable && hand_in_expected_work_area {
        return HandAirBoardDecision {
            behaviour_label: "hand_ready_for_rough_work".to_string(),
            attention_level: "normal".to_string(),
            hand_matches_air_board: true,
            review_required: false,
            student_message:
                "Your rough-work board is ready. You may continue solving inside the exam screen."
                    .to_string(),
            reviewer_summary:
                "Hand activity is within the expected keyboard, mouse, stylus, or writing area."
                    .to_string(),
        };
    }

    if !air_board_active && hand_reliable && context.hand.below_desk_line {
        return HandAirBoardDecision {
            behaviour_label: "hand_below_desk_without_rough_work".to_string(),
            attention_level: "medium_attention_required".to_string(),
            hand_matches_air_board: false,
            review_required: true,
            student_message: "Please keep your hands visible in the exam area.".to_string(),
            reviewer_summary:
                "Hand appeared below the desk line while the Air Board was not active.".to_string(),
        };
    }

    HandAirBoardDecision {
        behaviour_label: "hand_air_board_neutral".to_string(),
        attention_level: "normal".to_string(),
        hand_matches_air_board: false,
        review_required: false,
        student_message: "Please continue your exam carefully.".to_string(),
        reviewer_summary: "No hand and Air Board concern was detected from the available signals."
            .to_string(),
    }
}

use flutter_rust_bridge::frb;
use serde::{Deserialize, Serialize};

use super::air_board::AirBoardActivitySummary;
use super::gaze_calibration::GazeZonePrediction;

#[frb]
#[derive(Clone, Debug, Serialize, Deserialize, PartialEq)]
pub struct ExamBehaviourContext {
    pub gaze: GazeZonePrediction,
    pub air_board: AirBoardActivitySummary,
    pub head_pose_attention_level: String,
    pub audio_attention_level: String,
    pub screen_attention_level: String,
    pub external_voice_detected: bool,
    pub screen_left: bool,
    pub now_ms: i64,
}

#[frb]
#[derive(Clone, Debug, Serialize, Deserialize, PartialEq)]
pub struct ExamBehaviourDecision {
    pub behaviour_label: String,
    pub attention_level: String,
    pub normal_calculation_behaviour: bool,
    pub review_required: bool,
    pub suggested_student_message: String,
    pub reviewer_summary: String,
}

#[frb(sync)]
pub fn analyze_exam_behaviour_context(context: ExamBehaviourContext) -> ExamBehaviourDecision {
    let gaze_zone = context.gaze.zone.as_str();
    let air_board_active = context.air_board.active;
    let air_board_writing = context.air_board.currently_writing;

    let normal_calculation_behaviour = air_board_active
        && (gaze_zone == "air_board" || gaze_zone == "question_area" || gaze_zone == "answer_area")
        && (air_board_writing || context.air_board.total_points > 0)
        && !context.external_voice_detected
        && !context.screen_left;

    if normal_calculation_behaviour {
        return ExamBehaviourDecision {
            behaviour_label: "normal_rough_work".to_string(),
            attention_level: "normal".to_string(),
            normal_calculation_behaviour: true,
            review_required: false,
            suggested_student_message: "Your rough-work board is active. Please continue solving inside the exam screen.".to_string(),
            reviewer_summary: "Student activity appears consistent with normal calculation behaviour using the rough-work board.".to_string(),
        };
    }

    if context.external_voice_detected
        && (gaze_zone == "outside_screen" || gaze_zone == "downward_gaze")
    {
        return ExamBehaviourDecision {
            behaviour_label: "external_voice_with_away_gaze".to_string(),
            attention_level: "high_attention_required".to_string(),
            normal_calculation_behaviour: false,
            review_required: true,
            suggested_student_message: "A voice was noticed. Please keep your exam area quiet and continue inside the exam screen.".to_string(),
            reviewer_summary: "Possible external voice occurred while gaze was away from the exam screen. Human review is recommended.".to_string(),
        };
    }

    if context.screen_left {
        return ExamBehaviourDecision {
            behaviour_label: "exam_screen_left".to_string(),
            attention_level: "high_attention_required".to_string(),
            normal_calculation_behaviour: false,
            review_required: true,
            suggested_student_message:
                "Please return to the exam screen. Leaving the exam screen may require review."
                    .to_string(),
            reviewer_summary: "The candidate moved away from the secure exam screen.".to_string(),
        };
    }

    if gaze_zone == "downward_gaze"
        && !air_board_writing
        && context.air_board.idle_duration_ms > 20_000
    {
        return ExamBehaviourDecision {
            behaviour_label: "downward_gaze_without_rough_work".to_string(),
            attention_level: "medium_attention_required".to_string(),
            normal_calculation_behaviour: false,
            review_required: true,
            suggested_student_message: "Please keep your rough work inside the exam screen."
                .to_string(),
            reviewer_summary:
                "Downward gaze continued while no rough-work board activity was recorded."
                    .to_string(),
        };
    }

    if context.air_board.attention_level != "normal" {
        return ExamBehaviourDecision {
            behaviour_label: "rough_work_needs_attention".to_string(),
            attention_level: context.air_board.attention_level.clone(),
            normal_calculation_behaviour: false,
            review_required: context.air_board.attention_level != "normal",
            suggested_student_message: "Please continue solving inside the exam screen."
                .to_string(),
            reviewer_summary: context.air_board.reason.clone(),
        };
    }

    if context.gaze.attention_level != "normal" {
        return ExamBehaviourDecision {
            behaviour_label: "gaze_signal_needs_attention".to_string(),
            attention_level: context.gaze.attention_level.clone(),
            normal_calculation_behaviour: false,
            review_required: true,
            suggested_student_message:
                "Please make sure your face is clearly visible and continue your exam.".to_string(),
            reviewer_summary: context.gaze.reason.clone(),
        };
    }

    ExamBehaviourDecision {
        behaviour_label: "normal_exam_activity".to_string(),
        attention_level: strongest_attention_level(vec![
            context.head_pose_attention_level,
            context.audio_attention_level,
            context.screen_attention_level,
        ]),
        normal_calculation_behaviour: false,
        review_required: false,
        suggested_student_message: "Please continue your exam carefully.".to_string(),
        reviewer_summary: "Exam activity is within expected range.".to_string(),
    }
}

fn strongest_attention_level(levels: Vec<String>) -> String {
    if levels.iter().any(|level| level == "urgent_review_required") {
        "urgent_review_required".to_string()
    } else if levels
        .iter()
        .any(|level| level == "high_attention_required")
    {
        "high_attention_required".to_string()
    } else if levels
        .iter()
        .any(|level| level == "medium_attention_required")
    {
        "medium_attention_required".to_string()
    } else {
        "normal".to_string()
    }
}

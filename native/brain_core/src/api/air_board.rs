use flutter_rust_bridge::frb;
use serde::{Deserialize, Serialize};

#[frb]
#[derive(Clone, Debug, Serialize, Deserialize, PartialEq)]
pub struct AirBoardStrokePoint {
    pub x: f32,
    pub y: f32,
    pub pressure: f32,
    pub timestamp_ms: i64,
}

#[frb]
#[derive(Clone, Debug, Serialize, Deserialize, PartialEq)]
pub struct AirBoardStroke {
    pub stroke_id: String,
    pub page_index: i32,
    pub tool: String,
    pub points: Vec<AirBoardStrokePoint>,
    pub started_at_ms: i64,
    pub ended_at_ms: i64,
}

#[frb]
#[derive(Clone, Debug, Serialize, Deserialize, PartialEq)]
pub struct AirBoardContext {
    pub is_open: bool,
    pub active_page_index: i32,
    pub page_count: i32,
    pub strokes: Vec<AirBoardStroke>,
    pub last_activity_at_ms: i64,
    pub opened_at_ms: i64,
    pub now_ms: i64,
}

#[frb]
#[derive(Clone, Debug, Serialize, Deserialize, PartialEq)]
pub struct AirBoardActivitySummary {
    pub active: bool,
    pub currently_writing: bool,
    pub stroke_count: i32,
    pub page_count: i32,
    pub active_page_index: i32,
    pub total_points: i32,
    pub active_duration_ms: i64,
    pub idle_duration_ms: i64,
    pub attention_level: String,
    pub reason: String,
}

#[frb(sync)]
pub fn analyze_air_board_context(context: AirBoardContext) -> AirBoardActivitySummary {
    let stroke_count = context.strokes.len() as i32;
    let total_points = context
        .strokes
        .iter()
        .map(|stroke| stroke.points.len() as i32)
        .sum::<i32>();

    let active_duration_ms = if context.is_open && context.opened_at_ms > 0 {
        context.now_ms.saturating_sub(context.opened_at_ms)
    } else {
        0
    };

    let idle_duration_ms = if context.last_activity_at_ms > 0 {
        context.now_ms.saturating_sub(context.last_activity_at_ms)
    } else {
        active_duration_ms
    };

    let currently_writing = context.is_open && idle_duration_ms <= 4_000 && total_points > 0;

    let (attention_level, reason) = if !context.is_open {
        ("normal", "rough-work board is closed")
    } else if currently_writing {
        (
            "normal",
            "rough-work board is active and writing is in progress",
        )
    } else if total_points == 0 && active_duration_ms > 60_000 {
        (
            "medium_attention_required",
            "rough-work board has been open without writing activity",
        )
    } else if idle_duration_ms > 120_000 {
        (
            "medium_attention_required",
            "rough-work board is open but has been idle for a long time",
        )
    } else {
        (
            "normal",
            "rough-work board activity is within expected range",
        )
    };

    AirBoardActivitySummary {
        active: context.is_open,
        currently_writing,
        stroke_count,
        page_count: context.page_count.max(0),
        active_page_index: context.active_page_index.max(0),
        total_points,
        active_duration_ms,
        idle_duration_ms,
        attention_level: attention_level.to_string(),
        reason: reason.to_string(),
    }
}

#[frb(sync)]
pub fn build_air_board_evidence_manifest(
    session_id: String,
    attempt_id: String,
    summary: AirBoardActivitySummary,
) -> String {
    format!(
        "air_board:{}:{}:active={}:strokes={}:points={}:duration_ms={}:attention={}",
        session_id,
        attempt_id,
        summary.active,
        summary.stroke_count,
        summary.total_points,
        summary.active_duration_ms,
        summary.attention_level
    )
}

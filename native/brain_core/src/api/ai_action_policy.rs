use flutter_rust_bridge::frb;

#[frb]
#[derive(Clone, Debug)]
pub struct AiActionAuthorization {
    pub action: String,
    pub allowed: bool,
    pub requires_user_consent: bool,
    pub reason: String,
}

/// Rust is the final authority for every action proposed by the Python runtime.
/// Unknown or high-impact actions are denied by default.
#[frb(sync)]
pub fn authorize_ai_action(action: String, exam_active: bool) -> AiActionAuthorization {
    let normalized = action.trim().to_ascii_lowercase();
    match normalized.as_str() {
        "capture_review_snapshot" if exam_active => AiActionAuthorization {
            action: normalized,
            allowed: true,
            requires_user_consent: false,
            reason: "Allowed during an active, consented proctored exam".into(),
        },
        "capture_review_snapshot" => AiActionAuthorization {
            action: normalized,
            allowed: false,
            requires_user_consent: false,
            reason: "Review evidence may only be captured during an active exam".into(),
        },
        "request_identity_recheck" => AiActionAuthorization {
            action: normalized,
            allowed: exam_active,
            requires_user_consent: true,
            reason: if exam_active {
                "A visible identity recheck requires student consent".into()
            } else {
                "Identity recheck is unavailable outside an active exam".into()
            },
        },
        _ => AiActionAuthorization {
            action: normalized,
            allowed: false,
            requires_user_consent: false,
            reason: "Action is not present in the Rust allow-list".into(),
        },
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn allows_snapshot_only_during_active_exam() {
        assert!(authorize_ai_action("capture_review_snapshot".into(), true).allowed);
        assert!(!authorize_ai_action("capture_review_snapshot".into(), false).allowed);
    }

    #[test]
    fn unknown_actions_are_denied() {
        let result = authorize_ai_action("run_shell_command".into(), true);
        assert!(!result.allowed);
        assert!(result.reason.contains("not present"));
    }

    #[test]
    fn identity_recheck_requires_consent() {
        let result = authorize_ai_action("request_identity_recheck".into(), true);
        assert!(result.allowed);
        assert!(result.requires_user_consent);
    }
}

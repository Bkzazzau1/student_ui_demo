use brain_core::api::analyze_secure_lockdown_report;

#[test]
fn clean_lockdown_report_passes() {
    let result = analyze_secure_lockdown_report(
        "windows".to_string(),
        "explorer.exe student_ui_demo.exe system".to_string(),
        Some(1),
    );

    assert!(result.platform_supported);
    assert!(result.ready);
    assert_eq!(result.display_count, Some(1));
    assert!(result.prohibited_processes.is_empty());
}

#[test]
fn detects_prohibited_processes() {
    let result = analyze_secure_lockdown_report(
        "windows".to_string(),
        "AnyDesk.exe OBS64.exe chrome.exe ChatGPT".to_string(),
        Some(1),
    );

    assert!(result.platform_supported);
    assert!(!result.ready);
    assert!(result.prohibited_processes.iter().any(|item| item == "anydesk"));
    assert!(result.prohibited_processes.iter().any(|item| item == "obs64"));
    assert!(result.prohibited_processes.iter().any(|item| item == "chrome.exe"));
    assert!(result.prohibited_processes.iter().any(|item| item == "chatgpt"));
}

#[test]
fn blocks_multiple_displays() {
    let result = analyze_secure_lockdown_report(
        "linux".to_string(),
        "student_ui_demo".to_string(),
        Some(2),
    );

    assert!(result.platform_supported);
    assert!(!result.ready);
    assert_eq!(result.display_count, Some(2));
    assert!(result.findings.iter().any(|finding| finding.code == "multiple_displays_detected"));
}

#[test]
fn unsupported_platform_is_not_ready() {
    let result = analyze_secure_lockdown_report(
        "android".to_string(),
        "student_ui_demo".to_string(),
        None,
    );

    assert!(!result.platform_supported);
    assert!(!result.ready);
    assert!(result.findings.iter().any(|finding| finding.code == "unsupported_platform"));
}

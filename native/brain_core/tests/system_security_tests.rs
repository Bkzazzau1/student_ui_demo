use brain_core::api::analyze_system_security_report;

#[test]
fn passes_clean_internal_audio_report() {
    let report = "Internal Microphone Microphone Array Realtek High Definition Audio";
    let result = analyze_system_security_report(report.to_string(), "windows".to_string());

    assert!(result.platform_supported);
    assert!(result.ready);
    assert!(!result.bluetooth_detected);
    assert!(!result.external_audio_detected);
    assert!(!result.usb_risk_detected);
    assert!(result.hard_findings.is_empty());
}

#[test]
fn blocks_wireless_audio_and_usb_capture() {
    let report = "Bluetooth AirPods USB Capture Card External Microphone";
    let result = analyze_system_security_report(report.to_string(), "windows".to_string());

    assert!(result.platform_supported);
    assert!(!result.ready);
    assert!(result.bluetooth_detected);
    assert!(result.external_audio_detected);
    assert!(result.usb_risk_detected);
    assert!(!result.hard_findings.is_empty());
}

#[test]
fn blocks_virtual_machine_container_and_virtual_camera() {
    let report = "VMware Docker OBS Virtual Camera v4l2loopback";
    let result = analyze_system_security_report(report.to_string(), "linux".to_string());

    assert!(!result.ready);
    assert!(result.virtualization_detected);
    assert!(result.container_detected);
    assert!(result.virtual_camera_detected);
}

#[test]
fn rejects_unsupported_platform() {
    let result = analyze_system_security_report("anything".to_string(), "android".to_string());

    assert!(!result.ready);
    assert!(!result.platform_supported);
    assert!(result.unknown_device_state);
}

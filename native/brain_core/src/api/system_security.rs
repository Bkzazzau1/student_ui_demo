use std::process::{Command, Stdio};
use std::time::{Duration, Instant};

use flutter_rust_bridge::frb;

#[frb]
#[derive(Clone, Debug)]
pub struct NativeSystemSecurityReviewResult {
    pub ready: bool,
    pub platform_supported: bool,
    pub bluetooth_detected: bool,
    pub external_audio_detected: bool,
    pub usb_risk_detected: bool,
    pub virtualization_detected: bool,
    pub virtualization_warning_detected: bool,
    pub container_detected: bool,
    pub virtual_camera_detected: bool,
    pub unknown_device_state: bool,
    pub findings: Vec<String>,
    pub hard_findings: Vec<String>,
    pub warning_findings: Vec<String>,
    pub message: String,
}

#[frb(sync)]
pub fn analyze_system_security_report(
    report: String,
    platform_name: String,
) -> NativeSystemSecurityReviewResult {
    analyse_output(&report, &platform_name)
}

pub fn collect_system_security_report(platform_name: String) -> Result<String, String> {
    let platform = normalized_platform(&platform_name);
    if platform == "windows" {
        run_command(
            "powershell",
            &[
                "-NoProfile",
                "-ExecutionPolicy",
                "Bypass",
                "-Command",
                r#"
$devices = Get-PnpDevice -PresentOnly | Where-Object {
  $_.Status -eq 'OK' -and (
    $_.Class -match 'Bluetooth|AudioEndpoint|Media|USB|Camera|Image' -or
    $_.FriendlyName -match 'Bluetooth|Headset|Headphone|Earbud|AirPods|Hands-Free|Microphone|Mic|Audio|Wireless|USB|Capture|Camera'
  )
} | Select-Object Class,FriendlyName,Status,InstanceId
$computer = Get-CimInstance Win32_ComputerSystem | Select-Object Manufacturer,Model,HypervisorPresent
$bios = Get-CimInstance Win32_BIOS | Select-Object Manufacturer,SerialNumber,Version
$camera = Get-PnpDevice -PresentOnly | Where-Object {
  $_.Class -match 'Camera|Image|Media' -or
  $_.FriendlyName -match 'Camera|Webcam|Virtual|OBS|ManyCam|DroidCam|Snap|XSplit|NDI|SplitCam|Camo|EpocCam|iVCam'
} | Select-Object Class,FriendlyName,InstanceId,Status
[ordered]@{
  devices = $devices
  computer = $computer
  bios = $bios
  camera = $camera
} | ConvertTo-Json -Compress -Depth 4
"#,
            ],
        )
    } else if platform == "macos" {
        run_command(
            "sh",
            &[
                "-c",
                "system_profiler SPBluetoothDataType SPAudioDataType SPUSBDataType SPCameraDataType 2>/dev/null",
            ],
        )
    } else if platform == "linux" {
        run_command(
            "sh",
            &[
                "-c",
                r#"(
  bluetoothctl devices Connected 2>/dev/null
  pactl list short sources 2>/dev/null
  arecord -l 2>/dev/null
  lsusb 2>/dev/null
  systemd-detect-virt 2>/dev/null || true
  test -f /.dockerenv && echo dockerenv_present || true
  cat /proc/1/cgroup 2>/dev/null
  cat /sys/class/dmi/id/product_name 2>/dev/null
  cat /sys/class/dmi/id/sys_vendor 2>/dev/null
  lsmod 2>/dev/null | grep -Ei "v4l2loopback|akvcam|virtual" || true
  v4l2-ctl --list-devices 2>/dev/null || true
) | tr "\n" " ""#,
            ],
        )
    } else {
        Err("unsupported platform for native system security review".to_string())
    }
}

pub fn run_system_security_review(platform_name: String) -> NativeSystemSecurityReviewResult {
    let platform = normalized_platform(&platform_name);
    if !is_supported_platform(&platform) {
        return unsupported_result();
    }

    match collect_system_security_report(platform.clone()) {
        Ok(report) => analyse_output(&report, &platform),
        Err(error) => NativeSystemSecurityReviewResult {
            ready: false,
            platform_supported: true,
            bluetooth_detected: false,
            external_audio_detected: false,
            usb_risk_detected: false,
            virtualization_detected: false,
            virtualization_warning_detected: false,
            container_detected: false,
            virtual_camera_detected: false,
            unknown_device_state: true,
            findings: vec![format!("System devices could not be verified: {error}")],
            hard_findings: vec![format!("System devices could not be verified: {error}")],
            warning_findings: Vec::new(),
            message: "System review could not verify connected devices. Contact the invigilator."
                .to_string(),
        },
    }
}

fn analyse_output(output: &str, platform_name: &str) -> NativeSystemSecurityReviewResult {
    let platform = normalized_platform(platform_name);
    if !is_supported_platform(&platform) {
        return unsupported_result();
    }

    let text = normalise(output);
    let mut hard_findings = Vec::<String>::new();
    let mut warning_findings = Vec::<String>::new();

    let bluetooth_detected = contains_any(
        &text,
        &[
            "bluetooth",
            "hands-free",
            "handsfree",
            "airpods",
            "earbuds",
            "wireless headset",
            "wireless headphone",
            "bt audio",
        ],
    );

    let external_audio_detected = contains_any(
        &text,
        &[
            "headset",
            "headphone",
            "earphone",
            "earbud",
            "airpods",
            "hands-free",
            "handsfree",
            "usb audio",
            "usb microphone",
            "external microphone",
            "external mic",
            "wireless microphone",
            "wireless mic",
            "audio capture",
            "capture card",
            "webcam microphone",
            "camera microphone",
        ],
    );

    let usb_risk_detected = contains_any(
        &text,
        &[
            "usb microphone",
            "usb audio",
            "usb headset",
            "usb headphones",
            "usb camera",
            "usb capture",
            "capture card",
            "elgato",
            "aver media",
            "avermedia",
        ],
    );

    let virtualization_warning_detected = platform == "windows"
        && contains_any(
            &text,
            &[
                "hypervisorpresent: true",
                "hypervisorpresent=true",
                "hypervisorpresent true",
            ],
        );

    let virtualization_detected = contains_any(
        &text,
        &[
            "vmware",
            "virtualbox",
            "oracle vm",
            "qemu",
            "kvm",
            "xen",
            "parallels",
            "virtio",
            "hyper-v virtual machine",
            "microsoft corporation virtual machine",
            "virtual machine platform device",
        ],
    );

    let container_detected = contains_any(
        &text,
        &[
            "docker",
            "containerd",
            "kubepods",
            "podman",
            "lxc",
            "wsl",
            "moby",
            "dockerenv_present",
        ],
    );

    let virtual_camera_detected = contains_any(
        &text,
        &[
            "obs virtual camera",
            "virtual camera",
            "virtual webcam",
            "manycam",
            "snap camera",
            "droidcam",
            "xsplit",
            "ndi webcam",
            "splitcam",
            "camo",
            "epoccam",
            "ivcam",
            "v4l2loopback",
            "akvcam",
            "webcamoid",
        ],
    );

    let known_safe_audio = contains_any(
        &text,
        &[
            "microphone array",
            "internal microphone",
            "built-in microphone",
            "integrated microphone",
            "realtek",
            "intel smart sound",
            "high definition audio",
            "default source",
        ],
    );

    let audio_mentioned = contains_any(
        &text,
        &["microphone", " mic ", "audio", "source", "capture"],
    );
    let unknown_device_state = audio_mentioned
        && !known_safe_audio
        && !external_audio_detected
        && !usb_risk_detected
        && !bluetooth_detected;

    if bluetooth_detected {
        hard_findings.push("Bluetooth or wireless device detected. Turn off Bluetooth and disconnect wireless audio before exam startup.".to_string());
    }
    if external_audio_detected {
        hard_findings.push(
            "External audio device detected. Use only the built-in microphone and speaker."
                .to_string(),
        );
    }
    if usb_risk_detected {
        hard_findings.push("USB audio, camera, or capture device risk detected. Remove external exam-risk devices.".to_string());
    }
    if virtualization_detected {
        hard_findings.push("Real virtual machine environment detected. Use a physical desktop device for this exam.".to_string());
    }
    if container_detected {
        hard_findings.push(
            "Container, WSL, or sandbox environment detected. Close it before this exam."
                .to_string(),
        );
    }
    if virtual_camera_detected {
        hard_findings.push("Virtual camera software detected. Disable virtual camera drivers and use a physical webcam.".to_string());
    }
    if unknown_device_state {
        hard_findings.push(
            "Connected audio device state is unclear. Invigilator confirmation is required."
                .to_string(),
        );
    }
    if virtualization_warning_detected && !virtualization_detected {
        warning_findings.push("Windows hypervisor security feature detected. This can happen on normal Windows 11 devices using Hyper-V, WSL2, Docker Desktop, or Core Isolation. It is recorded for review but does not block by itself.".to_string());
    }

    let ready = hard_findings.is_empty();
    let mut findings = Vec::<String>::new();
    findings.extend(hard_findings.clone());
    findings.extend(warning_findings.clone());
    if findings.is_empty() {
        findings.push("System device review passed.".to_string());
    }

    let message = if ready {
        if warning_findings.is_empty() {
            "System device review passed. Continue to the next step.".to_string()
        } else {
            "System device review passed with notes for review.".to_string()
        }
    } else {
        "System review found device or environment issues that must be resolved before this exam can start.".to_string()
    };

    NativeSystemSecurityReviewResult {
        ready,
        platform_supported: true,
        bluetooth_detected,
        external_audio_detected,
        usb_risk_detected,
        virtualization_detected,
        virtualization_warning_detected,
        container_detected,
        virtual_camera_detected,
        unknown_device_state,
        findings,
        hard_findings,
        warning_findings,
        message,
    }
}

fn unsupported_result() -> NativeSystemSecurityReviewResult {
    NativeSystemSecurityReviewResult {
        ready: false,
        platform_supported: false,
        bluetooth_detected: false,
        external_audio_detected: false,
        usb_risk_detected: false,
        virtualization_detected: false,
        virtualization_warning_detected: false,
        container_detected: false,
        virtual_camera_detected: false,
        unknown_device_state: true,
        findings: vec![
            "Unsupported platform. Use Windows, macOS, or Linux desktop app.".to_string(),
        ],
        hard_findings: vec![
            "Unsupported platform. Use Windows, macOS, or Linux desktop app.".to_string(),
        ],
        warning_findings: Vec::new(),
        message: "Desktop system review is required before this exam can start.".to_string(),
    }
}

fn is_supported_platform(platform: &str) -> bool {
    matches!(platform, "windows" | "linux" | "macos")
}

fn normalized_platform(platform_name: &str) -> String {
    let value = platform_name.trim().to_lowercase();
    match value.as_str() {
        "mac" | "darwin" | "macos" | "osx" => "macos".to_string(),
        "win" | "windows" => "windows".to_string(),
        "linux" => "linux".to_string(),
        "" | "auto" | "current" => current_platform_name(),
        _ => value,
    }
}

fn current_platform_name() -> String {
    if cfg!(target_os = "windows") {
        "windows".to_string()
    } else if cfg!(target_os = "macos") {
        "macos".to_string()
    } else if cfg!(target_os = "linux") {
        "linux".to_string()
    } else {
        "unknown".to_string()
    }
}

fn contains_any(text: &str, patterns: &[&str]) -> bool {
    patterns.iter().any(|pattern| text.contains(pattern))
}

fn normalise(output: &str) -> String {
    output
        .replace(['{', '}', '[', ']', '"', '\'', ',', ':'], " ")
        .split_whitespace()
        .collect::<Vec<_>>()
        .join(" ")
        .to_lowercase()
}

fn run_command(executable: &str, arguments: &[&str]) -> Result<String, String> {
    let mut child = Command::new(executable)
        .args(arguments)
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .map_err(|error| error.to_string())?;
    let started = Instant::now();

    loop {
        match child.try_wait() {
            Ok(Some(_)) => break,
            Ok(None) => {
                if started.elapsed() >= command_timeout_hint() {
                    let _ = child.kill();
                    let _ = child.wait();
                    return Err("device report timed out after 7 seconds".to_string());
                }
                std::thread::sleep(Duration::from_millis(50));
            }
            Err(error) => return Err(error.to_string()),
        }
    }

    let output = child
        .wait_with_output()
        .map_err(|error| error.to_string())?;
    let stdout = String::from_utf8_lossy(&output.stdout);
    let stderr = String::from_utf8_lossy(&output.stderr);
    let combined = format!("{}\n{}", stdout, stderr).trim().to_string();
    if combined.is_empty() {
        return Err("empty system security report".to_string());
    }
    Ok(combined)
}

#[allow(dead_code)]
fn command_timeout_hint() -> Duration {
    Duration::from_secs(7)
}

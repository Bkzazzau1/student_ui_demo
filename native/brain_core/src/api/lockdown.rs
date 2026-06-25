use std::process::{Command, Stdio};
use std::time::{Duration, Instant};

use flutter_rust_bridge::frb;

#[frb]
#[derive(Clone, Debug)]
pub struct NativeLockdownFinding {
    pub code: String,
    pub message: String,
    pub severity: String,
}

#[frb]
#[derive(Clone, Debug)]
pub struct NativeSecureLockdownReviewResult {
    pub ready: bool,
    pub platform_supported: bool,
    pub platform_name: String,
    pub display_count: Option<i32>,
    pub prohibited_processes: Vec<String>,
    pub findings: Vec<NativeLockdownFinding>,
}

#[frb(sync)]
pub fn analyze_secure_lockdown_report(
    platform_name: String,
    process_report: String,
    display_count: Option<i32>,
) -> NativeSecureLockdownReviewResult {
    analyse_lockdown(&normalized_platform(&platform_name), &process_report, display_count)
}

pub fn collect_lockdown_process_report(platform_name: String) -> Result<String, String> {
    let platform = normalized_platform(&platform_name);
    if platform == "windows" {
        run_command(
            "powershell",
            &[
                "-NoProfile",
                "-ExecutionPolicy",
                "Bypass",
                "-Command",
                r#"Get-Process | Select-Object ProcessName,Path | ConvertTo-Json -Compress -Depth 2"#,
            ],
        )
    } else if platform == "macos" || platform == "linux" {
        run_command("sh", &["-c", "ps -axo comm,args 2>/dev/null"])
    } else {
        Err("unsupported platform for secure lockdown process review".to_string())
    }
}

pub fn collect_lockdown_display_count(platform_name: String) -> Result<Option<i32>, String> {
    let platform = normalized_platform(&platform_name);
    let output = if platform == "windows" {
        run_command(
            "powershell",
            &[
                "-NoProfile",
                "-ExecutionPolicy",
                "Bypass",
                "-Command",
                r#"Add-Type -AssemblyName System.Windows.Forms; [System.Windows.Forms.Screen]::AllScreens.Count"#,
            ],
        )?
    } else if platform == "macos" {
        run_command(
            "sh",
            &[
                "-c",
                "system_profiler SPDisplaysDataType 2>/dev/null | grep -c 'Resolution:'",
            ],
        )?
    } else if platform == "linux" {
        run_command(
            "sh",
            &[
                "-c",
                "xrandr --listmonitors 2>/dev/null | awk '/Monitors:/ {print $2}'",
            ],
        )?
    } else {
        return Err("unsupported platform for secure lockdown display review".to_string());
    };

    Ok(parse_display_count(&output))
}

pub fn run_secure_lockdown_review(platform_name: String) -> NativeSecureLockdownReviewResult {
    let platform = normalized_platform(&platform_name);
    if !is_supported_platform(&platform) {
        return unsupported_result(platform);
    }

    let process_report = collect_lockdown_process_report(platform.clone()).unwrap_or_default();
    let display_count = collect_lockdown_display_count(platform.clone()).unwrap_or(None);
    analyse_lockdown(&platform, &process_report, display_count)
}

fn analyse_lockdown(
    platform: &str,
    process_report: &str,
    display_count: Option<i32>,
) -> NativeSecureLockdownReviewResult {
    if !is_supported_platform(platform) {
        return unsupported_result(platform.to_string());
    }

    let mut findings = Vec::<NativeLockdownFinding>::new();
    let prohibited_processes = detect_prohibited_processes(process_report);

    if !prohibited_processes.is_empty() {
        findings.push(NativeLockdownFinding {
            code: "prohibited_process_detected".to_string(),
            severity: "critical".to_string(),
            message: format!(
                "Close prohibited apps before continuing: {}.",
                prohibited_processes
                    .iter()
                    .take(4)
                    .cloned()
                    .collect::<Vec<_>>()
                    .join(", ")
            ),
        });
    }

    if let Some(count) = display_count {
        if count > 1 {
            findings.push(NativeLockdownFinding {
                code: "multiple_displays_detected".to_string(),
                severity: "critical".to_string(),
                message: "Only one display is allowed during a secure exam.".to_string(),
            });
        }
    }

    if findings.is_empty() {
        findings.push(NativeLockdownFinding {
            code: "secure_lockdown_ready".to_string(),
            severity: "info".to_string(),
            message: "Secure lockdown native checks are active.".to_string(),
        });
    }

    let ready = prohibited_processes.is_empty()
        && display_count.map(|count| count <= 1).unwrap_or(true)
        && !findings.iter().any(|finding| finding.severity == "critical");

    NativeSecureLockdownReviewResult {
        ready,
        platform_supported: true,
        platform_name: platform.to_string(),
        display_count,
        prohibited_processes,
        findings,
    }
}

fn unsupported_result(platform_name: String) -> NativeSecureLockdownReviewResult {
    NativeSecureLockdownReviewResult {
        ready: false,
        platform_supported: false,
        platform_name,
        display_count: None,
        prohibited_processes: Vec::new(),
        findings: vec![NativeLockdownFinding {
            code: "unsupported_platform".to_string(),
            severity: "critical".to_string(),
            message: "Secure lockdown requires the desktop app on Windows, macOS, or Linux."
                .to_string(),
        }],
    }
}

fn detect_prohibited_processes(report: &str) -> Vec<String> {
    let text = normalise(report);
    let mut matches = Vec::<String>::new();
    for term in prohibited_process_terms() {
        if text.contains(&term.to_lowercase()) && !matches.iter().any(|item| item == term) {
            matches.push(term.to_string());
        }
    }
    matches.sort();
    matches
}

fn prohibited_process_terms() -> &'static [&'static str] {
    &[
        "anydesk",
        "teamviewer",
        "rustdesk",
        "chrome remote desktop",
        "remotedesktop",
        "remote desktop",
        "mstsc",
        "parsecd",
        "parsec",
        "vnc",
        "ultravnc",
        "tightvnc",
        "obs",
        "obs64",
        "screen recorder",
        "camtasia",
        "bandicam",
        "xsplit",
        "manycam",
        "droidcam",
        "snap camera",
        "virtualbox",
        "vmware",
        "qemu",
        "parallels",
        "hyper-v",
        "zoom",
        "teams",
        "telegram",
        "whatsapp",
        "discord",
        "slack",
        "chrome.exe",
        "msedge.exe",
        "firefox.exe",
        "brave.exe",
        "opera.exe",
        "chatgpt",
        "copilot",
    ]
}

fn parse_display_count(output: &str) -> Option<i32> {
    output
        .split_whitespace()
        .find_map(|part| part.trim().parse::<i32>().ok())
        .filter(|count| *count > 0)
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
                    return Err("secure lockdown report timed out after 5 seconds".to_string());
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
        return Err("empty secure lockdown report".to_string());
    }
    Ok(combined)
}

fn command_timeout_hint() -> Duration {
    Duration::from_secs(5)
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import 'native_secure_lockdown_review_bridge.dart';

class SecureLockdownFinding {
  const SecureLockdownFinding({
    required this.code,
    required this.message,
    required this.severity,
  });

  final String code;
  final String message;
  final String severity;

  Map<String, Object?> toJson() => <String, Object?>{
    'code': code,
    'message': message,
    'severity': severity,
  };
}

class SecureLockdownSnapshot {
  const SecureLockdownSnapshot({
    required this.lockdownActive,
    required this.platformSupported,
    required this.platformName,
    required this.displayCount,
    required this.prohibitedProcesses,
    required this.clipboardCleared,
    required this.findings,
    required this.capturedAt,
  });

  final bool lockdownActive;
  final bool platformSupported;
  final String platformName;
  final int? displayCount;
  final List<String> prohibitedProcesses;
  final bool clipboardCleared;
  final List<SecureLockdownFinding> findings;
  final DateTime capturedAt;

  bool get ready =>
      lockdownActive &&
      platformSupported &&
      prohibitedProcesses.isEmpty &&
      (displayCount == null || displayCount! <= 1) &&
      !findings.any((finding) => finding.severity == 'critical');

  Map<String, Object?> toJson() => <String, Object?>{
    'lockdown_active': lockdownActive,
    'ready': ready,
    'platform_supported': platformSupported,
    'platform_name': platformName,
    'display_count': displayCount,
    'prohibited_processes': prohibitedProcesses,
    'clipboard_cleared': clipboardCleared,
    'findings': findings.map((finding) => finding.toJson()).toList(),
    'captured_at': capturedAt.toUtc().toIso8601String(),
  };
}

class SecureLockdownSessionService {
  SecureLockdownSessionService({
    this.commandTimeout = const Duration(seconds: 5),
    NativeSecureLockdownReviewBridge nativeBridge =
        const GeneratedNativeSecureLockdownReviewBridge(),
  }) : _nativeBridge = nativeBridge;

  final Duration commandTimeout;
  final NativeSecureLockdownReviewBridge _nativeBridge;
  bool _active = false;
  bool _clipboardCleared = false;

  static const List<String> _prohibitedProcessTerms = <String>[
    'anydesk',
    'teamviewer',
    'rustdesk',
    'chrome remote desktop',
    'remotedesktop',
    'remote desktop',
    'mstsc',
    'parsecd',
    'parsec',
    'vnc',
    'ultravnc',
    'tightvnc',
    'obs',
    'obs64',
    'screen recorder',
    'camtasia',
    'bandicam',
    'xsplit',
    'manycam',
    'droidcam',
    'snap camera',
    'virtualbox',
    'vmware',
    'qemu',
    'parallels',
    'hyper-v',
    'zoom',
    'teams',
    'telegram',
    'whatsapp',
    'discord',
    'slack',
    'chrome.exe',
    'msedge.exe',
    'firefox.exe',
    'brave.exe',
    'opera.exe',
    'chatgpt',
    'copilot',
  ];

  Future<SecureLockdownSnapshot> begin() async {
    _active = true;
    _clipboardCleared = await _clearClipboard();
    return collectSnapshot();
  }

  Future<void> end() async {
    _active = false;
  }

  Future<SecureLockdownSnapshot> collectSnapshot() async {
    final nativeSnapshot = await _nativeBridge.check();
    if (nativeSnapshot != null) {
      return SecureLockdownSnapshot(
        lockdownActive: _active,
        platformSupported: nativeSnapshot.platformSupported,
        platformName: nativeSnapshot.platformName,
        displayCount: nativeSnapshot.displayCount,
        prohibitedProcesses: nativeSnapshot.prohibitedProcesses,
        clipboardCleared: _clipboardCleared,
        findings: nativeSnapshot.findings
            .map(
              (finding) => SecureLockdownFinding(
                code: finding.code,
                message: finding.message,
                severity: finding.severity,
              ),
            )
            .toList(growable: false),
        capturedAt: DateTime.now(),
      );
    }

    final findings = <SecureLockdownFinding>[];
    final platformName = _platformName();
    final platformSupported =
        Platform.isWindows || Platform.isMacOS || Platform.isLinux;

    if (!platformSupported) {
      findings.add(
        const SecureLockdownFinding(
          code: 'unsupported_platform',
          severity: 'critical',
          message:
              'Secure lockdown requires the desktop app on Windows, macOS, or Linux.',
        ),
      );
    }

    final processReport = platformSupported ? await _processReport() : '';
    final prohibitedProcesses = _detectProhibitedProcesses(processReport);
    if (prohibitedProcesses.isNotEmpty) {
      findings.add(
        SecureLockdownFinding(
          code: 'prohibited_process_detected',
          severity: 'critical',
          message:
              'Close prohibited apps before continuing: ${prohibitedProcesses.take(4).join(', ')}.',
        ),
      );
    }

    final displayCount = platformSupported ? await _displayCount() : null;
    if (displayCount != null && displayCount > 1) {
      findings.add(
        SecureLockdownFinding(
          code: 'multiple_displays_detected',
          severity: 'critical',
          message: 'Only one display is allowed during a secure exam.',
        ),
      );
    }

    if (!_clipboardCleared) {
      findings.add(
        const SecureLockdownFinding(
          code: 'clipboard_clear_unconfirmed',
          severity: 'warning',
          message: 'Clipboard clearing could not be confirmed on this device.',
        ),
      );
    }

    if (findings.isEmpty) {
      findings.add(
        const SecureLockdownFinding(
          code: 'secure_lockdown_ready',
          severity: 'info',
          message: 'Secure lockdown checks are active.',
        ),
      );
    }

    return SecureLockdownSnapshot(
      lockdownActive: _active,
      platformSupported: platformSupported,
      platformName: platformName,
      displayCount: displayCount,
      prohibitedProcesses: prohibitedProcesses,
      clipboardCleared: _clipboardCleared,
      findings: findings,
      capturedAt: DateTime.now(),
    );
  }

  Future<bool> _clearClipboard() async {
    try {
      await Clipboard.setData(const ClipboardData(text: ''));
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<String> _processReport() async {
    try {
      if (Platform.isWindows) {
        return _run('powershell', <String>[
          '-NoProfile',
          '-ExecutionPolicy',
          'Bypass',
          '-Command',
          r"Get-Process | Select-Object ProcessName,Path | ConvertTo-Json -Compress -Depth 2",
        ]);
      }
      return _run('sh', <String>['-c', 'ps -axo comm,args 2>/dev/null']);
    } catch (_) {
      return '';
    }
  }

  Future<int?> _displayCount() async {
    try {
      final output = Platform.isWindows
          ? await _run('powershell', <String>[
              '-NoProfile',
              '-ExecutionPolicy',
              'Bypass',
              '-Command',
              r"Add-Type -AssemblyName System.Windows.Forms; [System.Windows.Forms.Screen]::AllScreens.Count",
            ])
          : Platform.isMacOS
          ? await _run('sh', <String>[
              '-c',
              "system_profiler SPDisplaysDataType 2>/dev/null | grep -c 'Resolution:'",
            ])
          : await _run('sh', <String>[
              '-c',
              "xrandr --listmonitors 2>/dev/null | awk '/Monitors:/ {print \$2}'",
            ]);
      final number = int.tryParse(output.trim().split(RegExp(r'\\s+')).first);
      if (number == null || number <= 0) return null;
      return number;
    } catch (_) {
      return null;
    }
  }

  Future<String> _run(String executable, List<String> arguments) async {
    final result = await Process.run(
      executable,
      arguments,
    ).timeout(commandTimeout);
    final stdoutText = result.stdout.toString();
    final stderrText = result.stderr.toString();
    final combined = '$stdoutText\n$stderrText'.trim();
    return combined;
  }

  List<String> _detectProhibitedProcesses(String report) {
    if (report.trim().isEmpty) return const <String>[];
    final text = _normalise(report);
    final matches = <String>{};
    for (final term in _prohibitedProcessTerms) {
      if (text.contains(term.toLowerCase())) matches.add(term);
    }
    return matches.toList()..sort();
  }

  String _normalise(String value) {
    try {
      return jsonDecode(value).toString().toLowerCase();
    } catch (_) {
      return value.toLowerCase();
    }
  }

  String _platformName() {
    if (Platform.isWindows) return 'windows';
    if (Platform.isMacOS) return 'macos';
    if (Platform.isLinux) return 'linux';
    if (Platform.isAndroid) return 'android';
    if (Platform.isIOS) return 'ios';
    return 'unknown';
  }
}

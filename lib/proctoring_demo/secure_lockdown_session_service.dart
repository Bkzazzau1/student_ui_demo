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

class SecureLockdownAction {
  const SecureLockdownAction({
    required this.code,
    required this.message,
    required this.success,
    this.metadata = const <String, Object?>{},
  });

  final String code;
  final String message;
  final bool success;
  final Map<String, Object?> metadata;

  Map<String, Object?> toJson() => <String, Object?>{
    'code': code,
    'message': message,
    'success': success,
    if (metadata.isNotEmpty) 'metadata': metadata,
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
    required this.actions,
    required this.enforcementActive,
    required this.clipboardSweepCount,
    required this.capturedAt,
  });

  final bool lockdownActive;
  final bool platformSupported;
  final String platformName;
  final int? displayCount;
  final List<String> prohibitedProcesses;
  final bool clipboardCleared;
  final List<SecureLockdownFinding> findings;
  final List<SecureLockdownAction> actions;
  final bool enforcementActive;
  final int clipboardSweepCount;
  final DateTime capturedAt;

  bool get ready =>
      lockdownActive &&
      platformSupported &&
      enforcementActive &&
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
    'clipboard_sweep_count': clipboardSweepCount,
    'enforcement_active': enforcementActive,
    'findings': findings.map((finding) => finding.toJson()).toList(),
    'actions': actions.map((action) => action.toJson()).toList(),
    'captured_at': capturedAt.toUtc().toIso8601String(),
  };
}

class SecureLockdownSessionService {
  SecureLockdownSessionService({
    this.commandTimeout = const Duration(seconds: 5),
    this.enforcementEnabled = true,
    NativeSecureLockdownReviewBridge nativeBridge =
        const GeneratedNativeSecureLockdownReviewBridge(),
  }) : _nativeBridge = nativeBridge;

  final Duration commandTimeout;
  final bool enforcementEnabled;
  final NativeSecureLockdownReviewBridge _nativeBridge;
  bool _active = false;
  bool _clipboardCleared = false;
  int _clipboardSweepCount = 0;

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
    await _enterExamWindowMode();
    _clipboardCleared = await _clearClipboard();
    return collectSnapshot();
  }

  Future<void> end() async {
    _active = false;
    await _exitExamWindowMode();
  }

  Future<SecureLockdownSnapshot> collectSnapshot() async {
    final actions = <SecureLockdownAction>[];
    if (_active && enforcementEnabled) {
      final clipboardAction = await _sweepClipboard();
      actions.add(clipboardAction);
    }

    final nativeSnapshot = await _nativeBridge.check();
    if (nativeSnapshot != null) {
      actions.addAll(
        await _applyLockdownControls(
          prohibitedProcesses: nativeSnapshot.prohibitedProcesses,
          displayCount: nativeSnapshot.displayCount,
        ),
      );

      final refreshed = actions.any((action) =>
              action.code == 'prohibited_app_close_requested' && action.success)
          ? await _nativeBridge.check()
          : nativeSnapshot;
      final source = refreshed ?? nativeSnapshot;
      final nativeFindings = source.findings
          .map(
            (finding) => SecureLockdownFinding(
              code: finding.code,
              message: finding.message,
              severity: finding.severity,
            ),
          )
          .toList(growable: true);
      _appendLocalFindings(nativeFindings, source.displayCount);

      return SecureLockdownSnapshot(
        lockdownActive: _active,
        platformSupported: source.platformSupported,
        platformName: source.platformName,
        displayCount: source.displayCount,
        prohibitedProcesses: source.prohibitedProcesses,
        clipboardCleared: _clipboardCleared,
        findings: nativeFindings,
        actions: actions,
        enforcementActive: _active && enforcementEnabled,
        clipboardSweepCount: _clipboardSweepCount,
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
    var prohibitedProcesses = _detectProhibitedProcesses(processReport);
    final displayCount = platformSupported ? await _displayCount() : null;
    actions.addAll(
      await _applyLockdownControls(
        prohibitedProcesses: prohibitedProcesses,
        displayCount: displayCount,
      ),
    );

    if (actions.any((action) =>
        action.code == 'prohibited_app_close_requested' && action.success)) {
      prohibitedProcesses = _detectProhibitedProcesses(await _processReport());
    }

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

    if (displayCount != null && displayCount > 1) {
      findings.add(
        const SecureLockdownFinding(
          code: 'multiple_displays_detected',
          severity: 'critical',
          message: 'Only one display is allowed during a secure exam.',
        ),
      );
    }

    _appendLocalFindings(findings, displayCount);

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
      actions: actions,
      enforcementActive: _active && enforcementEnabled,
      clipboardSweepCount: _clipboardSweepCount,
      capturedAt: DateTime.now(),
    );
  }

  Future<void> _enterExamWindowMode() async {
    try {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } catch (_) {
      // Desktop platforms may ignore immersive mode; lockdown still relies on
      // app-level pause, process review, clipboard sweep, and display checks.
    }
  }

  Future<void> _exitExamWindowMode() async {
    try {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    } catch (_) {
      // Best effort only.
    }
  }

  Future<SecureLockdownAction> _sweepClipboard() async {
    final ok = await _clearClipboard();
    _clipboardCleared = _clipboardCleared || ok;
    if (ok) _clipboardSweepCount++;
    return SecureLockdownAction(
      code: 'clipboard_sweep_applied',
      success: ok,
      message: ok
          ? 'Clipboard was cleared for secure exam mode.'
          : 'Clipboard could not be cleared on this cycle.',
      metadata: <String, Object?>{'sweep_count': _clipboardSweepCount},
    );
  }

  Future<List<SecureLockdownAction>> _applyLockdownControls({
    required List<String> prohibitedProcesses,
    required int? displayCount,
  }) async {
    if (!_active || !enforcementEnabled) {
      return const <SecureLockdownAction>[
        SecureLockdownAction(
          code: 'lockdown_enforcement_not_active',
          success: false,
          message: 'Secure exam enforcement is not active.',
        ),
      ];
    }

    final actions = <SecureLockdownAction>[];
    if (prohibitedProcesses.isNotEmpty) {
      actions.add(await _requestCloseProhibitedApps(prohibitedProcesses));
    }
    if (displayCount != null && displayCount > 1) {
      actions.add(
        SecureLockdownAction(
          code: 'external_display_block_required',
          success: false,
          message: 'External display is still connected and must be removed.',
          metadata: <String, Object?>{'display_count': displayCount},
        ),
      );
    }
    return actions;
  }

  Future<SecureLockdownAction> _requestCloseProhibitedApps(
    List<String> prohibitedProcesses,
  ) async {
    final terms = prohibitedProcesses
        .map(_safeProcessTerm)
        .where((term) => term.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    if (terms.isEmpty) {
      return const SecureLockdownAction(
        code: 'prohibited_app_close_requested',
        success: false,
        message: 'No safe prohibited app terms were available for closure.',
      );
    }

    try {
      if (Platform.isWindows) {
        final scriptTerms = terms
            .map((term) => "'${term.replaceAll("'", "''")}'")
            .join(',');
        final script = """
\$terms = @($scriptTerms)
\$matched = Get-Process | Where-Object {
  \$name = \$_.ProcessName.ToLowerInvariant()
  \$path = ''
  try { if (\$_.Path) { \$path = \$_.Path.ToLowerInvariant() } } catch {}
  foreach (\$term in \$terms) {
    \$clean = \$term.Replace('.exe','')
    if (\$name.Contains(\$term) -or \$name.Contains(\$clean) -or \$path.Contains(\$term)) { return \$true }
  }
  return \$false
}
\$matched | Stop-Process -Force -ErrorAction SilentlyContinue
\$matched | Select-Object -ExpandProperty ProcessName | ConvertTo-Json -Compress
""";
        final output = await _run('powershell', <String>[
          '-NoProfile',
          '-ExecutionPolicy',
          'Bypass',
          '-Command',
          script,
        ]);
        return SecureLockdownAction(
          code: 'prohibited_app_close_requested',
          success: true,
          message: 'Prohibited apps were requested to close for secure exam mode.',
          metadata: <String, Object?>{
            'terms': terms,
            'platform': 'windows',
            'output': output,
          },
        );
      }

      if (Platform.isMacOS || Platform.isLinux) {
        final closed = <String>[];
        for (final term in terms) {
          try {
            await Process.run('pkill', <String>['-f', term])
                .timeout(commandTimeout);
            closed.add(term);
          } catch (_) {
            // Some terms may not have running processes; continue safely.
          }
        }
        return SecureLockdownAction(
          code: 'prohibited_app_close_requested',
          success: true,
          message: 'Prohibited apps were requested to close for secure exam mode.',
          metadata: <String, Object?>{
            'terms': terms,
            'platform': Platform.isMacOS ? 'macos' : 'linux',
            'requested_terms': closed,
          },
        );
      }
    } catch (error) {
      return SecureLockdownAction(
        code: 'prohibited_app_close_requested',
        success: false,
        message: 'Prohibited apps could not be closed automatically.',
        metadata: <String, Object?>{'error': error.toString(), 'terms': terms},
      );
    }

    return const SecureLockdownAction(
      code: 'prohibited_app_close_requested',
      success: false,
      message: 'Automatic prohibited app closure is not supported on this platform.',
    );
  }

  void _appendLocalFindings(
    List<SecureLockdownFinding> findings,
    int? displayCount,
  ) {
    if (!_clipboardCleared) {
      findings.add(
        const SecureLockdownFinding(
          code: 'clipboard_clear_unconfirmed',
          severity: 'warning',
          message: 'Clipboard clearing could not be confirmed on this device.',
        ),
      );
    }
    if (!_active || !enforcementEnabled) {
      findings.add(
        const SecureLockdownFinding(
          code: 'lockdown_enforcement_inactive',
          severity: 'critical',
          message: 'Secure exam enforcement is not active.',
        ),
      );
    }
    if (displayCount != null && displayCount > 1) {
      findings.add(
        const SecureLockdownFinding(
          code: 'external_display_must_be_removed',
          severity: 'critical',
          message: 'Remove external display before continuing the exam.',
        ),
      );
    }
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
      final number = int.tryParse(output.trim().split(RegExp(r'\s+')).first);
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

  String _safeProcessTerm(String value) {
    return value
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9 ._-]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
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

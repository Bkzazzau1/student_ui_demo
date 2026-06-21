import 'package:flutter/material.dart';

import 'audio_security_check_service.dart';
import 'system_security_review_service.dart';

class AudioSystemReviewResult {
  const AudioSystemReviewResult({
    required this.audioReady,
    required this.systemReady,
    this.audioReview,
    this.systemReview,
  });

  final bool audioReady;
  final bool systemReady;
  final AudioSecurityCheckResult? audioReview;
  final SystemSecurityReviewResult? systemReview;

  bool get ready => audioReady && systemReady;
}

class AudioSystemReviewView extends StatefulWidget {
  const AudioSystemReviewView({super.key});

  @override
  State<AudioSystemReviewView> createState() => _AudioSystemReviewViewState();
}

class _AudioSystemReviewViewState extends State<AudioSystemReviewView> {
  final AudioSecurityCheckService _audioReview = AudioSecurityCheckService();
  final SystemSecurityReviewService _systemReview = SystemSecurityReviewService();

  bool _checkingAudio = false;
  bool _checkingSystem = false;
  bool _runningFullCheck = false;
  bool _audioReady = false;
  bool _systemReady = false;
  String _audioMessage = 'Room sound has not been checked.';
  String _systemMessage = 'Device readiness has not been checked.';
  AudioSecurityCheckResult? _audioReviewResult;
  SystemSecurityReviewResult? _systemReviewResult;

  bool get _ready => _audioReady && _systemReady;
  bool get _busy => _checkingAudio || _checkingSystem || _runningFullCheck;

  @override
  void dispose() {
    _audioReview.dispose();
    super.dispose();
  }

  Future<void> _runFullReview() async {
    if (_busy) return;
    setState(() => _runningFullCheck = true);
    await _checkAudio();
    if (!mounted) return;
    await _checkSystem();
    if (!mounted) return;
    setState(() => _runningFullCheck = false);
  }

  Future<void> _checkAudio() async {
    setState(() {
      _checkingAudio = true;
      _audioReady = false;
      _audioReviewResult = null;
      _audioMessage = 'Learning room sound for 15 seconds. Keep the room quiet.';
    });
    try {
      final result = await _audioReview.captureBaseline(
        duration: const Duration(seconds: 15),
      );
      if (!mounted) return;
      setState(() {
        _checkingAudio = false;
        _audioReviewResult = result;
        _audioReady = result.microphoneAvailable &&
            result.permissionGranted &&
            result.inputLevelOk &&
            result.ambientNoiseAllowed;
        _audioMessage = result.message ?? result.environmentDescription;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _checkingAudio = false;
        _audioReady = false;
        _audioMessage = 'Room sound check could not be completed. Try again.';
      });
    }
  }

  Future<void> _checkSystem() async {
    setState(() {
      _checkingSystem = true;
      _systemReady = false;
      _systemMessage = 'Checking connected devices, camera, audio, and system setup...';
    });
    final result = await _systemReview.check();
    if (!mounted) return;
    setState(() {
      _checkingSystem = false;
      _systemReviewResult = result;
      _systemReady = result.ready;
      _systemMessage = result.message;
    });
  }

  void _finish() {
    Navigator.of(context).pop(
      AudioSystemReviewResult(
        audioReady: _audioReady,
        systemReady: _systemReady,
        audioReview: _audioReviewResult,
        systemReview: _systemReviewResult,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final audioBlocking = _audioBlockingFindings(_audioReviewResult);
    final audioWarnings = _audioWarningFindings(_audioReviewResult);
    final systemBlocking = _systemReviewResult?.hardFindings ?? const <String>[];
    final systemWarnings = _systemReviewResult?.warningFindings ?? const <String>[];
    final progress = (_audioReady ? 0.5 : 0.0) + (_systemReady ? 0.5 : 0.0);

    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FB),
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'Sound and device check',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFF8FAFC), Color(0xFFF1F5F9)],
          ),
        ),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 120),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1220),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _HeaderPanel(
                      ready: _ready,
                      busy: _busy,
                      progress: progress,
                    ),
                    const SizedBox(height: 16),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final wide = constraints.maxWidth >= 950;
                        final checks = _ChecksPanel(
                          audioCard: _ReviewStepCard(
                            number: 1,
                            title: 'Room sound learning',
                            subtitle: 'The app listens briefly to understand the room background sound.',
                            icon: Icons.hearing_outlined,
                            passed: _audioReady,
                            checking: _checkingAudio,
                            message: _audioMessage,
                            primaryButtonText: _checkingAudio
                                ? 'Learning room sound...'
                                : 'Run sound check',
                            onPrimaryPressed: _busy ? null : _checkAudio,
                            metrics: _audioReviewResult == null
                                ? const <_MetricData>[]
                                : _audioMetrics(_audioReviewResult!),
                            blockingFindings: audioBlocking,
                            warningFindings: audioWarnings,
                          ),
                          systemCard: _ReviewStepCard(
                            number: 2,
                            title: 'Device readiness',
                            subtitle: 'The app checks connected devices and exam access settings.',
                            icon: Icons.desktop_windows_outlined,
                            passed: _systemReady,
                            checking: _checkingSystem,
                            message: _systemMessage,
                            primaryButtonText: _checkingSystem
                                ? 'Checking device...'
                                : 'Run device check',
                            onPrimaryPressed: _busy ? null : _checkSystem,
                            metrics: _systemReviewResult == null
                                ? const <_MetricData>[]
                                : _systemMetrics(_systemReviewResult!),
                            blockingFindings: systemBlocking,
                            warningFindings: systemWarnings,
                          ),
                        );
                        final side = _ActionPanel(
                          ready: _ready,
                          busy: _busy,
                          audioReady: _audioReady,
                          systemReady: _systemReady,
                          onRunAll: _busy ? null : _runFullReview,
                          onContinue: _ready ? _finish : null,
                        );
                        if (!wide) {
                          return Column(
                            children: [checks, const SizedBox(height: 16), side],
                          );
                        }
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(flex: 7, child: checks),
                            const SizedBox(width: 16),
                            Expanded(flex: 4, child: side),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<String> _audioBlockingFindings(AudioSecurityCheckResult? result) {
    if (result == null) return const <String>[];
    final findings = <String>[];
    if (!result.microphoneAvailable || !result.permissionGranted) {
      findings.add('Microphone access is required before the exam can start.');
    }
    if (!result.inputLevelOk) {
      findings.add('Microphone input is too low or muted. Run the sound check again.');
    }
    if (result.humanVoiceDetected) {
      findings.add('Voice was noticed during room sound learning. Keep the room quiet and repeat the check.');
    }
    if (result.phoneRingDetected || result.notificationDetected) {
      findings.add('Phone ring, notification, or sharp beep was noticed. Silence devices and repeat the check.');
    }
    if (result.tvOrRadioVoiceDetected) {
      findings.add('TV or radio-like voice was noticed. Turn it off and repeat the check.');
    }
    return findings;
  }

  List<String> _audioWarningFindings(AudioSecurityCheckResult? result) {
    if (result == null) return const <String>[];
    if (!result.ambientNoiseAllowed) return const <String>[];
    return <String>[result.environmentDescription, result.recommendedAction];
  }

  List<_MetricData> _audioMetrics(AudioSecurityCheckResult result) => <_MetricData>[
        _MetricData('Noise', result.dominantNoiseClass),
        _MetricData('Voice', '${(result.voiceConfidence * 100).toStringAsFixed(0)}%'),
        _MetricData('Avg', '${(result.averageRms * 100).toStringAsFixed(1)}%'),
        _MetricData('Peak', '${(result.peakRms * 100).toStringAsFixed(1)}%'),
        _MetricData('Learned', '${result.sampleDurationSeconds}s'),
      ];

  List<_MetricData> _systemMetrics(SystemSecurityReviewResult result) => <_MetricData>[
        _MetricData('Platform', result.platformSupported ? 'OK' : 'Unsupported'),
        _MetricData('Audio device', result.externalAudioDetected ? 'Check' : 'OK'),
        _MetricData('Bluetooth', result.bluetoothDetected ? 'Check' : 'OK'),
        _MetricData('USB', result.usbRiskDetected ? 'Check' : 'OK'),
      ];
}

class _HeaderPanel extends StatelessWidget {
  const _HeaderPanel({
    required this.ready,
    required this.busy,
    required this.progress,
  });

  final bool ready;
  final bool busy;
  final double progress;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(28),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1A0F172A),
            blurRadius: 24,
            offset: Offset(0, 14),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 760;
          final main = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _DarkTag('Room sound'),
                  _DarkTag('Device readiness'),
                  _DarkTag(ready ? 'Ready' : busy ? 'Checking' : 'Not started'),
                ],
              ),
              const SizedBox(height: 14),
              const Text(
                'Sound and device check',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 31,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.4,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Complete the room sound and device readiness checks before requesting exam start approval.',
                style: TextStyle(color: Color(0xFFCBD5E1), fontSize: 16),
              ),
            ],
          );
          final progressCard = Container(
            width: wide ? 280 : double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0x12FFFFFF),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: const Color(0x24FFFFFF)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      ready ? Icons.check_circle : Icons.pending_actions_outlined,
                      color: ready ? const Color(0xFF86EFAC) : const Color(0xFFBFDBFE),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        ready ? 'Ready to continue' : 'Check progress',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    minHeight: 9,
                    value: progress.clamp(0.0, 1.0),
                    backgroundColor: const Color(0x24FFFFFF),
                    color: ready ? const Color(0xFF22C55E) : const Color(0xFF60A5FA),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  '${(progress * 2).round()} of 2 checks ready',
                  style: const TextStyle(color: Color(0xFFCBD5E1), fontWeight: FontWeight.w700),
                ),
              ],
            ),
          );
          if (!wide) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [main, const SizedBox(height: 18), progressCard],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [Expanded(child: main), const SizedBox(width: 24), progressCard],
          );
        },
      ),
    );
  }
}

class _ChecksPanel extends StatelessWidget {
  const _ChecksPanel({required this.audioCard, required this.systemCard});

  final Widget audioCard;
  final Widget systemCard;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xB3FFFFFF),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        children: [audioCard, const SizedBox(height: 14), systemCard],
      ),
    );
  }
}

class _ReviewStepCard extends StatelessWidget {
  const _ReviewStepCard({
    required this.number,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.passed,
    required this.checking,
    required this.message,
    required this.primaryButtonText,
    required this.onPrimaryPressed,
    required this.metrics,
    required this.blockingFindings,
    required this.warningFindings,
  });

  final int number;
  final String title;
  final String subtitle;
  final IconData icon;
  final bool passed;
  final bool checking;
  final String message;
  final String primaryButtonText;
  final VoidCallback? onPrimaryPressed;
  final List<_MetricData> metrics;
  final List<String> blockingFindings;
  final List<String> warningFindings;

  @override
  Widget build(BuildContext context) {
    final hasIssues = blockingFindings.isNotEmpty && !passed;
    final color = passed
        ? const Color(0xFF16A34A)
        : hasIssues
            ? const Color(0xFFDC2626)
            : checking
                ? const Color(0xFF2563EB)
                : const Color(0xFF64748B);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: passed ? const Color(0xFFBBF7D0) : hasIssues ? const Color(0xFFFECACA) : const Color(0xFFE2E8F0)),
        boxShadow: const [
          BoxShadow(color: Color(0x080F172A), blurRadius: 18, offset: Offset(0, 8)),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 620;
          final leading = Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: color.withOpacity(0.10),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Icon(icon, color: color),
          );
          final details = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _StepNumber(number: number, color: color),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 5),
              Text(subtitle, style: const TextStyle(color: Color(0xFF64748B))),
              const SizedBox(height: 8),
              Text(message),
              if (metrics.isNotEmpty) ...[
                const SizedBox(height: 10),
                _MetricsGrid(metrics: metrics),
              ],
              if (blockingFindings.isNotEmpty) ...[
                const SizedBox(height: 10),
                _FindingList(findings: blockingFindings, color: const Color(0xFFDC2626), icon: Icons.warning_amber_outlined),
              ],
              if (warningFindings.isNotEmpty) ...[
                const SizedBox(height: 10),
                _FindingList(findings: warningFindings, color: const Color(0xFFB45309), icon: Icons.info_outline),
              ],
              const SizedBox(height: 10),
              _StatusPill(passed: passed, checking: checking, hasIssues: hasIssues),
            ],
          );
          final action = OutlinedButton.icon(
            onPressed: onPrimaryPressed,
            icon: checking
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.refresh_rounded),
            label: Text(primaryButtonText),
          );
          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [leading, const SizedBox(width: 12), Expanded(child: details)]),
                const SizedBox(height: 14),
                Align(alignment: Alignment.centerRight, child: action),
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [leading, const SizedBox(width: 14), Expanded(child: details), const SizedBox(width: 14), action],
          );
        },
      ),
    );
  }
}

class _ActionPanel extends StatelessWidget {
  const _ActionPanel({
    required this.ready,
    required this.busy,
    required this.audioReady,
    required this.systemReady,
    required this.onRunAll,
    required this.onContinue,
  });

  final bool ready;
  final bool busy;
  final bool audioReady;
  final bool systemReady;
  final VoidCallback? onRunAll;
  final VoidCallback? onContinue;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(26),
            border: Border.all(color: const Color(0xFFE2E8F0)),
            boxShadow: const [BoxShadow(color: Color(0x080F172A), blurRadius: 18, offset: Offset(0, 8))],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Check summary', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
              const SizedBox(height: 12),
              _SummaryLine(icon: Icons.hearing_outlined, label: audioReady ? 'Room sound ready' : 'Room sound pending', ok: audioReady),
              _SummaryLine(icon: Icons.desktop_windows_outlined, label: systemReady ? 'Device ready' : 'Device check pending', ok: systemReady),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: onRunAll,
                  icon: busy
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.play_arrow_rounded),
                  label: Text(busy ? 'Checking...' : 'Start sound and device check'),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: onContinue,
                  icon: Icon(ready ? Icons.check_circle_outline : Icons.lock_outline_rounded),
                  label: Text(ready ? 'Continue to setup' : 'Complete checks to continue'),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFFFFBEB),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: const Color(0xFFFDE68A)),
          ),
          child: const Text(
            'Keep the room quiet while sound is being checked. Disconnect external audio devices before continuing.',
          ),
        ),
      ],
    );
  }
}

class _StepNumber extends StatelessWidget {
  const _StepNumber({required this.number, required this.color});
  final int number;
  final Color color;
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 26,
      height: 26,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.28)),
      ),
      child: Text('$number', style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 12)),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.passed, required this.checking, required this.hasIssues});
  final bool passed;
  final bool checking;
  final bool hasIssues;
  @override
  Widget build(BuildContext context) {
    final color = passed
        ? const Color(0xFF16A34A)
        : hasIssues
            ? const Color(0xFFDC2626)
            : checking
                ? const Color(0xFF2563EB)
                : const Color(0xFF64748B);
    final label = passed
        ? 'Completed'
        : hasIssues
            ? 'Needs attention'
            : checking
                ? 'Checking now'
                : 'Waiting';
    final icon = passed
        ? Icons.check_circle
        : hasIssues
            ? Icons.warning_amber_outlined
            : checking
                ? Icons.sync
                : Icons.radio_button_unchecked;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: color.withOpacity(0.08), borderRadius: BorderRadius.circular(999), border: Border.all(color: color.withOpacity(0.25))),
      child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(icon, color: color, size: 15), const SizedBox(width: 6), Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 12))]),
    );
  }
}

class _MetricData {
  const _MetricData(this.label, this.value);
  final String label;
  final String value;
}

class _MetricsGrid extends StatelessWidget {
  const _MetricsGrid({required this.metrics});
  final List<_MetricData> metrics;
  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final metric in metrics)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(999), border: Border.all(color: const Color(0xFFE2E8F0))),
            child: Text('${metric.label}: ${metric.value}', style: const TextStyle(fontWeight: FontWeight.w800)),
          ),
      ],
    );
  }
}

class _FindingList extends StatelessWidget {
  const _FindingList({required this.findings, required this.color, required this.icon});
  final List<String> findings;
  final Color color;
  final IconData icon;
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final finding in findings)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Icon(icon, size: 17, color: color), const SizedBox(width: 8), Expanded(child: Text(finding))]),
          ),
      ],
    );
  }
}

class _SummaryLine extends StatelessWidget {
  const _SummaryLine({required this.icon, required this.label, required this.ok});
  final IconData icon;
  final String label;
  final bool ok;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Icon(ok ? Icons.check_circle : icon, color: ok ? const Color(0xFF16A34A) : const Color(0xFF64748B), size: 19),
          const SizedBox(width: 9),
          Expanded(child: Text(label, style: const TextStyle(color: Color(0xFF334155), fontWeight: FontWeight.w800))),
        ],
      ),
    );
  }
}

class _DarkTag extends StatelessWidget {
  const _DarkTag(this.text);
  final String text;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: const Color(0xFF1F2937), borderRadius: BorderRadius.circular(999), border: Border.all(color: const Color(0xFF334155))),
      child: Text(text, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
    );
  }
}

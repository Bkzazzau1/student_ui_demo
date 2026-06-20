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
  bool _audioReady = false;
  bool _systemReady = false;
  String _audioMessage = 'Room sound learning has not started.';
  String _systemMessage = 'System review has not started.';
  AudioSecurityCheckResult? _audioReviewResult;
  SystemSecurityReviewResult? _systemReviewResult;

  @override
  void dispose() {
    _audioReview.dispose();
    super.dispose();
  }

  Future<void> _checkAudio() async {
    setState(() {
      _checkingAudio = true;
      _audioReady = false;
      _audioReviewResult = null;
      _audioMessage = 'Learning room sound for 15 seconds. Keep quiet and avoid phone notifications.';
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
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _checkingAudio = false;
        _audioReady = false;
        _audioMessage = 'Room sound learning failed: $e';
      });
    }
  }

  Future<void> _checkSystem() async {
    setState(() {
      _checkingSystem = true;
      _systemReady = false;
      _systemMessage = 'Checking Bluetooth, external audio, USB, camera, VM, and capture devices...';
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
    final ready = _audioReady && _systemReady;
    final audioBlocking = _audioBlockingFindings(_audioReviewResult);
    final audioWarnings = _audioWarningFindings(_audioReviewResult);
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      appBar: AppBar(title: const Text('Audio and system review')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(18),
          children: [
            _ReviewCard(
              title: 'Room sound learning',
              icon: Icons.hearing_outlined,
              passed: _audioReady,
              checking: _checkingAudio,
              message: _audioMessage,
              audioResult: _audioReviewResult,
              blockingFindings: audioBlocking,
              warningFindings: audioWarnings,
              buttonText: _checkingAudio ? 'Learning room sound...' : 'Learn room sound',
              onPressed: _checkingAudio ? null : _checkAudio,
            ),
            const SizedBox(height: 14),
            _ReviewCard(
              title: 'Strict device review',
              icon: Icons.desktop_windows_outlined,
              passed: _systemReady,
              checking: _checkingSystem,
              message: _systemMessage,
              blockingFindings:
                  _systemReviewResult?.hardFindings ?? const <String>[],
              warningFindings:
                  _systemReviewResult?.warningFindings ?? const <String>[],
              buttonText: _checkingSystem ? 'Checking...' : 'Check system devices',
              onPressed: _checkingSystem ? null : _checkSystem,
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: ready ? _finish : null,
              icon: const Icon(Icons.check_circle_outline),
              label: Text(
                ready
                    ? 'Approve and continue'
                    : 'Resolve blocking issues to continue',
              ),
            ),
            const SizedBox(height: 10),
            const _RuleNotice(),
          ],
        ),
      ),
    );
  }

  List<String> _audioBlockingFindings(AudioSecurityCheckResult? result) {
    if (result == null) return const <String>[];
    final findings = <String>[];
    if (!result.microphoneAvailable || !result.permissionGranted) {
      findings.add('Microphone permission is required before the exam can start.');
    }
    if (!result.inputLevelOk) {
      findings.add('Microphone input is too low or muted. Run the sound review again.');
    }
    if (result.humanVoiceDetected) {
      findings.add('Human voice or conversation detected. Move to a quiet room before starting.');
    }
    if (result.phoneRingDetected || result.notificationDetected) {
      findings.add('Phone ring, notification, or sharp beep detected. Silence devices and repeat the sound review.');
    }
    if (result.tvOrRadioVoiceDetected) {
      findings.add('TV or radio-like voice detected. Turn it off and repeat the sound review.');
    }
    return findings;
  }

  List<String> _audioWarningFindings(AudioSecurityCheckResult? result) {
    if (result == null) return const <String>[];
    if (!result.ambientNoiseAllowed) return const <String>[];
    return <String>[
      result.environmentDescription,
      result.recommendedAction,
    ];
  }
}

class _ReviewCard extends StatelessWidget {
  const _ReviewCard({
    required this.title,
    required this.icon,
    required this.passed,
    required this.checking,
    required this.message,
    required this.buttonText,
    required this.onPressed,
    this.audioResult,
    this.blockingFindings = const <String>[],
    this.warningFindings = const <String>[],
  });

  final String title;
  final IconData icon;
  final bool passed;
  final bool checking;
  final String message;
  final String buttonText;
  final VoidCallback? onPressed;
  final AudioSecurityCheckResult? audioResult;
  final List<String> blockingFindings;
  final List<String> warningFindings;

  bool get _hasBlockingIssues => blockingFindings.isNotEmpty && !passed;

  @override
  Widget build(BuildContext context) {
    final borderColor = passed
        ? const Color(0xFFBBF7D0)
        : _hasBlockingIssues
            ? const Color(0xFFFECACA)
            : const Color(0xFFE2E8F0);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: borderColor),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x08000000),
            blurRadius: 16,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: const Color(0xFF0F4C81)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                ),
              ),
              _StatusBadge(
                passed: passed,
                checking: checking,
                hasBlockingIssues: _hasBlockingIssues,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(message),
          if (audioResult != null) ...[
            const SizedBox(height: 12),
            _AudioEnvironmentPanel(result: audioResult!),
          ],
          if (_hasBlockingIssues) ...[
            const SizedBox(height: 12),
            const _FindingHeader(
              text: 'Blocking issues',
              color: Color(0xFFB91C1C),
              icon: Icons.block,
            ),
            const SizedBox(height: 8),
            ...blockingFindings.map(
              (finding) => _FindingRow(
                finding: finding,
                icon: Icons.warning_amber_outlined,
                color: const Color(0xFFDC2626),
              ),
            ),
          ],
          if (passed && blockingFindings.isNotEmpty) ...[
            const SizedBox(height: 12),
            ...blockingFindings.map(
              (finding) => _FindingRow(
                finding: finding,
                icon: Icons.check_circle_outline,
                color: const Color(0xFF16A34A),
              ),
            ),
          ],
          if (warningFindings.isNotEmpty) ...[
            const SizedBox(height: 12),
            const _FindingHeader(
              text: 'Sound/environment information',
              color: Color(0xFFB45309),
              icon: Icons.info_outline,
            ),
            const SizedBox(height: 8),
            ...warningFindings.map(
              (finding) => _FindingRow(
                finding: finding,
                icon: Icons.info_outline,
                color: const Color(0xFFF59E0B),
              ),
            ),
          ],
          const SizedBox(height: 14),
          OutlinedButton.icon(
            onPressed: onPressed,
            icon: checking
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
            label: Text(buttonText),
          ),
        ],
      ),
    );
  }
}

class _AudioEnvironmentPanel extends StatelessWidget {
  const _AudioEnvironmentPanel({required this.result});

  final AudioSecurityCheckResult result;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          _MetricPill('Profile', _friendlyProfile(result.soundProfile)),
          _MetricPill('Noise class', result.dominantNoiseClass),
          _MetricPill('Voice', '${(result.voiceConfidence * 100).toStringAsFixed(0)}%'),
          _MetricPill('Avg', '${(result.averageRms * 100).toStringAsFixed(1)}%'),
          _MetricPill('Peak', '${(result.peakRms * 100).toStringAsFixed(1)}%'),
          _MetricPill('Noise floor', '${(result.noiseFloorRms * 100).toStringAsFixed(1)}%'),
          _MetricPill('Variation', '${(result.dynamicVariation * 100).toStringAsFixed(1)}%'),
          _MetricPill('Learned', '${result.sampleDurationSeconds}s'),
        ],
      ),
    );
  }

  String _friendlyProfile(String value) {
    return value.replaceAll('_', ' ');
  }
}

class _MetricPill extends StatelessWidget {
  const _MetricPill(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Text(
        '$label: $value',
        style: const TextStyle(fontWeight: FontWeight.w800),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({
    required this.passed,
    required this.checking,
    required this.hasBlockingIssues,
  });

  final bool passed;
  final bool checking;
  final bool hasBlockingIssues;

  @override
  Widget build(BuildContext context) {
    final color = checking
        ? const Color(0xFF2563EB)
        : passed
            ? const Color(0xFF16A34A)
            : hasBlockingIssues
                ? const Color(0xFFDC2626)
                : const Color(0xFF64748B);
    final label = checking
        ? 'Learning'
        : passed
            ? 'Passed'
            : hasBlockingIssues
                ? 'Blocked'
                : 'Pending';
    final icon = checking
        ? Icons.sync
        : passed
            ? Icons.check_circle
            : hasBlockingIssues
                ? Icons.block
                : Icons.radio_button_unchecked;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(color: color, fontWeight: FontWeight.w900),
          ),
        ],
      ),
    );
  }
}

class _FindingHeader extends StatelessWidget {
  const _FindingHeader({
    required this.text,
    required this.color,
    required this.icon,
  });

  final String text;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 8),
        Text(
          text,
          style: TextStyle(color: color, fontWeight: FontWeight.w900),
        ),
      ],
    );
  }
}

class _FindingRow extends StatelessWidget {
  const _FindingRow({
    required this.finding,
    required this.icon,
    required this.color,
  });

  final String finding;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(child: Text(finding)),
        ],
      ),
    );
  }
}

class _RuleNotice extends StatelessWidget {
  const _RuleNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFDE68A)),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.policy_outlined, color: Color(0xFFB45309)),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Proctored exam rule: the room sound must be learned before startup. Fan, AC, generator, rain, and traffic may be allowed; human voice, phone ring, TV/radio voice, and notifications require correction or review.',
            ),
          ),
        ],
      ),
    );
  }
}

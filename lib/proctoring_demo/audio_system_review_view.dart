import 'package:flutter/material.dart';
import 'package:record/record.dart';

import 'system_security_review_service.dart';

class AudioSystemReviewResult {
  const AudioSystemReviewResult({
    required this.audioReady,
    required this.systemReady,
    this.systemReview,
  });

  final bool audioReady;
  final bool systemReady;
  final SystemSecurityReviewResult? systemReview;

  bool get ready => audioReady && systemReady;
}

class AudioSystemReviewView extends StatefulWidget {
  const AudioSystemReviewView({super.key});

  @override
  State<AudioSystemReviewView> createState() => _AudioSystemReviewViewState();
}

class _AudioSystemReviewViewState extends State<AudioSystemReviewView> {
  final AudioRecorder _recorder = AudioRecorder();
  final SystemSecurityReviewService _systemReview = SystemSecurityReviewService();
  bool _checkingAudio = false;
  bool _checkingSystem = false;
  bool _audioReady = false;
  bool _systemReady = false;
  String _audioMessage = 'Microphone review has not started.';
  String _systemMessage = 'System review has not started.';
  SystemSecurityReviewResult? _systemReviewResult;

  @override
  void dispose() {
    _recorder.dispose();
    super.dispose();
  }

  Future<void> _checkAudio() async {
    setState(() {
      _checkingAudio = true;
      _audioReady = false;
      _audioMessage = 'Checking microphone permission...';
    });
    try {
      final hasPermission = await _recorder.hasPermission();
      if (!hasPermission) {
        setState(() {
          _checkingAudio = false;
          _audioReady = false;
          _audioMessage = 'Microphone permission is required before the exam can start.';
        });
        return;
      }
      setState(() {
        _checkingAudio = false;
        _audioReady = true;
        _audioMessage = 'Microphone permission confirmed. External audio devices are checked under strict device review.';
      });
    } catch (e) {
      setState(() {
        _checkingAudio = false;
        _audioReady = false;
        _audioMessage = 'Microphone review failed: $e';
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
        systemReview: _systemReviewResult,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ready = _audioReady && _systemReady;
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      appBar: AppBar(title: const Text('Audio and system review')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(18),
          children: [
            _ReviewCard(
              title: 'Microphone permission',
              icon: Icons.mic_none_outlined,
              passed: _audioReady,
              checking: _checkingAudio,
              message: _audioMessage,
              buttonText: _checkingAudio ? 'Checking...' : 'Check microphone',
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
              text: 'Recorded review notes',
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
        ? 'Checking'
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
              'Proctored exam rule: disconnect Bluetooth, headset, earbud, external microphone, USB audio/capture, virtual camera software, and unknown external devices before starting. Windows hypervisor security features may be recorded for review without blocking when no real virtual machine is detected.',
            ),
          ),
        ],
      ),
    );
  }
}

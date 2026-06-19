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
        _audioMessage = 'Built-in microphone permission confirmed. External audio devices are checked under System review.';
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
      _systemMessage = 'Checking Bluetooth, external audio, USB, camera, and capture devices...';
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
      appBar: AppBar(title: const Text('Audio and system review')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(18),
          children: [
            _ReviewCard(
              title: 'Microphone permission',
              icon: Icons.mic_none_outlined,
              passed: _audioReady,
              message: _audioMessage,
              buttonText: _checkingAudio ? 'Checking...' : 'Check microphone',
              onPressed: _checkingAudio ? null : _checkAudio,
            ),
            const SizedBox(height: 14),
            _ReviewCard(
              title: 'Strict device review',
              icon: Icons.desktop_windows_outlined,
              passed: _systemReady,
              message: _systemMessage,
              findings: _systemReviewResult?.findings ?? const <String>[],
              buttonText: _checkingSystem ? 'Checking...' : 'Check system devices',
              onPressed: _checkingSystem ? null : _checkSystem,
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: ready ? _finish : null,
              icon: const Icon(Icons.check_circle_outline),
              label: const Text('Approve and continue'),
            ),
            const SizedBox(height: 10),
            const Text(
              'Proctored exam rule: disconnect Bluetooth, headset, earbud, external microphone, USB audio/capture, and any unknown external device before starting.',
            ),
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
    required this.message,
    required this.buttonText,
    required this.onPressed,
    this.findings = const <String>[],
  });

  final String title;
  final IconData icon;
  final bool passed;
  final String message;
  final String buttonText;
  final VoidCallback? onPressed;
  final List<String> findings;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: const Color(0xFF0F4C81)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                ),
              ),
              Icon(
                passed ? Icons.check_circle : Icons.radio_button_unchecked,
                color: passed ? const Color(0xFF16A34A) : const Color(0xFF64748B),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(message),
          if (findings.isNotEmpty) ...[
            const SizedBox(height: 10),
            ...findings.map(
              (finding) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      passed ? Icons.check : Icons.warning_amber_outlined,
                      size: 18,
                      color: passed ? const Color(0xFF16A34A) : const Color(0xFFDC2626),
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: Text(finding)),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 12),
          OutlinedButton(onPressed: onPressed, child: Text(buttonText)),
        ],
      ),
    );
  }
}

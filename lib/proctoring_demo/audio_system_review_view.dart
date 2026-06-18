import 'dart:io';

import 'package:flutter/material.dart';
import 'package:record/record.dart';

class AudioSystemReviewResult {
  const AudioSystemReviewResult({
    required this.audioReady,
    required this.systemReady,
  });

  final bool audioReady;
  final bool systemReady;

  bool get ready => audioReady && systemReady;
}

class AudioSystemReviewView extends StatefulWidget {
  const AudioSystemReviewView({super.key});

  @override
  State<AudioSystemReviewView> createState() => _AudioSystemReviewViewState();
}

class _AudioSystemReviewViewState extends State<AudioSystemReviewView> {
  final AudioRecorder _recorder = AudioRecorder();
  bool _checkingAudio = false;
  bool _audioReady = false;
  bool _systemReady = false;
  String _audioMessage = 'Microphone review has not started.';
  String _systemMessage = 'System review has not started.';

  @override
  void dispose() {
    _recorder.dispose();
    super.dispose();
  }

  Future<void> _checkAudio() async {
    setState(() {
      _checkingAudio = true;
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
        _audioMessage = 'Microphone permission confirmed.';
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
    final platformOk = Platform.isWindows || Platform.isLinux || Platform.isMacOS;
    setState(() {
      _systemReady = platformOk;
      _systemMessage = platformOk
          ? 'Desktop environment confirmed. Continue with full-screen exam mode.'
          : 'Desktop environment required for this proctored exam.';
    });
  }

  void _finish() {
    Navigator.of(context).pop(
      AudioSystemReviewResult(
        audioReady: _audioReady,
        systemReady: _systemReady,
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
              title: 'Audio review',
              icon: Icons.mic_none_outlined,
              passed: _audioReady,
              message: _audioMessage,
              buttonText: _checkingAudio ? 'Checking...' : 'Check microphone',
              onPressed: _checkingAudio ? null : _checkAudio,
            ),
            const SizedBox(height: 14),
            _ReviewCard(
              title: 'System review',
              icon: Icons.desktop_windows_outlined,
              passed: _systemReady,
              message: _systemMessage,
              buttonText: 'Check system',
              onPressed: _checkSystem,
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: ready ? _finish : null,
              icon: const Icon(Icons.check_circle_outline),
              label: const Text('Approve and continue'),
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
  });

  final String title;
  final IconData icon;
  final bool passed;
  final String message;
  final String buttonText;
  final VoidCallback? onPressed;

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
          const SizedBox(height: 12),
          OutlinedButton(onPressed: onPressed, child: Text(buttonText)),
        ],
      ),
    );
  }
}

import 'dart:async';

import 'package:flutter/material.dart';

import 'live_proctoring_event_service.dart';
import 'secure_lockdown_session_service.dart';

class SecureLockdownStatusPanel extends StatefulWidget {
  const SecureLockdownStatusPanel({
    super.key,
    required this.studentId,
    required this.examId,
    required this.attemptId,
    required this.onCriticalEvent,
    this.assessmentType = 'exam',
    this.reviewAudience = 'invigilator',
  });

  final String studentId;
  final String examId;
  final String attemptId;
  final ValueChanged<String> onCriticalEvent;
  final String assessmentType;
  final String reviewAudience;

  @override
  State<SecureLockdownStatusPanel> createState() =>
      _SecureLockdownStatusPanelState();
}

class _SecureLockdownStatusPanelState extends State<SecureLockdownStatusPanel> {
  final SecureLockdownSessionService _lockdown = SecureLockdownSessionService();
  final LiveProctoringEventService _events = LiveProctoringEventService(
    baseUrl: const String.fromEnvironment(
      'KSLAS_API_BASE_URL',
      defaultValue: 'http://127.0.0.1:8080',
    ),
  );

  Timer? _timer;
  bool _checking = false;
  bool _reviewNoticeSent = false;
  SecureLockdownSnapshot? _snapshot;

  @override
  void initState() {
    super.initState();
    unawaited(_start());
    _timer = Timer.periodic(const Duration(seconds: 8), (_) {
      unawaited(_check());
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    unawaited(_lockdown.end());
    _events.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    if (_checking) return;
    _checking = true;
    try {
      final snapshot = await _lockdown.begin();
      if (!mounted) return;
      setState(() => _snapshot = snapshot);
      await _send(snapshot, 'secure_lockdown_started');
      _handle(snapshot);
    } finally {
      _checking = false;
    }
  }

  Future<void> _check() async {
    if (_checking) return;
    _checking = true;
    try {
      final snapshot = await _lockdown.collectSnapshot();
      if (!mounted) return;
      setState(() => _snapshot = snapshot);
      if (!snapshot.ready) await _send(snapshot, 'secure_lockdown_check_failed');
      _handle(snapshot);
    } finally {
      _checking = false;
    }
  }

  void _handle(SecureLockdownSnapshot snapshot) {
    if (snapshot.ready) {
      _reviewNoticeSent = false;
      return;
    }
    if (_reviewNoticeSent) return;
    _reviewNoticeSent = true;
    widget.onCriticalEvent(_studentMessage(snapshot));
  }

  String _studentMessage(SecureLockdownSnapshot snapshot) {
    for (final finding in snapshot.findings) {
      if (finding.severity == 'critical') return finding.message;
    }
    return 'Secure lockdown requires invigilator review.';
  }

  Future<void> _send(SecureLockdownSnapshot snapshot, String eventType) {
    return _events.send(
      LiveProctoringEvent(
        studentId: widget.studentId,
        examId: widget.examId,
        attemptId: widget.attemptId,
        eventType: eventType,
        severity: snapshot.ready ? 'info' : 'critical',
        message: snapshot.ready
            ? 'Secure lockdown checks are active.'
            : 'Secure lockdown check failed during the exam.',
        createdAt: DateTime.now(),
        metadata: snapshot.toJson(),
        assessmentType: widget.assessmentType,
        reviewAudience: widget.reviewAudience,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = _snapshot;
    final ready = snapshot?.ready ?? false;
    final findings = snapshot?.findings ?? const <SecureLockdownFinding>[];
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  ready ? Icons.lock : Icons.warning_amber_outlined,
                  color: ready ? const Color(0xFF16A34A) : const Color(0xFFDC2626),
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Secure lockdown',
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              _checking
                  ? 'Checking secure lockdown...'
                  : ready
                      ? 'Secure lockdown active'
                      : 'Secure lockdown needs review',
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                _LockdownChip(label: 'Platform', value: snapshot?.platformName ?? 'checking'),
                _LockdownChip(
                  label: 'Displays',
                  value: snapshot?.displayCount?.toString() ?? 'unknown',
                ),
                _LockdownChip(
                  label: 'Clipboard',
                  value: snapshot?.clipboardCleared == true ? 'cleared' : 'unconfirmed',
                ),
              ],
            ),
            if (findings.isNotEmpty) ...[
              const SizedBox(height: 8),
              ...findings.take(3).map(
                (finding) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    '- ${finding.message}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _LockdownChip extends StatelessWidget {
  const _LockdownChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Chip(
      label: Text('$label: $value'),
      visualDensity: VisualDensity.compact,
    );
  }
}

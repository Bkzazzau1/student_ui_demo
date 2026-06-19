import 'dart:async';

import 'package:flutter/material.dart';

import 'live_proctoring_event_service.dart';
import 'system_security_review_service.dart';

class LiveSystemSecurityMonitor extends StatefulWidget {
  const LiveSystemSecurityMonitor({
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
  State<LiveSystemSecurityMonitor> createState() =>
      _LiveSystemSecurityMonitorState();
}

class _LiveSystemSecurityMonitorState extends State<LiveSystemSecurityMonitor> {
  final SystemSecurityReviewService _review = SystemSecurityReviewService();
  final LiveProctoringEventService _events = LiveProctoringEventService(
    baseUrl: const String.fromEnvironment(
      'KSLAS_API_BASE_URL',
      defaultValue: 'http://127.0.0.1:8080',
    ),
  );

  Timer? _timer;
  bool _checking = false;
  bool _ready = false;
  String _message = 'Live system device review starting...';
  final List<String> _findings = <String>[];

  @override
  void initState() {
    super.initState();
    unawaited(_checkNow());
    _timer = Timer.periodic(const Duration(seconds: 10), (_) {
      unawaited(_checkNow());
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _events.dispose();
    super.dispose();
  }

  Future<void> _checkNow() async {
    if (_checking) return;
    _checking = true;
    try {
      final result = await _review.check();
      if (!mounted) return;
      setState(() {
        _ready = result.ready;
        _message = result.message;
        _findings
          ..clear()
          ..addAll(result.findings.take(3));
      });
      if (!result.ready) {
        await _raiseCritical(result);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _ready = false;
        _message = 'Live system device review could not complete.';
        _findings
          ..clear()
          ..add(e.toString());
      });
      await _events.send(
        LiveProctoringEvent(
          studentId: widget.studentId,
          examId: widget.examId,
          attemptId: widget.attemptId,
          eventType: 'system_review_unavailable',
          severity: 'critical',
          message: 'Live system review could not complete during the exam.',
          createdAt: DateTime.now(),
          metadata: <String, Object?>{'error': e.toString()},
          assessmentType: widget.assessmentType,
          reviewAudience: widget.reviewAudience,
        ),
      );
      widget.onCriticalEvent(
        'Live system review could not complete during the exam.',
      );
    } finally {
      _checking = false;
    }
  }

  Future<void> _raiseCritical(SystemSecurityReviewResult result) async {
    final sent = await _events.send(
      LiveProctoringEvent(
        studentId: widget.studentId,
        examId: widget.examId,
        attemptId: widget.attemptId,
        eventType: 'system_device_check_failed',
        severity: 'critical',
        message: result.message,
        createdAt: DateTime.now(),
        metadata: result.toJson(),
        assessmentType: widget.assessmentType,
        reviewAudience: widget.reviewAudience,
      ),
    );
    if (!mounted) return;
    widget.onCriticalEvent(
      sent
          ? result.message
          : '${result.message} Monitoring event could not be confirmed by backend.',
    );
  }

  @override
  Widget build(BuildContext context) {
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
                  _ready ? Icons.check_circle : Icons.warning_amber_outlined,
                  color: _ready
                      ? const Color(0xFF16A34A)
                      : const Color(0xFFDC2626),
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Live system device review',
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(_checking ? 'Checking system devices...' : _message),
            if (_findings.isNotEmpty) ...[
              const SizedBox(height: 8),
              ..._findings.map(
                (finding) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    '- $finding',
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

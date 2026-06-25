import 'dart:async';

import 'package:flutter/material.dart';

import 'live_event_local_record_service.dart';
import 'live_proctoring_event_service.dart';
import 'secure_lockdown_session_service.dart';
import 'system_security_review_service.dart';

class LiveSystemLockdownMonitor extends StatefulWidget {
  const LiveSystemLockdownMonitor({
    super.key,
    required this.studentId,
    required this.examId,
    required this.attemptId,
    required this.onReviewRequired,
    this.assessmentType = 'exam',
    this.reviewAudience = 'invigilator',
  });

  final String studentId;
  final String examId;
  final String attemptId;
  final ValueChanged<String> onReviewRequired;
  final String assessmentType;
  final String reviewAudience;

  @override
  State<LiveSystemLockdownMonitor> createState() => _LiveSystemLockdownMonitorState();
}

class _LiveSystemLockdownMonitorState extends State<LiveSystemLockdownMonitor> {
  final SystemSecurityReviewService _systemReview = SystemSecurityReviewService();
  final SecureLockdownSessionService _secureSession = SecureLockdownSessionService();
  final LiveEventLocalRecordService _localRecords = const LiveEventLocalRecordService();
  final LiveProctoringEventService _events = LiveProctoringEventService(
    baseUrl: const String.fromEnvironment(
      'KSLAS_API_BASE_URL',
      defaultValue: 'http://127.0.0.1:8080',
    ),
  );

  Timer? _timer;
  bool _checking = false;
  bool _startedSecureSession = false;
  bool _ready = false;
  String _message = 'Starting secure exam checks...';
  final List<String> _findings = <String>[];
  SecureLockdownSnapshot? _secureSnapshot;

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
    unawaited(_secureSession.end());
    _events.dispose();
    super.dispose();
  }

  Future<void> _checkNow() async {
    if (_checking) return;
    _checking = true;
    try {
      final system = await _systemReview.check();
      final secure = await _secureSnapshotForCycle();
      final ready = system.ready && secure.ready;
      if (!mounted) return;
      setState(() {
        _ready = ready;
        _secureSnapshot = secure;
        _message = ready ? 'Secure exam checks active.' : _studentMessage(system, secure);
        _findings
          ..clear()
          ..addAll(system.findings)
          ..addAll(secure.findings.map((finding) => finding.message));
      });
      if (!ready) await _sendReviewEvent(system, secure);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _ready = false;
        _message = 'Secure exam checks could not complete.';
        _findings
          ..clear()
          ..add(e.toString());
      });
      widget.onReviewRequired('Secure exam checks could not complete.');
    } finally {
      _checking = false;
    }
  }

  Future<SecureLockdownSnapshot> _secureSnapshotForCycle() {
    if (!_startedSecureSession) {
      _startedSecureSession = true;
      return _secureSession.begin();
    }
    return _secureSession.collectSnapshot();
  }

  String _studentMessage(
    SystemSecurityReviewResult system,
    SecureLockdownSnapshot secure,
  ) {
    if (!system.ready) return system.message;
    if (!secure.ready) return 'Secure exam mode needs review before continuing.';
    return 'Secure exam checks need review before continuing.';
  }

  Future<void> _sendReviewEvent(
    SystemSecurityReviewResult system,
    SecureLockdownSnapshot secure,
  ) async {
    final message = _studentMessage(system, secure);
    final eventType = secure.ready ? 'system_device_check_failed' : 'secure_exam_mode_check_failed';
    final metadata = <String, Object?>{
      'system_review': system.toJson(),
      'secure_exam_mode': secure.toJson(),
    };
    final event = LiveProctoringEvent(
      studentId: widget.studentId,
      examId: widget.examId,
      attemptId: widget.attemptId,
      eventType: eventType,
      severity: 'critical',
      message: message,
      createdAt: DateTime.now(),
      metadata: metadata,
      assessmentType: widget.assessmentType,
      reviewAudience: widget.reviewAudience,
    );
    final localRecord = await _localRecords.saveEvent(event);
    if (localRecord != null) {
      metadata['local_record'] = localRecord;
    }

    final synced = await _events.send(
      LiveProctoringEvent(
        studentId: widget.studentId,
        examId: widget.examId,
        attemptId: widget.attemptId,
        eventType: eventType,
        severity: 'critical',
        message: message,
        createdAt: event.createdAt,
        metadata: metadata,
        assessmentType: widget.assessmentType,
        reviewAudience: widget.reviewAudience,
      ),
    );
    if (!mounted) return;
    widget.onReviewRequired(synced ? message : '$message Please wait for review.');
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = _secureSnapshot;
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
                  color: _ready ? const Color(0xFF16A34A) : const Color(0xFFDC2626),
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Secure exam checks',
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(_checking ? 'Checking secure exam state...' : _message),
            if (snapshot != null) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  _CheckChip(label: 'Platform', value: snapshot.platformName),
                  _CheckChip(label: 'Displays', value: snapshot.displayCount?.toString() ?? 'unknown'),
                  _CheckChip(label: 'Clipboard', value: snapshot.clipboardCleared ? 'cleared' : 'unconfirmed'),
                ],
              ),
            ],
            if (_findings.isNotEmpty) ...[
              const SizedBox(height: 8),
              ..._findings.take(5).map(
                (finding) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text('- $finding', style: Theme.of(context).textTheme.bodySmall),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CheckChip extends StatelessWidget {
  const _CheckChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Chip(label: Text('$label: $value'), visualDensity: VisualDensity.compact);
  }
}

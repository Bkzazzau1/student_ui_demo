import 'package:flutter/material.dart';

import '../face_demo/demo_face_id_service.dart';
import '../face_demo/demo_face_id_view.dart';
import '../proctoring_demo/proctoring_demo_home.dart';
import '../proctoring_demo/security_review_service.dart';
import 'demo_exam_attempt_view.dart';
import 'demo_exam_models.dart';
import 'demo_exam_service.dart';

class SecureExamSetupView extends StatefulWidget {
  const SecureExamSetupView({super.key, required this.assessment});

  final DemoAssessment assessment;

  @override
  State<SecureExamSetupView> createState() => _SecureExamSetupViewState();
}

class _SecureExamSetupViewState extends State<SecureExamSetupView> {
  final DemoFaceIdService _faceIdService = DemoFaceIdService();
  late DemoFaceIdSnapshot _faceId;
  bool _roomApproved = false;
  bool _audioApproved = false;
  bool _systemApproved = false;
  String? _manifestPath;
  String? _attemptId;
  SecurityReviewResult? _startApproval;

  @override
  void initState() {
    super.initState();
    _faceId = _faceIdService.load();
  }

  bool get _needsChecks => widget.assessment.remoteProctored;

  bool get _hasReviewApproval =>
      !_needsChecks ||
      (_roomApproved &&
          _manifestPath != null &&
          _attemptId != null &&
          _startApproval?.approvedToStart == true);

  bool _canStartOnDevice(BuildContext context) {
    final phoneSized = MediaQuery.sizeOf(context).shortestSide < 600;
    return !phoneSized || !widget.assessment.graded;
  }

  bool _canStart(BuildContext context) {
    final faceOk = !widget.assessment.graded || _faceId.isComplete;
    final roomOk = !_needsChecks || _hasReviewApproval;
    final audioOk = !_needsChecks || _audioApproved;
    final systemOk = !_needsChecks || _systemApproved;
    return faceOk &&
        roomOk &&
        audioOk &&
        systemOk &&
        _canStartOnDevice(context);
  }

  @override
  Widget build(BuildContext context) {
    final questions = DemoExamService.questionsFor(widget.assessment);
    return Scaffold(
      appBar: AppBar(title: Text(_setupTitle)),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          _Header(
            assessment: widget.assessment,
            questionCount: questions.length,
          ),
          const SizedBox(height: 14),
          _Checklist(
            faceOk: !widget.assessment.graded || _faceId.isComplete,
            roomOk: !_needsChecks || _hasReviewApproval,
            audioOk: !_needsChecks || _audioApproved,
            systemOk: !_needsChecks || _systemApproved,
            backendOk: !_needsChecks || _startApproval?.approvedToStart == true,
            manifestPath: _manifestPath,
            approval: _startApproval,
            needsChecks: _needsChecks,
          ),
          const SizedBox(height: 14),
          _Rules(remote: widget.assessment.remoteProctored),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              if (widget.assessment.graded)
                FilledButton.icon(
                  onPressed: _openFaceId,
                  icon: const Icon(Icons.face_retouching_natural),
                  label: Text(
                    _faceId.isComplete ? 'Face ID active' : 'Set up Face ID',
                  ),
                ),
              if (_needsChecks)
                FilledButton.icon(
                  onPressed: _faceId.isComplete ? _openRoomScan : null,
                  icon: const Icon(Icons.screen_rotation_alt_outlined),
                  label: Text(
                    _hasReviewApproval
                        ? 'Start approval received'
                        : 'Request start approval',
                  ),
                ),
              FilledButton.icon(
                onPressed: _canStart(context) ? _startExam : null,
                icon: const Icon(Icons.edit_document),
                label: Text(_startLabel),
              ),
              OutlinedButton.icon(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.arrow_back),
                label: const Text('Back'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _openFaceId() async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => DemoFaceIdView(
          onComplete: () => setState(() => _faceId = _faceIdService.load()),
        ),
      ),
    );
    if (!mounted) return;
    setState(() => _faceId = _faceIdService.load());
  }

  Future<void> _openRoomScan() async {
    final attemptId = 'attempt-${DateTime.now().millisecondsSinceEpoch}';
    setState(() {
      _roomApproved = false;
      _audioApproved = false;
      _systemApproved = false;
      _manifestPath = null;
      _attemptId = attemptId;
      _startApproval = null;
    });
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => ProctoringDemoHome(
          compactExamGate: true,
          examId: widget.assessment.id,
          attemptId: attemptId,
          onStartApproved: (manifestPath, result) {
            if (manifestPath == null || manifestPath.trim().isEmpty) {
              setState(() {
                _roomApproved = false;
                _manifestPath = null;
                _startApproval = null;
              });
              return;
            }
            setState(() {
              _roomApproved = true;
              _audioApproved = true;
              _systemApproved = true;
              _manifestPath = manifestPath;
              _startApproval = result;
            });
            Navigator.of(context).pop();
          },
        ),
      ),
    );
  }

  Future<void> _startExam() async {
    if (!_canStartOnDevice(context)) {
      await _showPhoneBlockedMessage();
      return;
    }
    if (!_canStart(context)) {
      await _showBlockedStartMessage();
      return;
    }
    if (widget.assessment.remoteProctored &&
        (_manifestPath == null ||
            !_roomApproved ||
            _attemptId == null ||
            _startApproval?.approvedToStart != true)) {
      await _showBlockedStartMessage();
      return;
    }
    final result = await Navigator.of(context).push<DemoExamResult>(
      MaterialPageRoute<DemoExamResult>(
        builder: (_) => DemoExamAttemptView(
          assessment: widget.assessment,
          proctoringManifestPath: _manifestPath,
          attemptId:
              _attemptId ?? 'attempt-${DateTime.now().millisecondsSinceEpoch}',
          examStartToken: _startApproval?.examStartToken ?? '',
          agentDecision: widget.assessment.remoteProctored
              ? 'approved_to_start'
              : widget.assessment.graded
              ? 'face_id_verified'
              : 'attendance_only',
        ),
      ),
    );
    if (!mounted || result == null) return;
    Navigator.of(context).pop(result);
  }

  Future<void> _showBlockedStartMessage() {
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Exam cannot start yet'),
        content: const Text(
          'Complete the full exam check and wait for approval before starting the exam.',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _showPhoneBlockedMessage() {
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Use a larger device'),
        content: const Text(
          'Exam and graded assessment attempts must be completed on a laptop, tablet, Windows desktop, or Mac. Phones are only used as an extra camera when needed.',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  String get _setupTitle {
    if (widget.assessment.isStrictExam) return 'Exam setup';
    if (widget.assessment.attendanceOnly) return 'Attendance practice';
    return 'Assessment setup';
  }

  String get _startLabel {
    if (widget.assessment.isStrictExam) return 'Start exam';
    if (widget.assessment.attendanceOnly) return 'Mark attendance and start';
    return 'Start assessment';
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.assessment, required this.questionCount});

  final DemoAssessment assessment;
  final int questionCount;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            assessment.title,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '${assessment.course.code} - ${assessment.course.title}',
            style: const TextStyle(color: Color(0xFFCBD5E1), fontSize: 16),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _DarkTag('${assessment.durationMinutes} minutes'),
              _DarkTag('$questionCount questions'),
              _DarkTag(assessment.graded ? 'Official graded' : 'Practice'),
              _DarkTag(
                assessment.remoteProctored
                    ? 'Full exam check required'
                    : 'Standard access',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Checklist extends StatelessWidget {
  const _Checklist({
    required this.faceOk,
    required this.roomOk,
    required this.audioOk,
    required this.systemOk,
    required this.backendOk,
    required this.needsChecks,
    required this.manifestPath,
    required this.approval,
  });

  final bool faceOk;
  final bool roomOk;
  final bool audioOk;
  final bool systemOk;
  final bool backendOk;
  final bool needsChecks;
  final String? manifestPath;
  final SecurityReviewResult? approval;

  @override
  Widget build(BuildContext context) {
    final rows = <_CheckRow>[
      _CheckRow('Face ID', faceOk),
      if (needsChecks) _CheckRow('Photos and video', roomOk),
      if (needsChecks) _CheckRow('Sound check', audioOk),
      if (needsChecks) _CheckRow('Device check', systemOk),
      if (needsChecks) _CheckRow('Backend start approval', backendOk),
    ];
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Startup checklist',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 12),
          ...rows,
          if (manifestPath != null) ...[
            const SizedBox(height: 8),
            Text(
              'Saved record: $manifestPath',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          if (approval != null) ...[
            const SizedBox(height: 8),
            Text(
              _approvalText(approval!),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ],
      ),
    );
  }

  String _approvalText(SecurityReviewResult approval) {
    final status = approval.status.isEmpty ? approval.decision : approval.status;
    if (approval.approvedToStart) {
      return 'Backend approved start. Token received.';
    }
    if (approval.requiresHumanReview) {
      return 'Waiting for exam officer review.';
    }
    return 'Backend decision: $status';
  }
}

class _CheckRow extends StatelessWidget {
  const _CheckRow(this.label, this.ok);

  final String label;
  final bool ok;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(
            ok ? Icons.check_circle : Icons.radio_button_unchecked,
            color: ok ? const Color(0xFF16A34A) : const Color(0xFF94A3B8),
          ),
          const SizedBox(width: 8),
          Text(label),
        ],
      ),
    );
  }
}

class _Rules extends StatelessWidget {
  const _Rules({required this.remote});

  final bool remote;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFDE68A)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Rules before you start',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          Text(
            remote
                ? 'Complete identity, room, video, sound, and device checks. Camera and sound must remain ready until you submit.'
                : 'Keep your login secure and submit before the timer ends.',
          ),
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
      decoration: BoxDecoration(
        color: const Color(0xFF1F2937),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

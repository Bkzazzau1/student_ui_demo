import 'package:flutter/material.dart';

import '../face_demo/demo_face_id_service.dart';
import '../face_demo/demo_face_id_view.dart';
import '../proctoring_demo/audio_system_review_view.dart';
import '../proctoring_demo/proctoring_demo_home.dart';
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

  @override
  void initState() {
    super.initState();
    _faceId = _faceIdService.load();
  }

  bool get _needsChecks => widget.assessment.remoteProctored;

  bool get _hasReviewApproval =>
      !_needsChecks ||
      (_roomApproved && _manifestPath != null && _attemptId != null);

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
            manifestPath: _manifestPath,
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
                        ? 'Room scan approved'
                        : 'Run 360 room scan',
                  ),
                ),
              if (_needsChecks)
                FilledButton.icon(
                  onPressed: _hasReviewApproval ? _openAudioSystemReview : null,
                  icon: const Icon(Icons.settings_voice_outlined),
                  label: Text(
                    _audioApproved && _systemApproved
                        ? 'Audio and system approved'
                        : 'Run audio and system review',
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
    });
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => ProctoringDemoHome(
          compactExamGate: true,
          examId: widget.assessment.id,
          attemptId: attemptId,
          onApproved: (manifestPath) {
            if (manifestPath == null || manifestPath.trim().isEmpty) {
              setState(() {
                _roomApproved = false;
                _manifestPath = null;
              });
              return;
            }
            setState(() {
              _roomApproved = true;
              _manifestPath = manifestPath;
            });
            Navigator.of(context).pop();
          },
        ),
      ),
    );
  }

  Future<void> _openAudioSystemReview() async {
    final result = await Navigator.of(context).push<AudioSystemReviewResult>(
      MaterialPageRoute<AudioSystemReviewResult>(
        builder: (_) => const AudioSystemReviewView(),
      ),
    );
    if (!mounted || result == null) return;
    setState(() {
      _audioApproved = result.audioReady;
      _systemApproved = result.systemReady;
    });
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
        (_manifestPath == null || !_roomApproved || _attemptId == null)) {
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
          agentDecision: widget.assessment.remoteProctored
              ? 'security_review_ready'
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
          'Complete all required checks and wait for security review approval before starting the exam.',
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
          'Exam and graded assessment attempts must be completed on a laptop, tablet, Windows desktop, or Mac. Phones are only used for companion camera monitoring.',
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
                    ? 'Full proctoring required'
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
    required this.needsChecks,
    required this.manifestPath,
  });

  final bool faceOk;
  final bool roomOk;
  final bool audioOk;
  final bool systemOk;
  final bool needsChecks;
  final String? manifestPath;

  @override
  Widget build(BuildContext context) {
    final rows = <_CheckRow>[
      _CheckRow('Face ID', faceOk),
      if (needsChecks) _CheckRow('360 room scan', roomOk),
      if (needsChecks) _CheckRow('Audio review', audioOk),
      if (needsChecks) _CheckRow('System review', systemOk),
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
              'Evidence record: $manifestPath',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ],
      ),
    );
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
                ? 'Complete identity, room, audio, system, and security review checks. Camera and audio readiness remain required until submission.'
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

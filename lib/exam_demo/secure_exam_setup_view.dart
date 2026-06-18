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

  @override
  void initState() {
    super.initState();
    _faceId = _faceIdService.load();
  }

  bool get _needsChecks => widget.assessment.remoteProctored;

  bool get _canStart {
    final faceOk = !widget.assessment.graded || _faceId.isComplete;
    final roomOk = !_needsChecks || _roomApproved;
    final audioOk = !_needsChecks || _audioApproved;
    final systemOk = !_needsChecks || _systemApproved;
    return faceOk && roomOk && audioOk && systemOk;
  }

  @override
  Widget build(BuildContext context) {
    final questions = DemoExamService.questionsFor(widget.assessment);
    return Scaffold(
      appBar: AppBar(title: const Text('Exam setup')),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          _Header(assessment: widget.assessment, questionCount: questions.length),
          const SizedBox(height: 14),
          _Checklist(
            faceOk: !widget.assessment.graded || _faceId.isComplete,
            roomOk: !_needsChecks || _roomApproved,
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
                  label: Text(_faceId.isComplete ? 'Face ID active' : 'Set up Face ID'),
                ),
              if (_needsChecks)
                FilledButton.icon(
                  onPressed: _faceId.isComplete ? _openRoomScan : null,
                  icon: const Icon(Icons.screen_rotation_alt_outlined),
                  label: Text(_roomApproved ? 'Room scan approved' : 'Run 360 room scan'),
                ),
              if (_needsChecks)
                FilledButton.icon(
                  onPressed: _roomApproved ? _openAudioSystemReview : null,
                  icon: const Icon(Icons.settings_voice_outlined),
                  label: Text(
                    _audioApproved && _systemApproved
                        ? 'Audio and system approved'
                        : 'Run audio and system review',
                  ),
                ),
              FilledButton.icon(
                onPressed: _canStart ? _startExam : null,
                icon: const Icon(Icons.edit_document),
                label: const Text('Start exam'),
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
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => ProctoringDemoHome(
          compactExamGate: true,
          examId: widget.assessment.id,
          attemptId: 'attempt-${DateTime.now().millisecondsSinceEpoch}',
          onApproved: (manifestPath) {
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
    final result = await Navigator.of(context).push<DemoExamResult>(
      MaterialPageRoute<DemoExamResult>(
        builder: (_) => DemoExamAttemptView(
          assessment: widget.assessment,
          proctoringManifestPath: _manifestPath,
          agentDecision: widget.assessment.remoteProctored
              ? 'security_review_ready'
              : widget.assessment.graded
              ? 'face_id_verified'
              : 'not_required',
        ),
      ),
    );
    if (!mounted || result == null) return;
    Navigator.of(context).pop(result);
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
              _DarkTag(assessment.remoteProctored ? 'Full proctoring required' : 'Standard access'),
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
    return _Card(
      title: 'Startup checklist',
      children: [
        _CheckRow(passed: faceOk, title: 'Face ID', detail: 'Student identity must be confirmed.'),
        if (needsChecks)
          _CheckRow(passed: roomOk, title: '360 room scan', detail: 'All required room views must be captured.'),
        if (needsChecks)
          _CheckRow(passed: audioOk, title: 'Audio review', detail: 'Microphone permission must be confirmed.'),
        if (needsChecks)
          _CheckRow(passed: systemOk, title: 'System review', detail: 'Desktop exam environment must be confirmed.'),
        if (manifestPath != null)
          Text(
            'Evidence record: $manifestPath',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
      ],
    );
  }
}

class _Rules extends StatelessWidget {
  const _Rules({required this.remote});

  final bool remote;

  @override
  Widget build(BuildContext context) {
    return _Card(
      title: 'Exam rules',
      children: [
        const _RuleRow('Do not leave the exam screen during the attempt.'),
        const _RuleRow('Do not use a phone, textbook, or another person.'),
        const _RuleRow('Submit only your own work.'),
        if (remote) const _RuleRow('Camera and audio readiness remain required until submission.'),
      ],
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
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
          Text(title, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    );
  }
}

class _CheckRow extends StatelessWidget {
  const _CheckRow({required this.passed, required this.title, required this.detail});

  final bool passed;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(passed ? Icons.check_circle : Icons.radio_button_unchecked, color: passed ? const Color(0xFF16A34A) : const Color(0xFF64748B)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
                Text(detail, style: const TextStyle(color: Color(0xFF475569))),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RuleRow extends StatelessWidget {
  const _RuleRow(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          const Icon(Icons.circle, size: 8, color: Color(0xFF64748B)),
          const SizedBox(width: 10),
          Expanded(child: Text(text)),
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
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(text, style: const TextStyle(color: Colors.white)),
    );
  }
}

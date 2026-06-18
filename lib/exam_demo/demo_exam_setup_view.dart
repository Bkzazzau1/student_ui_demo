import 'package:flutter/material.dart';

import '../face_demo/demo_face_id_service.dart';
import '../face_demo/demo_face_id_view.dart';
import '../proctoring_demo/proctoring_demo_home.dart';
import 'demo_exam_attempt_view.dart';
import 'demo_exam_models.dart';
import 'demo_exam_service.dart';

class DemoExamSetupView extends StatefulWidget {
  const DemoExamSetupView({super.key, required this.assessment});

  final DemoAssessment assessment;

  @override
  State<DemoExamSetupView> createState() => _DemoExamSetupViewState();
}

class _DemoExamSetupViewState extends State<DemoExamSetupView> {
  final DemoFaceIdService _faceIdService = DemoFaceIdService();
  late DemoFaceIdSnapshot _faceId;
  bool _proctoringApproved = false;
  String? _manifestPath;

  @override
  void initState() {
    super.initState();
    _faceId = _faceIdService.load();
  }

  @override
  Widget build(BuildContext context) {
    final assessment = widget.assessment;
    final questions = DemoExamService.questionsFor(assessment);
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      appBar: AppBar(title: const Text('Exam setup')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(18),
          children: [
            _SetupHeader(
              assessment: assessment,
              questionCount: questions.length,
            ),
            const SizedBox(height: 14),
            _ChecklistCard(
              assessment: assessment,
              faceIdComplete: _faceId.isComplete,
              proctoringApproved: _proctoringApproved,
              manifestPath: _manifestPath,
            ),
            const SizedBox(height: 14),
            _RulesCard(remoteProctored: assessment.remoteProctored),
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                if (assessment.graded)
                  FilledButton.icon(
                    onPressed: _openFaceId,
                    icon: const Icon(Icons.face_retouching_natural),
                    label: Text(
                      _faceId.isComplete ? 'Face ID active' : 'Set up Face ID',
                    ),
                  ),
                if (assessment.remoteProctored)
                  FilledButton.icon(
                    onPressed: _faceId.isComplete ? _openProctoring : null,
                    icon: const Icon(Icons.security_outlined),
                    label: Text(
                      _proctoringApproved
                          ? 'Proctoring approved'
                          : 'Run proctoring gate',
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
      ),
    );
  }

  bool get _canStart =>
      (!widget.assessment.graded || _faceId.isComplete) &&
      (!widget.assessment.remoteProctored || _proctoringApproved);

  Future<void> _openFaceId() async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => DemoFaceIdView(
          onComplete: () {
            setState(() => _faceId = _faceIdService.load());
          },
        ),
      ),
    );
    if (!mounted) return;
    setState(() => _faceId = _faceIdService.load());
  }

  Future<void> _openProctoring() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => ProctoringDemoHome(
          compactExamGate: true,
          onApproved: (manifestPath) {
            setState(() {
              _proctoringApproved = true;
              _manifestPath = manifestPath;
            });
            Navigator.of(context).pop();
          },
        ),
      ),
    );
  }

  Future<void> _startExam() async {
    final result = await Navigator.of(context).push<DemoExamResult>(
      MaterialPageRoute<DemoExamResult>(
        builder: (_) => DemoExamAttemptView(
          assessment: widget.assessment,
          proctoringManifestPath: _manifestPath,
          agentDecision: widget.assessment.remoteProctored
              ? 'ready'
              : 'not_required',
        ),
      ),
    );
    if (!mounted || result == null) return;
    Navigator.of(context).pop(result);
  }
}

class _SetupHeader extends StatelessWidget {
  const _SetupHeader({required this.assessment, required this.questionCount});

  final DemoAssessment assessment;
  final int questionCount;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(8),
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
                    ? 'Proctoring required'
                    : 'No proctoring',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ChecklistCard extends StatelessWidget {
  const _ChecklistCard({
    required this.assessment,
    required this.faceIdComplete,
    required this.proctoringApproved,
    required this.manifestPath,
  });

  final DemoAssessment assessment;
  final bool faceIdComplete;
  final bool proctoringApproved;
  final String? manifestPath;

  @override
  Widget build(BuildContext context) {
    return _Card(
      title: 'Startup checklist',
      children: [
        _CheckRow(
          passed: true,
          title: 'Assessment loaded',
          detail: 'Questions and timing are ready for demo use.',
        ),
        _CheckRow(
          passed: !assessment.graded || faceIdComplete,
          title: 'Identity context',
          detail: assessment.graded
              ? faceIdComplete
                    ? 'Face ID is active and attached to this attempt.'
                    : 'Set up Face ID before proctoring or exam startup.'
              : 'Demo student profile is attached to this attempt.',
        ),
        _CheckRow(
          passed: !assessment.remoteProctored || proctoringApproved,
          title: 'Agentic proctoring gate',
          detail: assessment.remoteProctored
              ? proctoringApproved
                    ? 'Room scan approved. Evidence manifest saved.'
                    : 'Run 360 scan and agent review before starting.'
              : 'Not required for this assessment.',
        ),
        if (manifestPath != null)
          Text(
            'Manifest: $manifestPath',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall,
          ),
      ],
    );
  }
}

class _RulesCard extends StatelessWidget {
  const _RulesCard({required this.remoteProctored});

  final bool remoteProctored;

  @override
  Widget build(BuildContext context) {
    return _Card(
      title: 'Exam rules',
      children: [
        const Text('Answer all visible sections before submitting.'),
        const Text('Do not refresh, close the window, or switch devices.'),
        const Text('Keep camera view stable during proctored attempts.'),
        if (remoteProctored)
          const Text(
            'Unauthorized items or repeated low light require review.',
          ),
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
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 10),
          ...children.map(
            (child) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: child,
            ),
          ),
        ],
      ),
    );
  }
}

class _CheckRow extends StatelessWidget {
  const _CheckRow({
    required this.passed,
    required this.title,
    required this.detail,
  });

  final bool passed;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          passed ? Icons.check_circle : Icons.radio_button_unchecked,
          color: passed ? const Color(0xFF16A34A) : const Color(0xFF64748B),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
              Text(detail),
            ],
          ),
        ),
      ],
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
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

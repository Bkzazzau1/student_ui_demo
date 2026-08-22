import 'package:flutter/material.dart';

import '../face_demo/demo_face_id_service.dart';
import '../face_demo/demo_face_id_view.dart';
import '../face_demo/face_identity_check_view.dart';
import '../proctoring_demo/proctoring_demo_home.dart';
import '../proctoring_demo/security_review_service.dart';
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
  // Reset whenever enrollment changes; proves a fresh live 1:1 comparison
  // was done for THIS attempt, not merely that enrollment happened at some
  // point in the past.
  bool _identityChecked = false;
  bool _proctoringApproved = false;
  String? _manifestPath;
  String? _attemptId;
  SecurityReviewResult? _startApproval;

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
              enrolled: _faceId.isComplete,
              identityChecked: _identityChecked,
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
                    onPressed: _faceId.isComplete
                        ? _openIdentityCheck
                        : _openFaceId,
                    icon: const Icon(Icons.face_retouching_natural),
                    label: Text(
                      !_faceId.isComplete
                          ? 'Set up Face ID'
                          : _identityChecked
                          ? 'Identity confirmed'
                          : 'Confirm identity',
                    ),
                  ),
                if (assessment.remoteProctored)
                  FilledButton.icon(
                    onPressed: _faceOk ? _openProctoring : null,
                    icon: const Icon(Icons.security_outlined),
                    label: Text(
                      _proctoringApproved
                          ? 'Exam check approved'
                          : 'Run exam check',
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

  // Enrollment alone (`_faceId.isComplete`) only proves a Face ID was set up
  // at some point; `_identityChecked` is the fresh, per-attempt 1:1 live
  // comparison and is what actually gates starting the exam.
  bool get _faceOk => !widget.assessment.graded || (_faceId.isComplete && _identityChecked);

  bool get _canStart =>
      _faceOk &&
      (!widget.assessment.remoteProctored ||
          (_proctoringApproved &&
              _startApproval?.approvedToStart == true));

  /// Opens enrollment. Only reachable before the student has enrolled;
  /// afterward the button routes to [_openIdentityCheck] instead, so this
  /// screen can never be used to replace an already-approved identity.
  Future<void> _openFaceId() async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => DemoFaceIdView(
          onComplete: () {
            setState(() {
              _faceId = _faceIdService.load();
              _identityChecked = false;
            });
          },
        ),
      ),
    );
    if (!mounted) return;
    setState(() {
      _faceId = _faceIdService.load();
      _identityChecked = false;
    });
  }

  /// Runs the fresh, per-attempt 1:1 identity check against the already
  /// approved template. Never enrolls, never resets, never searches across
  /// students.
  Future<void> _openIdentityCheck() async {
    final approved = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => FaceIdentityCheckView(
          examId: widget.assessment.id,
          attemptId:
              _attemptId ?? 'attempt-${DateTime.now().millisecondsSinceEpoch}',
        ),
      ),
    );
    if (!mounted) return;
    setState(() => _identityChecked = approved == true);
  }

  Future<void> _openProctoring() async {
    final attemptId = 'attempt-${DateTime.now().millisecondsSinceEpoch}';
    setState(() {
      _proctoringApproved = false;
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
            setState(() {
              _proctoringApproved = true;
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
                    ? 'Face ID + exam check required'
                    : 'Face ID optional',
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
    required this.enrolled,
    required this.identityChecked,
    required this.proctoringApproved,
    required this.manifestPath,
  });

  final DemoAssessment assessment;
  final bool enrolled;
  final bool identityChecked;
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
          detail: 'Questions and timing are ready for presentation use.',
        ),
        _CheckRow(
          passed: !assessment.graded || (enrolled && identityChecked),
          title: 'Identity check',
          detail: !assessment.graded
              ? 'Practice assessment can start without Face ID.'
              : !enrolled
              ? 'Set up Face ID before the security check or exam startup.'
              : identityChecked
              ? 'A fresh identity check was confirmed for this attempt.'
              : 'Confirm your identity with a fresh live check before this attempt.',
        ),
        _CheckRow(
          passed: !assessment.remoteProctored || proctoringApproved,
          title: 'Pre-exam security check',
          detail: assessment.remoteProctored
              ? proctoringApproved
                    ? 'Guided scan approved. Record saved.'
                    : 'Run the guided 360 scan and exam check before starting.'
              : 'Not required for this assessment.',
        ),
        if (manifestPath != null)
          Text(
            'Saved record: $manifestPath',
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
        if (remoteProctored)
          const Text(
            'Face ID and exam check approval are required before this exam starts.',
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

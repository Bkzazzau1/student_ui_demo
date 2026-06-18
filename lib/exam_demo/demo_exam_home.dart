import 'package:flutter/material.dart';

import '../face_demo/demo_face_id_view.dart';
import '../proctoring_demo/proctoring_demo_home.dart';
import 'demo_exam_models.dart';
import 'demo_exam_result_view.dart';
import 'demo_exam_service.dart';
import 'demo_exam_setup_view.dart';

class DemoExamHome extends StatelessWidget {
  const DemoExamHome({super.key});

  @override
  Widget build(BuildContext context) {
    final assessments = DemoExamService.assessments();
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      appBar: AppBar(
        title: const Text('K-SLAS Student Demo'),
        actions: [
          TextButton.icon(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const DemoFaceIdView()),
            ),
            icon: const Icon(Icons.face_retouching_natural),
            label: const Text('Face ID setup'),
          ),
          TextButton.icon(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const ProctoringDemoHome(),
              ),
            ),
            icon: const Icon(Icons.security_outlined),
            label: const Text('Proctoring demo'),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(18),
          children: [
            _SummaryBand(assessments: assessments),
            const SizedBox(height: 14),
            Text(
              'Examinations',
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 6),
            const Text(
              'Presentation mode shows the student exam flow, Face ID enrollment, and the guided Agentic AI proctoring gate for remote proctored exams.',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: Color(0xFF475569),
              ),
            ),
            const SizedBox(height: 12),
            ...assessments.map(
              (assessment) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _AssessmentCard(
                  assessment: assessment,
                  onStart: () => _openSetup(context, assessment),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openSetup(
    BuildContext context,
    DemoAssessment assessment,
  ) async {
    final result = await Navigator.of(context).push<DemoExamResult>(
      MaterialPageRoute<DemoExamResult>(
        builder: (_) => DemoExamSetupView(assessment: assessment),
      ),
    );
    if (result == null || !context.mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => DemoExamResultView(result: result),
      ),
    );
  }
}

class _SummaryBand extends StatelessWidget {
  const _SummaryBand({required this.assessments});

  final List<DemoAssessment> assessments;

  @override
  Widget build(BuildContext context) {
    final graded = assessments.where((item) => item.graded).length;
    final remote = assessments.where((item) => item.remoteProctored).length;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Wrap(
        spacing: 28,
        runSpacing: 14,
        children: [
          _SummaryMetric(label: 'Available exams', value: '${assessments.length}'),
          _SummaryMetric(label: 'Graded', value: '$graded'),
          _SummaryMetric(label: 'Remote proctored', value: '$remote'),
          const _SummaryMetric(label: 'Demo shell', value: 'Exam + Face + AI'),
        ],
      ),
    );
  }
}

class _SummaryMetric extends StatelessWidget {
  const _SummaryMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 170,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w900,
            ),
          ),
          Text(label, style: const TextStyle(color: Color(0xFFCBD5E1))),
        ],
      ),
    );
  }
}

class _AssessmentCard extends StatelessWidget {
  const _AssessmentCard({required this.assessment, required this.onStart});

  final DemoAssessment assessment;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final sections = assessment.sections
        .map((section) => section.label)
        .join(', ');
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: assessment.remoteProctored
                  ? const Color(0xFFDBEAFE)
                  : const Color(0xFFEFF6FF),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              assessment.remoteProctored
                  ? Icons.verified_user_outlined
                  : Icons.assignment_outlined,
              color: const Color(0xFF1D4ED8),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  assessment.title,
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 4),
                Text(
                  '${assessment.course.code} - ${assessment.course.title}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _Tag(assessment.graded ? 'Graded' : 'Practice'),
                    _Tag(
                      assessment.remoteProctored
                          ? 'Face ID + proctoring'
                          : 'Normal',
                    ),
                    _Tag('${assessment.durationMinutes} min'),
                    _Tag(sections),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          FilledButton.icon(
            onPressed: onStart,
            icon: const Icon(Icons.play_arrow_rounded),
            label: const Text('Open'),
          ),
        ],
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(text, style: const TextStyle(fontWeight: FontWeight.w700)),
    );
  }
}

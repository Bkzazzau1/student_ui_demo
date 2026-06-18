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
      appBar: AppBar(
        title: const Text('K-SLAS Student Portal'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const DemoFaceIdView()),
            ),
            child: const Text('Face ID'),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const ProctoringDemoHome()),
              ),
              child: const Text('Security Centre'),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          const _Header(),
          const SizedBox(height: 14),
          const _Steps(),
          const SizedBox(height: 18),
          Text(
            'Available assessments',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 10),
          for (final assessment in assessments)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _AssessmentCard(
                assessment: assessment,
                onStart: () => _openSetup(context, assessment),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _openSetup(BuildContext context, DemoAssessment assessment) async {
    final result = await Navigator.of(context).push<DemoExamResult>(
      MaterialPageRoute<DemoExamResult>(
        builder: (_) => DemoExamSetupView(assessment: assessment),
      ),
    );
    if (result == null || !context.mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => DemoExamResultView(result: result)),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(20),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Secure assessment gateway',
            style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w900),
          ),
          SizedBox(height: 8),
          Text(
            'Complete identity check, room scan, security review, and guided submission.',
            style: TextStyle(color: Color(0xFFCBD5E1), fontSize: 16),
          ),
        ],
      ),
    );
  }
}

class _Steps extends StatelessWidget {
  const _Steps();

  @override
  Widget build(BuildContext context) {
    return const Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        Chip(label: Text('1 Identity check')),
        Chip(label: Text('2 360 room scan')),
        Chip(label: Text('3 Security review')),
        Chip(label: Text('4 Start')),
      ],
    );
  }
}

class _AssessmentCard extends StatelessWidget {
  const _AssessmentCard({required this.assessment, required this.onStart});

  final DemoAssessment assessment;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final sections = assessment.sections.map((section) => section.label).join(', ');
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const Icon(Icons.assignment_outlined),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(assessment.title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
                  const SizedBox(height: 4),
                  Text('${assessment.course.code} • ${assessment.course.title}'),
                  const SizedBox(height: 4),
                  Text('Lecturer: ${assessment.course.lecturer}'),
                  const SizedBox(height: 8),
                  Text('${assessment.kind} • ${assessment.durationMinutes} min • $sections'),
                ],
              ),
            ),
            FilledButton(onPressed: onStart, child: const Text('Open')),
          ],
        ),
      ),
    );
  }
}

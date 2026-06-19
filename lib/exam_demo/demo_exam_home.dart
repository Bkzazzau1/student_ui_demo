import 'package:flutter/material.dart';

import '../face_demo/demo_face_id_view.dart';
import '../proctoring_demo/proctoring_demo_home.dart';
import 'demo_exam_models.dart';
import 'demo_exam_result_view.dart';
import 'demo_exam_service.dart';
import 'secure_exam_setup_view.dart';

class DemoExamHome extends StatelessWidget {
  const DemoExamHome({super.key});

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final assessments = DemoExamService.assessmentsForDate(today);
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
                MaterialPageRoute<void>(
                  builder: (_) => const ProctoringDemoHome(),
                ),
              ),
              child: const Text('Security Centre'),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          _Header(today: today),
          const SizedBox(height: 14),
          const _Steps(),
          const SizedBox(height: 18),
          Text(
            'Courses to write today',
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 10),
          if (assessments.isEmpty)
            const _EmptySchedule()
          else
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

  Future<void> _openSetup(
    BuildContext context,
    DemoAssessment assessment,
  ) async {
    final result = await Navigator.of(context).push<DemoExamResult>(
      MaterialPageRoute<DemoExamResult>(
        builder: (_) => SecureExamSetupView(assessment: assessment),
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

class _Header extends StatelessWidget {
  const _Header({required this.today});

  final DateTime today;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Secure assessment gateway',
            style: TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Showing courses scheduled for ${_formatDate(today)}. Ungraded weekly practice is attendance-only and does not use proctoring.',
            style: const TextStyle(color: Color(0xFFCBD5E1), fontSize: 16),
          ),
        ],
      ),
    );
  }

  static String _formatDate(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
}

class _Steps extends StatelessWidget {
  const _Steps();

  @override
  Widget build(BuildContext context) {
    return const Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        Chip(label: Text('Exam: strict proctoring')),
        Chip(label: Text('Graded: lecturer review')),
        Chip(label: Text('Practice: attendance only')),
        Chip(label: Text('Listed by date')),
      ],
    );
  }
}

class _EmptySchedule extends StatelessWidget {
  const _EmptySchedule();

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            const Icon(Icons.event_available_outlined),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'No exam, graded assessment, or weekly attendance practice is scheduled for today.',
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            ),
          ],
        ),
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
    final reviewRoute = assessment.attendanceOnly
        ? 'Attendance only'
        : assessment.sendsEventsToLecturer
        ? 'Events to lecturer'
        : 'Events to invigilator';
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
                  Text(
                    assessment.title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 18,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${assessment.course.code} • ${assessment.course.title}',
                  ),
                  const SizedBox(height: 4),
                  Text('Lecturer: ${assessment.course.lecturer}'),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      Chip(label: Text(assessment.policy.label)),
                      Chip(label: Text(reviewRoute)),
                      Chip(label: Text('${assessment.durationMinutes} min')),
                      Chip(label: Text(assessment.scheduleLabel())),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(sections),
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

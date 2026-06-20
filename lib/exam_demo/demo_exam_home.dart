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
    final exams = assessments.where((item) => item.isStrictExam).toList();
    final graded = assessments.where((item) => item.isGradedAssessment).toList();
    final ungraded = assessments
        .where((item) => item.isUngradedAssessment)
        .toList();
    final practice = assessments.where((item) => item.attendanceOnly).toList();

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
              child: const Text('Exam Check'),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          _Header(today: today),
          const SizedBox(height: 14),
          _SummaryCards(
            exams: exams.length,
            graded: graded.length,
            ungraded: ungraded.length,
            practice: practice.length,
          ),
          const SizedBox(height: 14),
          const _Steps(),
          const SizedBox(height: 22),
          if (assessments.isEmpty)
            const _EmptySchedule()
          else ...[
            if (exams.isNotEmpty) ...[
              _AssessmentSection(
                title: 'Exams today',
                subtitle: 'Supervised exams require checks before you start.',
                icon: Icons.verified_user_outlined,
                assessments: exams,
                onStart: (assessment) => _openSetup(context, assessment),
              ),
              const SizedBox(height: 18),
            ],
            if (graded.isNotEmpty) ...[
              _AssessmentSection(
                title: 'Graded assessments',
                subtitle: 'Lecturer-marked quizzes, tests, and continuous assessment.',
                icon: Icons.assignment_turned_in_outlined,
                assessments: graded,
                onStart: (assessment) => _openSetup(context, assessment),
              ),
              const SizedBox(height: 18),
            ],
            if (ungraded.isNotEmpty) ...[
              _AssessmentSection(
                title: 'Ungraded assessments',
                subtitle: 'Self-check activities for feedback and readiness.',
                icon: Icons.lightbulb_outline,
                assessments: ungraded,
                onStart: (assessment) => _openSetup(context, assessment),
              ),
              const SizedBox(height: 18),
            ],
            if (practice.isNotEmpty)
              _AssessmentSection(
                title: 'Practice questions',
                subtitle: 'Weekly learning practice and attendance activities.',
                icon: Icons.menu_book_outlined,
                assessments: practice,
                onStart: (assessment) => _openSetup(context, assessment),
              ),
          ],
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
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: const Color(0x1AFFFFFF),
              borderRadius: BorderRadius.circular(999),
            ),
            child: const Text(
              'Assessment Hub',
              style: TextStyle(
                color: Color(0xFFBFDBFE),
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            'Student assessment centre',
            style: TextStyle(
              color: Colors.white,
              fontSize: 30,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Your exams, graded assessments, self-checks, and practice questions for ${_formatDate(today)}.',
            style: const TextStyle(color: Color(0xFFCBD5E1), fontSize: 16),
          ),
          const SizedBox(height: 6),
          const Text(
            'Complete the required checks before starting a supervised exam.',
            style: TextStyle(color: Color(0xFF94A3B8), fontSize: 14),
          ),
        ],
      ),
    );
  }

  static String _formatDate(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
}

class _SummaryCards extends StatelessWidget {
  const _SummaryCards({
    required this.exams,
    required this.graded,
    required this.ungraded,
    required this.practice,
  });

  final int exams;
  final int graded;
  final int ungraded;
  final int practice;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final cardWidth = width >= 980
            ? (width - 36) / 4
            : width >= 560
                ? (width - 12) / 2
                : width;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _SummaryCard(
              width: cardWidth,
              icon: Icons.verified_user_outlined,
              value: '$exams',
              title: 'Exams',
              subtitle: 'Start checks first',
            ),
            _SummaryCard(
              width: cardWidth,
              icon: Icons.assignment_turned_in_outlined,
              value: '$graded',
              title: 'Graded',
              subtitle: 'Lecturer-marked',
            ),
            _SummaryCard(
              width: cardWidth,
              icon: Icons.lightbulb_outline,
              value: '$ungraded',
              title: 'Ungraded',
              subtitle: 'Feedback only',
            ),
            _SummaryCard(
              width: cardWidth,
              icon: Icons.menu_book_outlined,
              value: '$practice',
              title: 'Practice',
              subtitle: 'Learning activities',
            ),
          ],
        );
      },
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.width,
    required this.icon,
    required this.value,
    required this.title,
    required this.subtitle,
  });

  final double width;
  final IconData icon;
  final String value;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Card(
        elevation: 0,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: const Color(0xFF2563EB)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      value,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                    ),
                    Text(
                      title,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Color(0xFF64748B)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
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
        Chip(label: Text('Supervised exams')),
        Chip(label: Text('Graded assessments')),
        Chip(label: Text('Ungraded assessments')),
        Chip(label: Text('Practice questions')),
        Chip(label: Text('Shown by date')),
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
                'No exam, assessment, or practice activity is scheduled for today.',
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AssessmentSection extends StatelessWidget {
  const _AssessmentSection({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.assessments,
    required this.onStart,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final List<DemoAssessment> assessments;
  final ValueChanged<DemoAssessment> onStart;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: const Color(0xFFEFF6FF),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: const Color(0xFF2563EB)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                  Text(
                    subtitle,
                    style: const TextStyle(color: Color(0xFF64748B)),
                  ),
                ],
              ),
            ),
            Chip(label: Text('${assessments.length}')),
          ],
        ),
        const SizedBox(height: 10),
        for (final assessment in assessments)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _AssessmentCard(
              assessment: assessment,
              onStart: () => onStart(assessment),
            ),
          ),
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
    final sections = assessment.sections
        .map((section) => section.label)
        .join(', ');
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 700;
            final details = Column(
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
                Text('${assessment.course.code} • ${assessment.course.title}'),
                const SizedBox(height: 4),
                Text('Lecturer: ${assessment.course.lecturer}'),
                const SizedBox(height: 6),
                Text(
                  _descriptionFor(assessment),
                  style: const TextStyle(color: Color(0xFF64748B)),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    Chip(label: Text(_typeLabelFor(assessment))),
                    Chip(label: Text(_reviewLabelFor(assessment))),
                    Chip(label: Text('${assessment.durationMinutes} min')),
                    Chip(label: Text(assessment.scheduleLabel())),
                  ],
                ),
                const SizedBox(height: 6),
                Text(sections),
              ],
            );

            final icon = Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: const Color(0xFFEFF6FF),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(
                _iconFor(assessment),
                color: const Color(0xFF2563EB),
              ),
            );

            final action = FilledButton(
              onPressed: onStart,
              child: Text(_buttonLabelFor(assessment)),
            );

            if (compact) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [icon, const SizedBox(width: 12), Expanded(child: details)]),
                  const SizedBox(height: 12),
                  SizedBox(width: double.infinity, child: action),
                ],
              );
            }

            return Row(
              children: [
                icon,
                const SizedBox(width: 14),
                Expanded(child: details),
                const SizedBox(width: 16),
                action,
              ],
            );
          },
        ),
      ),
    );
  }

  static IconData _iconFor(DemoAssessment assessment) {
    if (assessment.isStrictExam) return Icons.verified_user_outlined;
    if (assessment.isGradedAssessment) {
      return Icons.assignment_turned_in_outlined;
    }
    if (assessment.isUngradedAssessment) return Icons.lightbulb_outline;
    return Icons.menu_book_outlined;
  }

  static String _typeLabelFor(DemoAssessment assessment) {
    if (assessment.isStrictExam) return 'Supervised exam';
    if (assessment.isGradedAssessment) return 'Graded assessment';
    if (assessment.isUngradedAssessment) return 'Ungraded assessment';
    return 'Practice questions';
  }

  static String _reviewLabelFor(DemoAssessment assessment) {
    if (assessment.attendanceOnly) return 'Attendance only';
    if (assessment.isUngradedAssessment) return 'Feedback only';
    if (assessment.sendsEventsToLecturer) return 'Lecturer-marked';
    return 'Exam officer review';
  }

  static String _descriptionFor(DemoAssessment assessment) {
    if (assessment.isStrictExam) {
      return 'Camera, microphone, and system checks are required before starting.';
    }
    if (assessment.isGradedAssessment) {
      return 'Your submission is recorded for lecturer marking.';
    }
    if (assessment.isUngradedAssessment) {
      return 'This helps you check readiness before a graded activity.';
    }
    return 'Practice activity for learning support and attendance.';
  }

  static String _buttonLabelFor(DemoAssessment assessment) {
    if (assessment.isStrictExam || assessment.remoteProctored) return 'Start checks';
    if (assessment.isGradedAssessment) return 'Open assessment';
    if (assessment.isUngradedAssessment) return 'Start self-check';
    return 'Practice now';
  }
}

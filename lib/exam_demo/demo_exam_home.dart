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
        leading: const Icon(Icons.school_outlined),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: TextButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const DemoFaceIdView()),
              ),
              icon: const Icon(Icons.face_retouching_natural),
              label: const Text('Face ID'),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const ProctoringDemoHome(),
                ),
              ),
              icon: const Icon(Icons.security_outlined),
              label: const Text('Security Centre'),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1280),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
              children: [
                _CommandHero(assessments: assessments),
                const SizedBox(height: 16),
                const _AgentWorkflowCard(),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Available assessments',
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w900),
                      ),
                    ),
                    const _LiveBadge(),
                  ],
                ),
                const SizedBox(height: 10),
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

class _CommandHero extends StatelessWidget {
  const _CommandHero({required this.assessments});

  final List<DemoAssessment> assessments;

  @override
  Widget build(BuildContext context) {
    final graded = assessments.where((item) => item.graded).length;
    final remote = assessments.where((item) => item.remoteProctored).length;
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1A0F172A),
            blurRadius: 24,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 860;
          final summary = _SummaryGrid(
            metrics: [
              ('${assessments.length}', 'Open exams'),
              ('$graded', 'Graded'),
              ('$remote', 'Remote proctored'),
              ('Live', 'Backend mode'),
            ],
          );
          final intro = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _HeroBadge(),
              const SizedBox(height: 14),
              Text(
                'Secure assessment gateway for K-SLAS students',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.8,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'A clean student journey for examination access, Face ID enrolment, pre-exam room scan, evidence manifest creation, and backend AI review before the exam starts.',
                style: TextStyle(
                  color: Color(0xFFCBD5E1),
                  fontSize: 15.5,
                  height: 1.45,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 18),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: const [
                  _DarkPill('Identity Agent'),
                  _DarkPill('Environment Agent'),
                  _DarkPill('Risk Agent'),
                  _DarkPill('Evidence Agent'),
                ],
              ),
            ],
          );
          if (!wide) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [intro, const SizedBox(height: 20), summary],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 6, child: intro),
              const SizedBox(width: 24),
              Expanded(flex: 5, child: summary),
            ],
          );
        },
      ),
    );
  }
}

class _HeroBadge extends StatelessWidget {
  const _HeroBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
      ),
      child: const Text(
        'Presentation build • Real backend-ready flow',
        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
      ),
    );
  }
}

class _SummaryGrid extends StatelessWidget {
  const _SummaryGrid({required this.metrics});

  final List<(String, String)> metrics;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: metrics
          .map((metric) => _MetricTile(value: metric.$1, label: metric.$2))
          .toList(),
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 160,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 30,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(color: Color(0xFFCBD5E1))),
        ],
      ),
    );
  }
}

class _AgentWorkflowCard extends StatelessWidget {
  const _AgentWorkflowCard();

  @override
  Widget build(BuildContext context) {
    return _SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.hub_outlined, color: Color(0xFF0F4C81)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Agentic AI review pipeline',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: const [
              _WorkflowStep('1', 'Identity', 'Face ID and student attempt check'),
              _WorkflowStep('2', 'Environment', 'Camera scan and room evidence'),
              _WorkflowStep('3', 'Backend', 'Manifest and images sent for staging review'),
              _WorkflowStep('4', 'Decision', 'Approved, rescan, or invigilator review'),
            ],
          ),
        ],
      ),
    );
  }
}

class _WorkflowStep extends StatelessWidget {
  const _WorkflowStep(this.number, this.title, this.detail);

  final String number;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 280,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 17,
            backgroundColor: const Color(0xFF0F4C81),
            child: Text(
              number,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
                const SizedBox(height: 3),
                Text(
                  detail,
                  style: const TextStyle(color: Color(0xFF64748B), height: 1.35),
                ),
              ],
            ),
          ),
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
    final sections = assessment.sections.map((section) => section.label).join(', ');
    return _SurfaceCard(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 760;
          final leading = _AssessmentIcon(remote: assessment.remoteProctored);
          final details = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                assessment.title,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.2,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                '${assessment.course.code} • ${assessment.course.title}',
                style: const TextStyle(
                  color: Color(0xFF334155),
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Lecturer: ${assessment.course.lecturer}',
                style: const TextStyle(color: Color(0xFF64748B)),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _Tag(assessment.kind),
                  _Tag(assessment.graded ? 'Graded' : 'Practice'),
                  _Tag(
                    assessment.remoteProctored
                        ? 'Face ID + proctoring'
                        : 'Standard access',
                  ),
                  _Tag('${assessment.durationMinutes} min'),
                  _Tag(sections),
                ],
              ),
            ],
          );
          final action = FilledButton.icon(
            onPressed: onStart,
            icon: const Icon(Icons.play_arrow_rounded),
            label: const Text('Open assessment'),
          );
          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [leading, const SizedBox(width: 12), Expanded(child: details)]),
                const SizedBox(height: 14),
                SizedBox(width: double.infinity, child: action),
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              leading,
              const SizedBox(width: 16),
              Expanded(child: details),
              const SizedBox(width: 14),
              action,
            ],
          );
        },
      ),
    );
  }
}

class _AssessmentIcon extends StatelessWidget {
  const _AssessmentIcon({required this.remote});

  final bool remote;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        color: remote ? const Color(0xFFEFF6FF) : const Color(0xFFF0FDF4),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Icon(
        remote ? Icons.verified_user_outlined : Icons.assignment_outlined,
        color: remote ? const Color(0xFF0F4C81) : const Color(0xFF16A34A),
      ),
    );
  }
}

class _SurfaceCard extends StatelessWidget {
  const _SurfaceCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0F0F172A),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Color(0xFF334155),
          fontWeight: FontWeight.w800,
          fontSize: 12,
        ),
      ),
    );
  }
}

class _DarkPill extends StatelessWidget {
  const _DarkPill(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
      ),
      child: Text(
        text,
        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
      ),
    );
  }
}

class _LiveBadge extends StatelessWidget {
  const _LiveBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFDCFCE7),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFBBF7D0)),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.circle, size: 9, color: Color(0xFF16A34A)),
          SizedBox(width: 7),
          Text(
            'Backend staging ready',
            style: TextStyle(
              color: Color(0xFF166534),
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

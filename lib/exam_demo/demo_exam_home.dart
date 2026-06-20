import 'package:flutter/material.dart';

import '../face_demo/demo_face_id_view.dart';
import '../proctoring_demo/proctoring_demo_home.dart';
import 'demo_exam_models.dart';
import 'demo_exam_result_view.dart';
import 'demo_exam_service.dart';
import 'secure_exam_setup_view.dart';

enum _AssessmentFilter { all, exams, graded, ungraded, practice }

extension _AssessmentFilterX on _AssessmentFilter {
  String get label {
    switch (this) {
      case _AssessmentFilter.all:
        return 'All';
      case _AssessmentFilter.exams:
        return 'Exams';
      case _AssessmentFilter.graded:
        return 'Graded';
      case _AssessmentFilter.ungraded:
        return 'Ungraded';
      case _AssessmentFilter.practice:
        return 'Practice';
    }
  }
}

class DemoExamHome extends StatefulWidget {
  const DemoExamHome({super.key});

  @override
  State<DemoExamHome> createState() => _DemoExamHomeState();
}

class _DemoExamHomeState extends State<DemoExamHome> {
  _AssessmentFilter _filter = _AssessmentFilter.all;

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

    final sections = <_AssessmentSectionData>[
      _AssessmentSectionData(
        filter: _AssessmentFilter.exams,
        title: 'Exams today',
        subtitle: 'Supervised exams require checks before you start.',
        icon: Icons.verified_user_outlined,
        assessments: exams,
      ),
      _AssessmentSectionData(
        filter: _AssessmentFilter.graded,
        title: 'Graded assessments',
        subtitle: 'Lecturer-marked quizzes, tests, and continuous assessment.',
        icon: Icons.assignment_turned_in_outlined,
        assessments: graded,
      ),
      _AssessmentSectionData(
        filter: _AssessmentFilter.ungraded,
        title: 'Ungraded assessments',
        subtitle: 'Self-check activities for feedback and readiness.',
        icon: Icons.lightbulb_outline,
        assessments: ungraded,
      ),
      _AssessmentSectionData(
        filter: _AssessmentFilter.practice,
        title: 'Practice questions',
        subtitle: 'Weekly learning practice and attendance activities.',
        icon: Icons.menu_book_outlined,
        assessments: practice,
      ),
    ];

    final visibleSections = sections
        .where(
          (section) =>
              section.assessments.isNotEmpty &&
              (_filter == _AssessmentFilter.all || section.filter == _filter),
        )
        .toList();

    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FB),
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        titleSpacing: 20,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: const Color(0xFFEFF6FF),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.school_outlined,
                color: Color(0xFF2563EB),
                size: 20,
              ),
            ),
            const SizedBox(width: 10),
            const Text(
              'K-SLAS Student Portal',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
          ],
        ),
        actions: [
          TextButton.icon(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const DemoFaceIdView()),
            ),
            icon: const Icon(Icons.face_retouching_natural_outlined),
            label: const Text('Face ID'),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 14, left: 6),
            child: FilledButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const ProctoringDemoHome(),
                ),
              ),
              icon: const Icon(Icons.health_and_safety_outlined, size: 18),
              label: const Text('Exam Check'),
            ),
          ),
        ],
      ),
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFF8FAFC), Color(0xFFF1F5F9)],
          ),
        ),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1220),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _Header(
                      today: today,
                      total: assessments.length,
                      supervised: exams.length,
                    ),
                    const SizedBox(height: 14),
                    _SummaryCards(
                      exams: exams.length,
                      graded: graded.length,
                      ungraded: ungraded.length,
                      practice: practice.length,
                      selected: _filter,
                      onSelected: (filter) => setState(() => _filter = filter),
                    ),
                    const SizedBox(height: 14),
                    _FilterChips(
                      selected: _filter,
                      onChanged: (filter) => setState(() => _filter = filter),
                    ),
                    const SizedBox(height: 22),
                    if (assessments.isEmpty)
                      const _EmptySchedule()
                    else if (visibleSections.isEmpty)
                      _NoFilteredSchedule(filter: _filter)
                    else
                      _ResponsiveSectionLayout(
                        sections: visibleSections,
                        onStart: (assessment) => _openSetup(context, assessment),
                      ),
                  ],
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

class _AssessmentSectionData {
  const _AssessmentSectionData({
    required this.filter,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.assessments,
  });

  final _AssessmentFilter filter;
  final String title;
  final String subtitle;
  final IconData icon;
  final List<DemoAssessment> assessments;
}

class _Header extends StatelessWidget {
  const _Header({
    required this.today,
    required this.total,
    required this.supervised,
  });

  final DateTime today;
  final int total;
  final int supervised;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(28),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1A0F172A),
            blurRadius: 24,
            offset: Offset(0, 14),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 820;
          final content = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _HeroBadge(
                    icon: Icons.calendar_today_outlined,
                    label: _formatDate(today),
                  ),
                  const _HeroBadge(
                    icon: Icons.verified_outlined,
                    label: 'Calm exam monitoring',
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Text(
                'Student assessment centre',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 32,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.4,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Your exams, graded assessments, self-checks, and practice questions are organised in one place.',
                style: TextStyle(color: Color(0xFFCBD5E1), fontSize: 16),
              ),
              const SizedBox(height: 6),
              const Text(
                'Complete the required checks before starting a supervised exam.',
                style: TextStyle(color: Color(0xFF94A3B8), fontSize: 14),
              ),
            ],
          );

          final stats = Wrap(
            spacing: 10,
            runSpacing: 10,
            alignment: wide ? WrapAlignment.end : WrapAlignment.start,
            children: [
              _HeroStat(value: '$total', label: 'Today'),
              _HeroStat(value: '$supervised', label: 'Need checks'),
            ],
          );

          if (!wide) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [content, const SizedBox(height: 18), stats],
            );
          }

          return Row(
            children: [
              Expanded(child: content),
              const SizedBox(width: 24),
              stats,
            ],
          );
        },
      ),
    );
  }

  static String _formatDate(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
}

class _HeroBadge extends StatelessWidget {
  const _HeroBadge({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0x1AFFFFFF),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0x1FFFFFFF)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: const Color(0xFFBFDBFE), size: 16),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFFDBEAFE),
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroStat extends StatelessWidget {
  const _HeroStat({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 118,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0x12FFFFFF),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0x24FFFFFF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFFCBD5E1),
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryCards extends StatelessWidget {
  const _SummaryCards({
    required this.exams,
    required this.graded,
    required this.ungraded,
    required this.practice,
    required this.selected,
    required this.onSelected,
  });

  final int exams;
  final int graded;
  final int ungraded;
  final int practice;
  final _AssessmentFilter selected;
  final ValueChanged<_AssessmentFilter> onSelected;

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
              selected: selected == _AssessmentFilter.exams,
              onTap: () => onSelected(_AssessmentFilter.exams),
            ),
            _SummaryCard(
              width: cardWidth,
              icon: Icons.assignment_turned_in_outlined,
              value: '$graded',
              title: 'Graded',
              subtitle: 'Lecturer-marked',
              selected: selected == _AssessmentFilter.graded,
              onTap: () => onSelected(_AssessmentFilter.graded),
            ),
            _SummaryCard(
              width: cardWidth,
              icon: Icons.lightbulb_outline,
              value: '$ungraded',
              title: 'Ungraded',
              subtitle: 'Feedback only',
              selected: selected == _AssessmentFilter.ungraded,
              onTap: () => onSelected(_AssessmentFilter.ungraded),
            ),
            _SummaryCard(
              width: cardWidth,
              icon: Icons.menu_book_outlined,
              value: '$practice',
              title: 'Practice',
              subtitle: 'Learning activities',
              selected: selected == _AssessmentFilter.practice,
              onTap: () => onSelected(_AssessmentFilter.practice),
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
    required this.selected,
    required this.onTap,
  });

  final double width;
  final IconData icon;
  final String value;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: selected
                    ? const Color(0xFF2563EB)
                    : const Color(0xFFE2E8F0),
                width: selected ? 1.4 : 1,
              ),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x080F172A),
                  blurRadius: 18,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: selected
                        ? const Color(0xFFDBEAFE)
                        : const Color(0xFFEFF6FF),
                    borderRadius: BorderRadius.circular(16),
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
                if (selected)
                  const Icon(
                    Icons.check_circle,
                    color: Color(0xFF2563EB),
                    size: 20,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FilterChips extends StatelessWidget {
  const _FilterChips({required this.selected, required this.onChanged});

  final _AssessmentFilter selected;
  final ValueChanged<_AssessmentFilter> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final filter in _AssessmentFilter.values)
            ChoiceChip(
              label: Text(filter.label),
              selected: selected == filter,
              onSelected: (_) => onChanged(filter),
              selectedColor: const Color(0xFFDBEAFE),
              labelStyle: TextStyle(
                color: selected == filter
                    ? const Color(0xFF1D4ED8)
                    : const Color(0xFF334155),
                fontWeight: FontWeight.w800,
              ),
              side: BorderSide(
                color: selected == filter
                    ? const Color(0xFF93C5FD)
                    : const Color(0xFFE2E8F0),
              ),
            ),
        ],
      ),
    );
  }
}

class _EmptySchedule extends StatelessWidget {
  const _EmptySchedule();

  @override
  Widget build(BuildContext context) {
    return _InfoStateCard(
      icon: Icons.event_available_outlined,
      title: 'Nothing scheduled today',
      message: 'No exam, assessment, or practice activity is scheduled for today.',
    );
  }
}

class _NoFilteredSchedule extends StatelessWidget {
  const _NoFilteredSchedule({required this.filter});

  final _AssessmentFilter filter;

  @override
  Widget build(BuildContext context) {
    return _InfoStateCard(
      icon: Icons.filter_alt_off_outlined,
      title: 'No ${filter.label.toLowerCase()} item',
      message: 'Choose All to see every activity scheduled for today.',
    );
  }
}

class _InfoStateCard extends StatelessWidget {
  const _InfoStateCard({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: const Color(0xFFEFF6FF),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(icon, color: const Color(0xFF2563EB)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  message,
                  style: const TextStyle(color: Color(0xFF64748B)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ResponsiveSectionLayout extends StatelessWidget {
  const _ResponsiveSectionLayout({required this.sections, required this.onStart});

  final List<_AssessmentSectionData> sections;
  final ValueChanged<DemoAssessment> onStart;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final twoColumns = constraints.maxWidth >= 980 && sections.length > 1;
        final itemWidth = twoColumns
            ? (constraints.maxWidth - 16) / 2
            : constraints.maxWidth;
        return Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            for (final section in sections)
              SizedBox(
                width: itemWidth,
                child: _AssessmentSection(
                  title: section.title,
                  subtitle: section.subtitle,
                  icon: section.icon,
                  assessments: section.assessments,
                  onStart: onStart,
                ),
              ),
          ],
        );
      },
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
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xB3FFFFFF),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
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
                child: Icon(icon, color: const Color(0xFF2563EB)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.2,
                          ),
                    ),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Color(0xFF64748B)),
                    ),
                  ],
                ),
              ),
              _CountPill(count: assessments.length),
            ],
          ),
          const SizedBox(height: 14),
          for (final assessment in assessments)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _AssessmentCard(
                assessment: assessment,
                onStart: () => onStart(assessment),
              ),
            ),
        ],
      ),
    );
  }
}

class _CountPill extends StatelessWidget {
  const _CountPill({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Text(
        '$count',
        style: const TextStyle(fontWeight: FontWeight.w900),
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
    final accent = _accentFor(assessment);
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x080F172A),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            child: Container(width: 5, color: accent),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 16, 16),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 560;
                final details = _AssessmentDetails(
                  assessment: assessment,
                  sections: sections,
                );
                final icon = _AssessmentIcon(assessment: assessment);
                final action = FilledButton.icon(
                  onPressed: onStart,
                  icon: Icon(_buttonIconFor(assessment), size: 18),
                  label: Text(_buttonLabelFor(assessment)),
                );

                if (compact) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          icon,
                          const SizedBox(width: 12),
                          Expanded(child: details),
                        ],
                      ),
                      const SizedBox(height: 14),
                      SizedBox(width: double.infinity, child: action),
                    ],
                  );
                }

                return Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    icon,
                    const SizedBox(width: 14),
                    Expanded(child: details),
                    const SizedBox(width: 14),
                    action,
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  static Color _accentFor(DemoAssessment assessment) {
    if (assessment.isStrictExam) return const Color(0xFF2563EB);
    if (assessment.isGradedAssessment) return const Color(0xFF16A34A);
    if (assessment.isUngradedAssessment) return const Color(0xFFF59E0B);
    return const Color(0xFF7C3AED);
  }

  static IconData _buttonIconFor(DemoAssessment assessment) {
    if (assessment.isStrictExam || assessment.remoteProctored) {
      return Icons.shield_outlined;
    }
    if (assessment.isGradedAssessment) return Icons.open_in_new_rounded;
    if (assessment.isUngradedAssessment) return Icons.play_circle_outline;
    return Icons.arrow_forward_rounded;
  }

  static String _buttonLabelFor(DemoAssessment assessment) {
    if (assessment.isStrictExam || assessment.remoteProctored) return 'Start checks';
    if (assessment.isGradedAssessment) return 'Open assessment';
    if (assessment.isUngradedAssessment) return 'Start self-check';
    return 'Practice now';
  }
}

class _AssessmentIcon extends StatelessWidget {
  const _AssessmentIcon({required this.assessment});

  final DemoAssessment assessment;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 46,
      height: 46,
      decoration: BoxDecoration(
        color: _softFor(assessment),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Icon(_iconFor(assessment), color: _accentFor(assessment)),
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

  static Color _accentFor(DemoAssessment assessment) {
    if (assessment.isStrictExam) return const Color(0xFF2563EB);
    if (assessment.isGradedAssessment) return const Color(0xFF16A34A);
    if (assessment.isUngradedAssessment) return const Color(0xFFF59E0B);
    return const Color(0xFF7C3AED);
  }

  static Color _softFor(DemoAssessment assessment) {
    if (assessment.isStrictExam) return const Color(0xFFEFF6FF);
    if (assessment.isGradedAssessment) return const Color(0xFFF0FDF4);
    if (assessment.isUngradedAssessment) return const Color(0xFFFFFBEB);
    return const Color(0xFFF5F3FF);
  }
}

class _AssessmentDetails extends StatelessWidget {
  const _AssessmentDetails({required this.assessment, required this.sections});

  final DemoAssessment assessment;
  final String sections;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          assessment.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: 17,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          '${assessment.course.code} - ${assessment.course.title}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Color(0xFF334155),
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Lecturer: ${assessment.course.lecturer}',
          style: const TextStyle(color: Color(0xFF475569)),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _StatusPill(label: _typeLabelFor(assessment)),
            _InfoPill(
              icon: Icons.route_outlined,
              label: _reviewLabelFor(assessment),
            ),
            _InfoPill(
              icon: Icons.schedule_outlined,
              label: '${assessment.durationMinutes} min',
            ),
            _InfoPill(
              icon: Icons.today_outlined,
              label: assessment.scheduleLabel(),
            ),
            _InfoPill(icon: Icons.list_alt_outlined, label: sections),
          ],
        ),
      ],
    );
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
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Color(0xFF334155),
          fontSize: 12,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _InfoPill extends StatelessWidget {
  const _InfoPill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: const Color(0xFF64748B)),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF475569),
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

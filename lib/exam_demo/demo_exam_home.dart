import 'package:flutter/material.dart';

import '../auth/student_logout_view.dart';
import '../face_demo/demo_face_id_view.dart';
import '../proctoring_demo/proctoring_demo_home.dart';
import 'assignment_submission_view.dart';
import 'demo_exam_models.dart';
import 'demo_exam_result_view.dart';
import 'demo_exam_service.dart';
import 'feedback_detail_view.dart';
import 'grade_book_view.dart';
import 'secure_exam_setup_view.dart';
import 'student_assessment_hub_extras.dart';

const Color _brand = Color(0xFF0F4C81);
const Color _brandDark = Color(0xFF0B1220);
const Color _brandSoft = Color(0xFFEFF6FF);
const Color _pageBg = Color(0xFFF4F7FB);
const Color _surface = Color(0xFFFFFFFF);
const Color _surfaceSoft = Color(0xFFF8FAFC);
const Color _line = Color(0xFFE2E8F0);
const Color _muted = Color(0xFF64748B);
const Color _success = Color(0xFF16A34A);
const Color _warning = Color(0xFFF59E0B);
const Color _purple = Color(0xFF7C3AED);

enum _DashboardTab { today, exams, assessments, practice, updates }

extension _DashboardTabX on _DashboardTab {
  String get label {
    switch (this) {
      case _DashboardTab.today:
        return 'Today';
      case _DashboardTab.exams:
        return 'Exams';
      case _DashboardTab.assessments:
        return 'Assessments';
      case _DashboardTab.practice:
        return 'Practice';
      case _DashboardTab.updates:
        return 'Updates';
    }
  }
}

class DemoExamHome extends StatefulWidget {
  const DemoExamHome({super.key});

  @override
  State<DemoExamHome> createState() => _DemoExamHomeState();
}

class _DemoExamHomeState extends State<DemoExamHome> {
  _DashboardTab _selectedTab = _DashboardTab.today;

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final assessments = DemoExamService.assessmentsForDate(today);
    final assignments = DemoStudentHubExtras.assignmentsForDate(today);
    final feedbackItems = DemoStudentHubExtras.feedbackForDate(today);

    final exams = assessments.where((item) => item.isStrictExam).toList();
    final assessmentsOnly = assessments
        .where((item) => item.isGradedAssessment || item.isUngradedAssessment)
        .toList();
    final practice = assessments.where((item) => item.attendanceOnly).toList();
    final nextAssessment = _nextAssessment(exams, assessmentsOnly, practice);

    return Scaffold(
      backgroundColor: _pageBg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        titleSpacing: 20,
        title: const _AppTitle(),
        actions: [
          const _StudentPill(),
          Padding(
            padding: const EdgeInsets.only(right: 12, left: 8),
            child: IconButton(
              tooltip: 'Sign out',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const StudentLogoutView(),
                ),
              ),
              icon: const Icon(Icons.logout_outlined),
            ),
          ),
        ],
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, color: _line),
        ),
      ),
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFF8FAFC), Color(0xFFEFF4FA)],
          ),
        ),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 96),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1100),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _WelcomeHeader(
                      today: today,
                      examCount: exams.length,
                      activityCount: assessments.length + assignments.length,
                    ),
                    const SizedBox(height: 16),
                    _QuickActions(
                      onGradeBook: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const GradeBookView(),
                        ),
                      ),
                      onIdentity: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const DemoFaceIdView(),
                        ),
                      ),
                      onExamCheck: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const ProctoringDemoHome(),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    if (nextAssessment != null)
                      _NextAssessmentCard(
                        assessment: nextAssessment,
                        onOpen: () => _openSetup(context, nextAssessment),
                      )
                    else
                      const _EmptyCard(
                        title: 'No assessment scheduled today',
                        message: 'Your assessments will appear here when available.',
                      ),
                    const SizedBox(height: 18),
                    _DashboardTabs(
                      selected: _selectedTab,
                      onChanged: (tab) => setState(() => _selectedTab = tab),
                    ),
                    const SizedBox(height: 16),
                    _buildSelectedContent(
                      context: context,
                      assessments: assessments,
                      exams: exams,
                      assessmentsOnly: assessmentsOnly,
                      practice: practice,
                      assignments: assignments,
                      feedbackItems: feedbackItems,
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

  Widget _buildSelectedContent({
    required BuildContext context,
    required List<DemoAssessment> assessments,
    required List<DemoAssessment> exams,
    required List<DemoAssessment> assessmentsOnly,
    required List<DemoAssessment> practice,
    required List<DemoAssignmentItem> assignments,
    required List<DemoFeedbackItem> feedbackItems,
  }) {
    switch (_selectedTab) {
      case _DashboardTab.today:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _AssessmentList(
              title: 'Today\'s activities',
              emptyTitle: 'Nothing scheduled today',
              emptyMessage: 'No exam, assessment, or practice activity is scheduled for today.',
              assessments: assessments,
              onOpen: (assessment) => _openSetup(context, assessment),
            ),
            const SizedBox(height: 16),
            _LearningUpdates(
              assignments: assignments,
              feedbackItems: feedbackItems,
              onOpenAssignment: (assignment) => _openAssignment(context, assignment),
              onOpenFeedback: (feedbackItem) => _openFeedback(context, feedbackItem),
            ),
          ],
        );
      case _DashboardTab.exams:
        return _AssessmentList(
          title: 'Exams',
          emptyTitle: 'No exam today',
          emptyMessage: 'Supervised exams will appear here when scheduled.',
          assessments: exams,
          onOpen: (assessment) => _openSetup(context, assessment),
        );
      case _DashboardTab.assessments:
        return _AssessmentList(
          title: 'Assessments',
          emptyTitle: 'No assessment today',
          emptyMessage: 'Quizzes, tests, and self-check activities will appear here.',
          assessments: assessmentsOnly,
          onOpen: (assessment) => _openSetup(context, assessment),
        );
      case _DashboardTab.practice:
        return _AssessmentList(
          title: 'Practice',
          emptyTitle: 'No practice activity today',
          emptyMessage: 'Weekly practice questions will appear here when available.',
          assessments: practice,
          onOpen: (assessment) => _openSetup(context, assessment),
        );
      case _DashboardTab.updates:
        return _UpdatesList(
          assignments: assignments,
          feedbackItems: feedbackItems,
          onOpenAssignment: (assignment) => _openAssignment(context, assignment),
          onOpenFeedback: (feedbackItem) => _openFeedback(context, feedbackItem),
        );
    }
  }

  static DemoAssessment? _nextAssessment(
    List<DemoAssessment> exams,
    List<DemoAssessment> assessments,
    List<DemoAssessment> practice,
  ) {
    if (exams.isNotEmpty) return exams.first;
    if (assessments.isNotEmpty) return assessments.first;
    if (practice.isNotEmpty) return practice.first;
    return null;
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

  Future<void> _openAssignment(
    BuildContext context,
    DemoAssignmentItem assignment,
  ) async {
    final result = await Navigator.of(context).push<AssignmentSubmissionResult>(
      MaterialPageRoute<AssignmentSubmissionResult>(
        builder: (_) => AssignmentSubmissionView(assignment: assignment),
      ),
    );
    if (result == null || !context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${result.assignment.course.code} assignment submitted.'),
      ),
    );
  }

  void _openFeedback(BuildContext context, DemoFeedbackItem feedbackItem) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => FeedbackDetailView(feedbackItem: feedbackItem),
      ),
    );
  }
}

class _AppTitle extends StatelessWidget {
  const _AppTitle();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 36,
          height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [_brand, Color(0xFF1D4ED8)],
            ),
            borderRadius: BorderRadius.circular(10),
            boxShadow: const [
              BoxShadow(
                color: Color(0x240F4C81),
                blurRadius: 12,
                offset: Offset(0, 6),
              ),
            ],
          ),
          child: const Text(
            'K',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        const SizedBox(width: 10),
        const Text(
          'K-SLAS Student Portal',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
      ],
    );
  }
}

class _StudentPill extends StatelessWidget {
  const _StudentPill();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(right: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: _surfaceSoft,
        border: Border.all(color: _line),
        borderRadius: BorderRadius.circular(999),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.person_outline, size: 16, color: _brand),
          SizedBox(width: 6),
          Text(
            'KSLAS/STD/2026/001',
            style: TextStyle(
              color: _brandDark,
              fontWeight: FontWeight.w800,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _WelcomeHeader extends StatelessWidget {
  const _WelcomeHeader({
    required this.today,
    required this.examCount,
    required this.activityCount,
  });

  final DateTime today;
  final int examCount;
  final int activityCount;

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: _surface,
        border: Border.all(color: _line),
        borderRadius: BorderRadius.circular(22),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0F0F172A),
            blurRadius: 22,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            height: 6,
            decoration: const BoxDecoration(
              gradient: LinearGradient(colors: [_brand, _success, _warning]),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(22),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= 760;
                final intro = Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Welcome back',
                      style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                            color: _brandDark,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.5,
                          ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _summaryText,
                      style: const TextStyle(
                        color: _muted,
                        fontSize: 16,
                        height: 1.45,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        _MetricPill(
                          value: '$examCount',
                          label: examCount == 1 ? 'exam' : 'exams',
                          color: _brand,
                        ),
                        _MetricPill(
                          value: '$activityCount',
                          label: activityCount == 1 ? 'activity' : 'activities',
                          color: _success,
                        ),
                      ],
                    ),
                  ],
                );

                final date = _DateBox(today: today);
                if (!wide) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [intro, const SizedBox(height: 18), date],
                  );
                }
                return Row(
                  children: [
                    Expanded(child: intro),
                    const SizedBox(width: 24),
                    date,
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  String get _summaryText {
    if (activityCount == 0) return 'You have no assessment activity scheduled today.';
    final examPart = examCount == 1 ? '1 exam' : '$examCount exams';
    final activityPart = activityCount == 1 ? '1 activity' : '$activityCount activities';
    if (examCount == 0) return 'You have $activityPart today.';
    return 'You have $examPart and $activityPart today.';
  }
}

class _MetricPill extends StatelessWidget {
  const _MetricPill({required this.value, required this.label, required this.color});

  final String value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        border: Border.all(color: color.withValues(alpha: 0.18)),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF334155),
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _DateBox extends StatelessWidget {
  const _DateBox({required this.today});

  final DateTime today;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        color: _surfaceSoft,
        border: Border.all(color: _line),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          const Text(
            'Today',
            style: TextStyle(
              color: _muted,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _formatDate(today),
            style: const TextStyle(
              color: _brandDark,
              fontWeight: FontWeight.w900,
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }

  static String _formatDate(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
}

class _QuickActions extends StatelessWidget {
  const _QuickActions({
    required this.onGradeBook,
    required this.onIdentity,
    required this.onExamCheck,
  });

  final VoidCallback onGradeBook;
  final VoidCallback onIdentity;
  final VoidCallback onExamCheck;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 720;
        final width = compact ? constraints.maxWidth : (constraints.maxWidth - 24) / 3;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            SizedBox(
              width: width,
              child: _QuickAction(
                title: 'Grade book',
                subtitle: 'View scores',
                icon: Icons.workspace_premium_outlined,
                color: _warning,
                onTap: onGradeBook,
              ),
            ),
            SizedBox(
              width: width,
              child: _QuickAction(
                title: 'Identity setup',
                subtitle: 'Prepare access',
                icon: Icons.account_circle_outlined,
                color: _purple,
                onTap: onIdentity,
              ),
            ),
            SizedBox(
              width: width,
              child: _QuickAction(
                title: 'Exam check',
                subtitle: 'Open readiness check',
                icon: Icons.verified_user_outlined,
                color: _success,
                onTap: onExamCheck,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _surface,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            border: Border.all(color: _line),
            borderRadius: BorderRadius.circular(18),
            boxShadow: const [
              BoxShadow(
                color: Color(0x080F172A),
                blurRadius: 16,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: color, size: 23),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: _brandDark,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _muted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Color(0xFF94A3B8)),
            ],
          ),
        ),
      ),
    );
  }
}

class _NextAssessmentCard extends StatelessWidget {
  const _NextAssessmentCard({required this.assessment, required this.onOpen});

  final DemoAssessment assessment;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final accent = _accentFor(assessment);
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [
          BoxShadow(
            color: Color(0x260F172A),
            blurRadius: 28,
            offset: Offset(0, 16),
          ),
        ],
      ),
      child: Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [_brandDark, const Color(0xFF113A63), accent.withValues(alpha: 0.78)],
          ),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 720;
            final details = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.12),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Text(
                    'Next assessment',
                    style: TextStyle(
                      color: Color(0xFFDBEAFE),
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  assessment.title,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.4,
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  '${assessment.course.code} • ${assessment.durationMinutes} min • ${assessment.scheduleLabel()}',
                  style: const TextStyle(
                    color: Color(0xFFE2E8F0),
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Lecturer: ${assessment.course.lecturer}',
                  style: const TextStyle(
                    color: Color(0xFFCBD5E1),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            );
            final button = FilledButton(
              onPressed: onOpen,
              style: FilledButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: _brandDark,
                minimumSize: const Size(170, 54),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                textStyle: const TextStyle(fontWeight: FontWeight.w900),
              ),
              child: Text(_buttonLabelFor(assessment)),
            );

            final focusBox = _NextFocusBox(assessment: assessment);
            if (compact) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [details, const SizedBox(height: 18), focusBox, const SizedBox(height: 18), button],
              );
            }
            return Row(
              children: [
                Expanded(child: details),
                const SizedBox(width: 22),
                SizedBox(width: 210, child: focusBox),
                const SizedBox(width: 18),
                button,
              ],
            );
          },
        ),
      ),
    );
  }
}

class _NextFocusBox extends StatelessWidget {
  const _NextFocusBox({required this.assessment});

  final DemoAssessment assessment;

  @override
  Widget build(BuildContext context) {
    final label = assessment.isStrictExam
        ? 'Checks required'
        : assessment.attendanceOnly
            ? 'Practice ready'
            : 'Ready to open';
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.11),
        border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(_iconFor(assessment), color: Colors.white, size: 26),
          const SizedBox(height: 10),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Follow the next step when you are ready.',
            style: TextStyle(
              color: Color(0xFFCBD5E1),
              height: 1.35,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _DashboardTabs extends StatelessWidget {
  const _DashboardTabs({required this.selected, required this.onChanged});

  final _DashboardTab selected;
  final ValueChanged<_DashboardTab> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: _surface,
        border: Border.all(color: _line),
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            color: Color(0x060F172A),
            blurRadius: 14,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final tab in _DashboardTab.values)
            _TabButton(
              label: tab.label,
              selected: selected == tab,
              onTap: () => onChanged(tab),
            ),
        ],
      ),
    );
  }
}

class _TabButton extends StatelessWidget {
  const _TabButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? _brand : Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? Colors.white : const Color(0xFF334155),
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ),
    );
  }
}

class _AssessmentList extends StatelessWidget {
  const _AssessmentList({
    required this.title,
    required this.emptyTitle,
    required this.emptyMessage,
    required this.assessments,
    required this.onOpen,
  });

  final String title;
  final String emptyTitle;
  final String emptyMessage;
  final List<DemoAssessment> assessments;
  final ValueChanged<DemoAssessment> onOpen;

  @override
  Widget build(BuildContext context) {
    if (assessments.isEmpty) {
      return _EmptyCard(title: emptyTitle, message: emptyMessage);
    }
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: _surface,
        border: Border.all(color: _line),
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(
            color: Color(0x080F172A),
            blurRadius: 18,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(height: 4, color: _brand),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 6),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: _brandDark,
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                ),
                _CountBadge(count: assessments.length),
              ],
            ),
          ),
          for (var index = 0; index < assessments.length; index++) ...[
            if (index > 0) const Divider(height: 1, color: _line),
            _AssessmentRow(
              assessment: assessments[index],
              onOpen: () => onOpen(assessments[index]),
            ),
          ],
        ],
      ),
    );
  }
}

class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: _brandSoft,
        border: Border.all(color: const Color(0xFFBFDBFE)),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '$count',
        style: const TextStyle(color: _brand, fontWeight: FontWeight.w900),
      ),
    );
  }
}

class _AssessmentRow extends StatelessWidget {
  const _AssessmentRow({required this.assessment, required this.onOpen});

  final DemoAssessment assessment;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final accent = _accentFor(assessment);
    return Container(
      decoration: BoxDecoration(color: _softAccentFor(assessment)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 680;
            final content = Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(width: 4, height: 54, color: accent),
                const SizedBox(width: 12),
                Container(
                  width: 44,
                  height: 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: accent.withValues(alpha: 0.16)),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(_iconFor(assessment), color: accent),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              assessment.title,
                              style: const TextStyle(
                                color: _brandDark,
                                fontWeight: FontWeight.w900,
                                fontSize: 16,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          _TypeBadge(assessment: assessment),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${assessment.course.code} • ${assessment.course.title}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF334155),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        '${assessment.durationMinutes} min • ${assessment.scheduleLabel()} • ${assessment.course.lecturer}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: _muted,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );

            final action = FilledButton(
              onPressed: onOpen,
              style: FilledButton.styleFrom(
                backgroundColor: accent,
                foregroundColor: Colors.white,
                minimumSize: const Size(140, 44),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                textStyle: const TextStyle(fontWeight: FontWeight.w900),
              ),
              child: Text(_buttonLabelFor(assessment)),
            );

            if (compact) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [content, const SizedBox(height: 14), action],
              );
            }
            return Row(
              children: [
                Expanded(child: content),
                const SizedBox(width: 16),
                action,
              ],
            );
          },
        ),
      ),
    );
  }
}

class _TypeBadge extends StatelessWidget {
  const _TypeBadge({required this.assessment});

  final DemoAssessment assessment;

  @override
  Widget build(BuildContext context) {
    final label = assessment.isStrictExam
        ? 'Exam'
        : assessment.attendanceOnly
            ? 'Practice'
            : assessment.graded
                ? 'Graded'
                : 'Self-check';
    final color = _accentFor(assessment);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _LearningUpdates extends StatelessWidget {
  const _LearningUpdates({
    required this.assignments,
    required this.feedbackItems,
    required this.onOpenAssignment,
    required this.onOpenFeedback,
  });

  final List<DemoAssignmentItem> assignments;
  final List<DemoFeedbackItem> feedbackItems;
  final ValueChanged<DemoAssignmentItem> onOpenAssignment;
  final ValueChanged<DemoFeedbackItem> onOpenFeedback;

  @override
  Widget build(BuildContext context) {
    if (assignments.isEmpty && feedbackItems.isEmpty) {
      return const SizedBox.shrink();
    }
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _surface,
        border: Border.all(color: _line),
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(
            color: Color(0x060F172A),
            blurRadius: 16,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Learning updates',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: _brandDark,
                  fontWeight: FontWeight.w900,
                ),
          ),
          const SizedBox(height: 12),
          if (assignments.isNotEmpty)
            _UpdateSummaryRow(
              title: 'Assignments due',
              subtitle: '${assignments.length} item${assignments.length == 1 ? '' : 's'} available',
              actionLabel: 'Open',
              color: _success,
              icon: Icons.assignment_outlined,
              onTap: () => onOpenAssignment(assignments.first),
            ),
          if (assignments.isNotEmpty && feedbackItems.isNotEmpty)
            const Divider(height: 18, color: _line),
          if (feedbackItems.isNotEmpty)
            _UpdateSummaryRow(
              title: 'Feedback available',
              subtitle: '${feedbackItems.length} item${feedbackItems.length == 1 ? '' : 's'} released',
              actionLabel: 'View',
              color: _brand,
              icon: Icons.rate_review_outlined,
              onTap: () => onOpenFeedback(feedbackItems.first),
            ),
        ],
      ),
    );
  }
}

class _UpdatesList extends StatelessWidget {
  const _UpdatesList({
    required this.assignments,
    required this.feedbackItems,
    required this.onOpenAssignment,
    required this.onOpenFeedback,
  });

  final List<DemoAssignmentItem> assignments;
  final List<DemoFeedbackItem> feedbackItems;
  final ValueChanged<DemoAssignmentItem> onOpenAssignment;
  final ValueChanged<DemoFeedbackItem> onOpenFeedback;

  @override
  Widget build(BuildContext context) {
    if (assignments.isEmpty && feedbackItems.isEmpty) {
      return const _EmptyCard(
        title: 'No learning updates',
        message: 'Assignments and lecturer feedback will appear here.',
      );
    }
    return Container(
      decoration: BoxDecoration(
        color: _surface,
        border: Border.all(color: _line),
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(
            color: Color(0x060F172A),
            blurRadius: 16,
            offset: Offset(0, 8),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(height: 4, color: _success),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 6),
            child: Text(
              'Updates',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: _brandDark,
                    fontWeight: FontWeight.w900,
                  ),
            ),
          ),
          for (final assignment in assignments) ...[
            const Divider(height: 1, color: _line),
            _UpdateDetailRow(
              title: assignment.title,
              subtitle: '${assignment.course.code} • Due ${assignment.dueLabel}',
              actionLabel: 'Open',
              color: _success,
              onTap: () => onOpenAssignment(assignment),
            ),
          ],
          for (final item in feedbackItems) ...[
            const Divider(height: 1, color: _line),
            _UpdateDetailRow(
              title: item.title,
              subtitle: '${item.course.code} • ${item.scoreLabel}',
              actionLabel: 'View',
              color: _brand,
              onTap: () => onOpenFeedback(item),
            ),
          ],
        ],
      ),
    );
  }
}

class _UpdateSummaryRow extends StatelessWidget {
  const _UpdateSummaryRow({
    required this.title,
    required this.subtitle,
    required this.actionLabel,
    required this.color,
    required this.icon,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final String actionLabel;
  final Color color;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(icon, color: color, size: 22),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: _brandDark,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                style: const TextStyle(
                  color: _muted,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        TextButton(onPressed: onTap, child: Text(actionLabel)),
      ],
    );
  }
}

class _UpdateDetailRow extends StatelessWidget {
  const _UpdateDetailRow({
    required this.title,
    required this.subtitle,
    required this.actionLabel,
    required this.color,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final String actionLabel;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Container(width: 4, height: 42, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: _brandDark,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: _muted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          OutlinedButton(onPressed: onTap, child: Text(actionLabel)),
        ],
      ),
    );
  }
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard({required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _surface,
        border: Border.all(color: _line),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: _brandDark,
                  fontWeight: FontWeight.w900,
                ),
          ),
          const SizedBox(height: 6),
          Text(
            message,
            style: const TextStyle(
              color: _muted,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

IconData _iconFor(DemoAssessment assessment) {
  if (assessment.isStrictExam) return Icons.verified_user_outlined;
  if (assessment.attendanceOnly) return Icons.menu_book_outlined;
  return Icons.assignment_turned_in_outlined;
}

Color _accentFor(DemoAssessment assessment) {
  if (assessment.isStrictExam) return _brand;
  if (assessment.attendanceOnly) return _purple;
  if (assessment.graded) return _success;
  return _warning;
}

Color _softAccentFor(DemoAssessment assessment) {
  final color = _accentFor(assessment);
  return color.withValues(alpha: 0.035);
}

String _buttonLabelFor(DemoAssessment assessment) {
  if (assessment.isStrictExam) return 'Start checks';
  if (assessment.attendanceOnly) return 'Open practice';
  return 'Open';
}

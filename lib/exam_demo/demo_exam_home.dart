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
      backgroundColor: const Color(0xFFF4F7FB),
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        titleSpacing: 20,
        title: const _AppTitle(),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
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
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 96),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1080),
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
          width: 34,
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: const Color(0xFF0F4C81),
            borderRadius: BorderRadius.circular(8),
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
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFE2E8F0)),
        borderRadius: BorderRadius.circular(16),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 720;
          final intro = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Welcome back',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      color: const Color(0xFF0F172A),
                      fontWeight: FontWeight.w900,
                    ),
              ),
              const SizedBox(height: 6),
              Text(
                _summaryText,
                style: const TextStyle(
                  color: Color(0xFF64748B),
                  fontSize: 16,
                  height: 1.45,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          );

          final date = _DateBox(today: today);
          if (!wide) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [intro, const SizedBox(height: 16), date],
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

class _DateBox extends StatelessWidget {
  const _DateBox({required this.today});

  final DateTime today;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          const Text(
            'Today',
            style: TextStyle(
              color: Color(0xFF64748B),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _formatDate(today),
            style: const TextStyle(
              color: Color(0xFF0F172A),
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
                onTap: onGradeBook,
              ),
            ),
            SizedBox(
              width: width,
              child: _QuickAction(
                title: 'Identity setup',
                subtitle: 'Prepare access',
                icon: Icons.account_circle_outlined,
                onTap: onIdentity,
              ),
            ),
            SizedBox(
              width: width,
              child: _QuickAction(
                title: 'Exam check',
                subtitle: 'Open readiness check',
                icon: Icons.verified_user_outlined,
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
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0xFFE2E8F0)),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              Icon(icon, color: const Color(0xFF0F4C81), size: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Color(0xFF0F172A),
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF64748B),
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
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(18),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 700;
          final details = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Next assessment',
                style: TextStyle(
                  color: Color(0xFFBFDBFE),
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                assessment.title,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                '${assessment.course.code} • ${assessment.durationMinutes} min • ${assessment.scheduleLabel()}',
                style: const TextStyle(
                  color: Color(0xFFCBD5E1),
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Lecturer: ${assessment.course.lecturer}',
                style: const TextStyle(
                  color: Color(0xFF94A3B8),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          );
          final button = FilledButton(
            onPressed: onOpen,
            style: FilledButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: const Color(0xFF0F172A),
              minimumSize: const Size(170, 52),
              textStyle: const TextStyle(fontWeight: FontWeight.w900),
            ),
            child: Text(_buttonLabelFor(assessment)),
          );

          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [details, const SizedBox(height: 18), button],
            );
          }
          return Row(
            children: [
              Expanded(child: details),
              const SizedBox(width: 24),
              button,
            ],
          );
        },
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
        color: Colors.white,
        border: Border.all(color: const Color(0xFFE2E8F0)),
        borderRadius: BorderRadius.circular(14),
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
      color: selected ? const Color(0xFF0F4C81) : Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
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
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFE2E8F0)),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 6),
            child: Text(
              title,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: const Color(0xFF0F172A),
                    fontWeight: FontWeight.w900,
                  ),
            ),
          ),
          for (var index = 0; index < assessments.length; index++) ...[
            if (index > 0) const Divider(height: 1, color: Color(0xFFE2E8F0)),
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

class _AssessmentRow extends StatelessWidget {
  const _AssessmentRow({required this.assessment, required this.onOpen});

  final DemoAssessment assessment;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 680;
          final content = Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(_iconFor(assessment), color: const Color(0xFF0F4C81)),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      assessment.title,
                      style: const TextStyle(
                        color: Color(0xFF0F172A),
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                      ),
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
                        color: Color(0xFF64748B),
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
              backgroundColor: const Color(0xFF0F4C81),
              foregroundColor: Colors.white,
              minimumSize: const Size(140, 44),
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
        color: Colors.white,
        border: Border.all(color: const Color(0xFFE2E8F0)),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Learning updates',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: const Color(0xFF0F172A),
                  fontWeight: FontWeight.w900,
                ),
          ),
          const SizedBox(height: 12),
          if (assignments.isNotEmpty)
            _UpdateSummaryRow(
              title: 'Assignments due',
              subtitle: '${assignments.length} item${assignments.length == 1 ? '' : 's'} available',
              actionLabel: 'Open',
              onTap: () => onOpenAssignment(assignments.first),
            ),
          if (assignments.isNotEmpty && feedbackItems.isNotEmpty)
            const Divider(height: 18, color: Color(0xFFE2E8F0)),
          if (feedbackItems.isNotEmpty)
            _UpdateSummaryRow(
              title: 'Feedback available',
              subtitle: '${feedbackItems.length} item${feedbackItems.length == 1 ? '' : 's'} released',
              actionLabel: 'View',
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
        color: Colors.white,
        border: Border.all(color: const Color(0xFFE2E8F0)),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 6),
            child: Text(
              'Updates',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: const Color(0xFF0F172A),
                    fontWeight: FontWeight.w900,
                  ),
            ),
          ),
          for (final assignment in assignments) ...[
            const Divider(height: 1, color: Color(0xFFE2E8F0)),
            _UpdateDetailRow(
              title: assignment.title,
              subtitle: '${assignment.course.code} • Due ${assignment.dueLabel}',
              actionLabel: 'Open',
              onTap: () => onOpenAssignment(assignment),
            ),
          ],
          for (final item in feedbackItems) ...[
            const Divider(height: 1, color: Color(0xFFE2E8F0)),
            _UpdateDetailRow(
              title: item.title,
              subtitle: '${item.course.code} • ${item.scoreLabel}',
              actionLabel: 'View',
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
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final String actionLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Color(0xFF0F172A),
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                style: const TextStyle(
                  color: Color(0xFF64748B),
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
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final String actionLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Color(0xFF0F172A),
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: Color(0xFF64748B),
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
        color: Colors.white,
        border: Border.all(color: const Color(0xFFE2E8F0)),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: const Color(0xFF0F172A),
                  fontWeight: FontWeight.w900,
                ),
          ),
          const SizedBox(height: 6),
          Text(
            message,
            style: const TextStyle(
              color: Color(0xFF64748B),
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

String _buttonLabelFor(DemoAssessment assessment) {
  if (assessment.isStrictExam) return 'Start checks';
  if (assessment.attendanceOnly) return 'Open practice';
  return 'Open';
}

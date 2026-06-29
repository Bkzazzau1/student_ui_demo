import 'package:flutter/material.dart';

import '../auth/student_logout_view.dart';
import '../face_demo/demo_face_id_view.dart';
import 'assignment_submission_view.dart';
import 'demo_exam_models.dart';
import 'demo_exam_result_view.dart';
import 'demo_exam_service.dart';
import 'exam_attendance_view.dart';
import 'feedback_detail_view.dart';
import 'grade_book_view.dart';
import 'secure_exam_setup_view.dart';
import 'student_assessment_hub_extras.dart';

const Color _brand = Color(0xFF0F4C81);
const Color _brandDark = Color(0xFF0B1220);
const Color _pageBg = Color(0xFFF4F7FB);
const Color _surface = Colors.white;
const Color _surfaceSoft = Color(0xFFF8FAFC);
const Color _line = Color(0xFFE2E8F0);
const Color _muted = Color(0xFF64748B);
const Color _success = Color(0xFF16A34A);
const Color _warning = Color(0xFFF59E0B);
const Color _purple = Color(0xFF7C3AED);

class DemoStudentProfile {
  const DemoStudentProfile({
    required this.fullName,
    required this.studentId,
    required this.department,
    required this.level,
    required this.programme,
    required this.faculty,
    required this.session,
    required this.supportLink,
    required this.supportEmail,
  });

  final String fullName;
  final String studentId;
  final String department;
  final String level;
  final String programme;
  final String faculty;
  final String session;
  final String supportLink;
  final String supportEmail;
}

const DemoStudentProfile _studentProfile = DemoStudentProfile(
  fullName: 'Aisha Abdullahi',
  studentId: 'KSLAS/STD/2026/001',
  department: 'Computer Science',
  level: '300 Level',
  programme: 'B.Sc. Computer Science',
  faculty: 'Faculty of Computing',
  session: '2025/2026 Academic Session',
  supportLink: 'support.kslas.edu.ng',
  supportEmail: 'support@kslas.edu.ng',
);

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
          _StudentPill(
            profile: _studentProfile,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const StudentInformationView(profile: _studentProfile),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 12, left: 8),
            child: IconButton(
              tooltip: 'Sign out',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const StudentLogoutView()),
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
                        MaterialPageRoute<void>(builder: (_) => const GradeBookView()),
                      ),
                      onIdentity: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(builder: (_) => const DemoFaceIdView()),
                      ),
                      onSchedule: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(builder: (_) => const ExamAttendanceView()),
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

  Future<void> _openSetup(BuildContext context, DemoAssessment assessment) async {
    final result = await Navigator.of(context).push<DemoExamResult>(
      MaterialPageRoute<DemoExamResult>(
        builder: (_) => SecureExamSetupView(assessment: assessment),
      ),
    );
    if (result == null || !context.mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => DemoExamResultView(result: result)),
    );
  }

  Future<void> _openAssignment(BuildContext context, DemoAssignmentItem assignment) async {
    final result = await Navigator.of(context).push<AssignmentSubmissionResult>(
      MaterialPageRoute<AssignmentSubmissionResult>(
        builder: (_) => AssignmentSubmissionView(assignment: assignment),
      ),
    );
    if (result == null || !context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${result.assignment.course.code} assignment submitted.')),
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
            gradient: const LinearGradient(colors: [_brand, Color(0xFF1D4ED8)]),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Text('K', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
        ),
        const SizedBox(width: 10),
        const Text('K-SLAS Student Portal', style: TextStyle(fontWeight: FontWeight.w900)),
      ],
    );
  }
}

class _StudentPill extends StatelessWidget {
  const _StudentPill({required this.profile, required this.onTap});

  final DemoStudentProfile profile;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: _surfaceSoft,
              border: Border.all(color: const Color(0xFFD6DFEA)),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.person_outline, size: 16, color: _brand),
                const SizedBox(width: 7),
                Text(
                  profile.studentId,
                  style: const TextStyle(color: _brandDark, fontWeight: FontWeight.w900, fontSize: 12),
                ),
                const SizedBox(width: 6),
                const Icon(Icons.keyboard_arrow_down_rounded, size: 17, color: _muted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class StudentInformationView extends StatelessWidget {
  const StudentInformationView({super.key, required this.profile});

  final DemoStudentProfile profile;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _pageBg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: const Text('Student Information', style: TextStyle(fontWeight: FontWeight.w900)),
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
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 80),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 940),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _StudentProfileHero(profile: profile),
                    const SizedBox(height: 16),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final wide = constraints.maxWidth >= 760;
                        final details = _StudentDetailsCard(profile: profile);
                        final support = _StudentSupportCard(profile: profile);
                        if (!wide) {
                          return Column(children: [details, const SizedBox(height: 16), support]);
                        }
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(flex: 6, child: details),
                            const SizedBox(width: 16),
                            Expanded(flex: 4, child: support),
                          ],
                        );
                      },
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
}

class _StudentProfileHero extends StatelessWidget {
  const _StudentProfileHero({required this.profile});

  final DemoStudentProfile profile;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [_brandDark, Color(0xFF113A63), _brand]),
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [BoxShadow(color: Color(0x1F0F172A), blurRadius: 26, offset: Offset(0, 14))],
      ),
      child: Row(
        children: [
          Container(
            width: 72,
            height: 72,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.12),
              border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
              borderRadius: BorderRadius.circular(22),
            ),
            child: Text(
              _initials(profile.fullName),
              style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900),
            ),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Student profile', style: TextStyle(color: Color(0xFFDBEAFE), fontWeight: FontWeight.w900)),
                const SizedBox(height: 6),
                Text(
                  profile.fullName,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(color: Colors.white, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 6),
                Text(
                  '${profile.studentId} • ${profile.level}',
                  style: const TextStyle(color: Color(0xFFE2E8F0), fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _initials(String value) {
    final parts = value.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty) return 'ST';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return '${parts.first.substring(0, 1)}${parts.last.substring(0, 1)}'.toUpperCase();
  }
}

class _StudentDetailsCard extends StatelessWidget {
  const _StudentDetailsCard({required this.profile});

  final DemoStudentProfile profile;

  @override
  Widget build(BuildContext context) {
    return _InfoPanel(
      title: 'Academic details',
      icon: Icons.school_outlined,
      children: [
        _InfoRow(label: 'Full name', value: profile.fullName),
        _InfoRow(label: 'Student ID', value: profile.studentId),
        _InfoRow(label: 'Department', value: profile.department),
        _InfoRow(label: 'Level', value: profile.level),
        _InfoRow(label: 'Programme', value: profile.programme),
        _InfoRow(label: 'Faculty', value: profile.faculty),
        _InfoRow(label: 'Session', value: profile.session),
      ],
    );
  }
}

class _StudentSupportCard extends StatelessWidget {
  const _StudentSupportCard({required this.profile});

  final DemoStudentProfile profile;

  @override
  Widget build(BuildContext context) {
    return _InfoPanel(
      title: 'Support',
      icon: Icons.support_agent_outlined,
      children: [
        _SupportBox(
          title: 'DLI Support Desk',
          message: 'Use this link for help with login, assessment access, camera check, and submissions.',
          link: profile.supportLink,
          email: profile.supportEmail,
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Support link: ${profile.supportLink}')),
          ),
          icon: const Icon(Icons.open_in_new_rounded),
          label: const Text('Open support link'),
        ),
      ],
    );
  }
}

class _InfoPanel extends StatelessWidget {
  const _InfoPanel({required this.title, required this.icon, required this.children});

  final String title;
  final IconData icon;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _line),
        boxShadow: const [BoxShadow(color: Color(0x080F172A), blurRadius: 18, offset: Offset(0, 10))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(color: const Color(0xFFEFF6FF), borderRadius: BorderRadius.circular(14)),
            child: Icon(icon, color: _brand),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(title, style: Theme.of(context).textTheme.titleLarge?.copyWith(color: _brandDark, fontWeight: FontWeight.w900)),
          ),
        ]),
        const SizedBox(height: 14),
        ...children,
      ]),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 11),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: 130, child: Text(label, style: const TextStyle(color: _muted, fontWeight: FontWeight.w800))),
        Expanded(child: Text(value, style: const TextStyle(color: _brandDark, fontWeight: FontWeight.w800))),
      ]),
    );
  }
}

class _SupportBox extends StatelessWidget {
  const _SupportBox({required this.title, required this.message, required this.link, required this.email});

  final String title;
  final String message;
  final String link;
  final String email;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFDE68A)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(color: _brandDark, fontWeight: FontWeight.w900)),
        const SizedBox(height: 7),
        Text(message, style: const TextStyle(color: _muted, height: 1.4, fontWeight: FontWeight.w600)),
        const SizedBox(height: 12),
        Text(link, style: const TextStyle(color: _brand, fontWeight: FontWeight.w900)),
        const SizedBox(height: 4),
        Text(email, style: const TextStyle(color: _brandDark, fontWeight: FontWeight.w700)),
      ]),
    );
  }
}

class _WelcomeHeader extends StatelessWidget {
  const _WelcomeHeader({required this.today, required this.examCount, required this.activityCount});

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
        boxShadow: const [BoxShadow(color: Color(0x0F0F172A), blurRadius: 22, offset: Offset(0, 12))],
      ),
      child: Column(children: [
        Container(height: 6, decoration: const BoxDecoration(gradient: LinearGradient(colors: [_brand, _success, _warning]))),
        Padding(
          padding: const EdgeInsets.all(22),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Welcome back', style: Theme.of(context).textTheme.headlineMedium?.copyWith(color: _brandDark, fontWeight: FontWeight.w900)),
                const SizedBox(height: 6),
                Text(_summaryText, style: const TextStyle(color: _muted, fontSize: 16, height: 1.45, fontWeight: FontWeight.w600)),
                const SizedBox(height: 16),
                Wrap(spacing: 10, runSpacing: 10, children: [
                  _MetricPill(value: '$examCount', label: examCount == 1 ? 'exam' : 'exams', color: _brand),
                  _MetricPill(value: '$activityCount', label: activityCount == 1 ? 'activity' : 'activities', color: _success),
                ]),
              ]),
            ),
            const SizedBox(width: 18),
            _DateBox(today: today),
          ]),
        ),
      ]),
    );
  }

  String get _summaryText {
    final examPart = examCount == 1 ? '1 exam' : '$examCount exams';
    final activityPart = activityCount == 1 ? '1 activity' : '$activityCount activities';
    if (activityCount == 0) return 'You have no assessment activity scheduled today.';
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
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text(value, style: TextStyle(color: color, fontWeight: FontWeight.w900)),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(color: Color(0xFF334155), fontWeight: FontWeight.w800)),
      ]),
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
      decoration: BoxDecoration(color: _surfaceSoft, border: Border.all(color: _line), borderRadius: BorderRadius.circular(16)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
        const Text('Today', style: TextStyle(color: _muted, fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Text(
          '${today.day.toString().padLeft(2, '0')}/${today.month.toString().padLeft(2, '0')}/${today.year}',
          style: const TextStyle(color: _brandDark, fontWeight: FontWeight.w900, fontSize: 16),
        ),
      ]),
    );
  }
}

class _QuickActions extends StatelessWidget {
  const _QuickActions({required this.onGradeBook, required this.onIdentity, required this.onSchedule});

  final VoidCallback onGradeBook;
  final VoidCallback onIdentity;
  final VoidCallback onSchedule;

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
                subtitle: 'Scores, grades, CGPA',
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
                title: 'Schedule',
                subtitle: 'Exams & attendance',
                icon: Icons.event_note_outlined,
                color: _success,
                onTap: onSchedule,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({required this.title, required this.subtitle, required this.icon, required this.color, required this.onTap});

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
          decoration: BoxDecoration(border: Border.all(color: _line), borderRadius: BorderRadius.circular(18)),
          child: Row(children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(color: color.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(14)),
              child: Icon(icon, color: color, size: 23),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: const TextStyle(color: _brandDark, fontWeight: FontWeight.w900)),
                const SizedBox(height: 2),
                Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: _muted, fontWeight: FontWeight.w600)),
              ]),
            ),
            const Icon(Icons.chevron_right, color: Color(0xFF94A3B8)),
          ]),
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
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [_brandDark, Color(0xFF113A63), _brand]),
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [BoxShadow(color: Color(0x260F172A), blurRadius: 28, offset: Offset(0, 16))],
      ),
      child: LayoutBuilder(builder: (context, constraints) {
        final compact = constraints.maxWidth < 700;
        final details = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _GlassLabel(text: 'Next assessment'),
          const SizedBox(height: 14),
          Text(assessment.title, style: Theme.of(context).textTheme.headlineSmall?.copyWith(color: Colors.white, fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          Text('${assessment.course.code} • ${assessment.durationMinutes} min • ${assessment.scheduleLabel()}', style: const TextStyle(color: Color(0xFFE2E8F0), fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text('Lecturer: ${assessment.course.lecturer}', style: const TextStyle(color: Color(0xFFCBD5E1), fontWeight: FontWeight.w600)),
        ]);
        final action = FilledButton(
          onPressed: onOpen,
          style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: _brandDark, minimumSize: const Size(170, 54)),
          child: Text(_buttonLabelFor(assessment)),
        );
        if (compact) return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [details, const SizedBox(height: 18), action]);
        return Row(children: [Expanded(child: details), const SizedBox(width: 20), action]);
      }),
    );
  }
}

class _GlassLabel extends StatelessWidget {
  const _GlassLabel({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.12), border: Border.all(color: Colors.white.withValues(alpha: 0.16)), borderRadius: BorderRadius.circular(999)),
      child: Text(text, style: const TextStyle(color: Color(0xFFDBEAFE), fontWeight: FontWeight.w900)),
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
      decoration: BoxDecoration(color: _surface, border: Border.all(color: _line), borderRadius: BorderRadius.circular(16)),
      child: Wrap(spacing: 6, runSpacing: 6, children: [
        for (final tab in _DashboardTab.values) _TabButton(label: tab.label, selected: selected == tab, onTap: () => onChanged(tab)),
      ]),
    );
  }
}

class _TabButton extends StatelessWidget {
  const _TabButton({required this.label, required this.selected, required this.onTap});

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
          child: Text(label, style: TextStyle(color: selected ? Colors.white : const Color(0xFF334155), fontWeight: FontWeight.w900)),
        ),
      ),
    );
  }
}

class _AssessmentList extends StatelessWidget {
  const _AssessmentList({required this.title, required this.emptyTitle, required this.emptyMessage, required this.assessments, required this.onOpen});

  final String title;
  final String emptyTitle;
  final String emptyMessage;
  final List<DemoAssessment> assessments;
  final ValueChanged<DemoAssessment> onOpen;

  @override
  Widget build(BuildContext context) {
    if (assessments.isEmpty) return _EmptyCard(title: emptyTitle, message: emptyMessage);
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(color: _surface, border: Border.all(color: _line), borderRadius: BorderRadius.circular(20)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(height: 4, color: _brand),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 6),
          child: Row(children: [
            Expanded(child: Text(title, style: Theme.of(context).textTheme.titleLarge?.copyWith(color: _brandDark, fontWeight: FontWeight.w900))),
            _CountBadge(count: assessments.length),
          ]),
        ),
        for (var index = 0; index < assessments.length; index++) ...[
          if (index > 0) const Divider(height: 1, color: _line),
          _AssessmentRow(assessment: assessments[index], onOpen: () => onOpen(assessments[index])),
        ],
      ]),
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
      decoration: BoxDecoration(color: const Color(0xFFEFF6FF), borderRadius: BorderRadius.circular(999)),
      child: Text('$count', style: const TextStyle(color: _brand, fontWeight: FontWeight.w900)),
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
      color: accent.withValues(alpha: 0.035),
      padding: const EdgeInsets.all(16),
      child: LayoutBuilder(builder: (context, constraints) {
        final compact = constraints.maxWidth < 680;
        final content = Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(width: 4, height: 54, color: accent),
          const SizedBox(width: 12),
          Container(width: 44, height: 44, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)), child: Icon(_iconFor(assessment), color: accent)),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(assessment.title, style: const TextStyle(color: _brandDark, fontWeight: FontWeight.w900, fontSize: 16)),
            const SizedBox(height: 4),
            Text('${assessment.course.code} • ${assessment.course.title}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFF334155), fontWeight: FontWeight.w700)),
            const SizedBox(height: 5),
            Text('${assessment.durationMinutes} min • ${assessment.scheduleLabel()} • ${assessment.course.lecturer}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: _muted, fontWeight: FontWeight.w600)),
          ])),
        ]);
        final action = FilledButton(
          onPressed: onOpen,
          style: FilledButton.styleFrom(backgroundColor: accent, foregroundColor: Colors.white, minimumSize: const Size(140, 44)),
          child: Text(_buttonLabelFor(assessment)),
        );
        if (compact) return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [content, const SizedBox(height: 14), action]);
        return Row(children: [Expanded(child: content), const SizedBox(width: 16), action]);
      }),
    );
  }
}

class _LearningUpdates extends StatelessWidget {
  const _LearningUpdates({required this.assignments, required this.feedbackItems, required this.onOpenAssignment, required this.onOpenFeedback});

  final List<DemoAssignmentItem> assignments;
  final List<DemoFeedbackItem> feedbackItems;
  final ValueChanged<DemoAssignmentItem> onOpenAssignment;
  final ValueChanged<DemoFeedbackItem> onOpenFeedback;

  @override
  Widget build(BuildContext context) {
    if (assignments.isEmpty && feedbackItems.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: _surface, border: Border.all(color: _line), borderRadius: BorderRadius.circular(20)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Learning updates', style: Theme.of(context).textTheme.titleLarge?.copyWith(color: _brandDark, fontWeight: FontWeight.w900)),
        const SizedBox(height: 12),
        if (assignments.isNotEmpty)
          _UpdateSummaryRow(title: 'Assignments due', subtitle: '${assignments.length} item${assignments.length == 1 ? '' : 's'} available', actionLabel: 'Open', onTap: () => onOpenAssignment(assignments.first)),
        if (assignments.isNotEmpty && feedbackItems.isNotEmpty) const Divider(height: 18, color: _line),
        if (feedbackItems.isNotEmpty)
          _UpdateSummaryRow(title: 'Feedback available', subtitle: '${feedbackItems.length} item${feedbackItems.length == 1 ? '' : 's'} released', actionLabel: 'View', onTap: () => onOpenFeedback(feedbackItems.first)),
      ]),
    );
  }
}

class _UpdatesList extends StatelessWidget {
  const _UpdatesList({required this.assignments, required this.feedbackItems, required this.onOpenAssignment, required this.onOpenFeedback});

  final List<DemoAssignmentItem> assignments;
  final List<DemoFeedbackItem> feedbackItems;
  final ValueChanged<DemoAssignmentItem> onOpenAssignment;
  final ValueChanged<DemoFeedbackItem> onOpenFeedback;

  @override
  Widget build(BuildContext context) {
    if (assignments.isEmpty && feedbackItems.isEmpty) {
      return const _EmptyCard(title: 'No learning updates', message: 'Assignments and lecturer feedback will appear here.');
    }
    return Container(
      decoration: BoxDecoration(color: _surface, border: Border.all(color: _line), borderRadius: BorderRadius.circular(20)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(padding: const EdgeInsets.all(18), child: Text('Updates', style: Theme.of(context).textTheme.titleLarge?.copyWith(color: _brandDark, fontWeight: FontWeight.w900))),
        for (final assignment in assignments) ...[
          const Divider(height: 1, color: _line),
          _UpdateDetailRow(title: assignment.title, subtitle: '${assignment.course.code} • Due ${assignment.dueLabel}', actionLabel: 'Open', onTap: () => onOpenAssignment(assignment)),
        ],
        for (final item in feedbackItems) ...[
          const Divider(height: 1, color: _line),
          _UpdateDetailRow(title: item.title, subtitle: '${item.course.code} • ${item.scoreLabel}', actionLabel: 'View', onTap: () => onOpenFeedback(item)),
        ],
      ]),
    );
  }
}

class _UpdateSummaryRow extends StatelessWidget {
  const _UpdateSummaryRow({required this.title, required this.subtitle, required this.actionLabel, required this.onTap});

  final String title;
  final String subtitle;
  final String actionLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(color: _brandDark, fontWeight: FontWeight.w900)),
        const SizedBox(height: 3),
        Text(subtitle, style: const TextStyle(color: _muted, fontWeight: FontWeight.w600)),
      ])),
      TextButton(onPressed: onTap, child: Text(actionLabel)),
    ]);
  }
}

class _UpdateDetailRow extends StatelessWidget {
  const _UpdateDetailRow({required this.title, required this.subtitle, required this.actionLabel, required this.onTap});

  final String title;
  final String subtitle;
  final String actionLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(color: _brandDark, fontWeight: FontWeight.w900)),
          const SizedBox(height: 4),
          Text(subtitle, style: const TextStyle(color: _muted, fontWeight: FontWeight.w600)),
        ])),
        OutlinedButton(onPressed: onTap, child: Text(actionLabel)),
      ]),
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
      decoration: BoxDecoration(color: _surface, border: Border.all(color: _line), borderRadius: BorderRadius.circular(18)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: Theme.of(context).textTheme.titleLarge?.copyWith(color: _brandDark, fontWeight: FontWeight.w900)),
        const SizedBox(height: 6),
        Text(message, style: const TextStyle(color: _muted, fontWeight: FontWeight.w600)),
      ]),
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

String _buttonLabelFor(DemoAssessment assessment) {
  if (assessment.isStrictExam) return 'Start exam check';
  if (assessment.attendanceOnly) return 'Open practice';
  return 'Open';
}

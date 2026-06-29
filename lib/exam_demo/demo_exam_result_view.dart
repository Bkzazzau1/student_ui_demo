import 'package:flutter/material.dart';

import 'demo_exam_home.dart';
import 'demo_exam_models.dart';
import 'student_exam_feedback_view.dart';

const Color _brand = Color(0xFF0F4C81);
const Color _brandDark = Color(0xFF0B1220);
const Color _surface = Colors.white;
const Color _surfaceSoft = Color(0xFFF8FAFC);
const Color _line = Color(0xFFE2E8F0);
const Color _muted = Color(0xFF64748B);
const Color _success = Color(0xFF16A34A);
const Color _warning = Color(0xFFF59E0B);

class DemoExamResultView extends StatefulWidget {
  const DemoExamResultView({super.key, required this.result});

  final DemoExamResult result;

  @override
  State<DemoExamResultView> createState() => _DemoExamResultViewState();
}

class _DemoExamResultViewState extends State<DemoExamResultView> {
  final TextEditingController _observationController = TextEditingController();
  bool _observationSaved = false;

  DemoExamResult get result => widget.result;

  @override
  void dispose() {
    _observationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final duration = result.endedAt.difference(result.startedAt);
    final showScore = !result.assessment.attendanceOnly;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, value) {
        if (!didPop) _showDashboardReminder(context);
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF4F7FB),
        appBar: AppBar(
          automaticallyImplyLeading: false,
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          title: Text(
            _resultTitle,
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: TextButton.icon(
                onPressed: _goToDashboard,
                icon: const Icon(Icons.dashboard_outlined, size: 18),
                label: const Text('Dashboard'),
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
          child: SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 96),
              children: [
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1040),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _SubmissionHero(
                          result: result,
                          gradeLabel: _gradeLabel,
                          showScore: showScore,
                        ),
                        const SizedBox(height: 16),
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final wide = constraints.maxWidth >= 900;
                            final summary = _ResultCard(
                              title: 'Submission summary',
                              rows: [
                                ('Course', '${result.assessment.course.code} - ${result.assessment.course.title}'),
                                ('Started', _formatDateTime(result.startedAt)),
                                ('Submitted', _formatDateTime(result.endedAt)),
                                ('Duration used', '${duration.inMinutes} min ${duration.inSeconds % 60} sec'),
                                ('Identity check', _identityLabel(result.agentDecision)),
                                ('Exam check', _examCheckLabel(result.agentDecision)),
                                ('Submission status', 'Submitted successfully'),
                                ('Review record', _reviewRecordLabel),
                              ],
                            );
                            final observation = _ObservationCard(
                              controller: _observationController,
                              saved: _observationSaved,
                              onChanged: () {
                                if (_observationSaved) {
                                  setState(() => _observationSaved = false);
                                }
                              },
                              onSave: _saveObservation,
                            );

                            if (!wide) {
                              return Column(
                                children: [summary, const SizedBox(height: 16), observation],
                              );
                            }
                            return Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(flex: 5, child: summary),
                                const SizedBox(width: 16),
                                Expanded(flex: 5, child: observation),
                              ],
                            );
                          },
                        ),
                        const SizedBox(height: 16),
                        _NextActions(
                          onDashboard: _goToDashboard,
                          onFeedback: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => StudentExamFeedbackView(result: result),
                            ),
                          ),
                        ),
                      ],
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

  void _saveObservation() {
    FocusScope.of(context).unfocus();
    setState(() => _observationSaved = true);
    final hasText = _observationController.text.trim().isNotEmpty;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          hasText
              ? 'Your observation has been saved on this submission page.'
              : 'No observation entered. You can still return to the dashboard.',
        ),
      ),
    );
  }

  void _goToDashboard() {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => const DemoExamHome()),
      (route) => false,
    );
  }

  void _showDashboardReminder(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Use the Dashboard button to leave this submission page.'),
      ),
    );
  }

  String _identityLabel(String decision) {
    if (result.assessment.attendanceOnly) return 'Not required for this activity';
    if (decision == 'approved_to_start' ||
        decision == 'agentic_proctoring_ready' ||
        decision == 'face_id_verified' ||
        decision == 'start_approved') {
      return 'Completed';
    }
    return 'Completed where required';
  }

  String _examCheckLabel(String decision) {
    if (result.assessment.attendanceOnly) return 'Not required for this activity';
    if (decision == 'approved_to_start' ||
        decision == 'agentic_proctoring_ready' ||
        decision == 'security_review_ready' ||
        decision == 'start_approved') {
      return 'Completed';
    }
    return 'Completed where required';
  }

  String get _reviewRecordLabel {
    if (result.proctoringManifestPath == null ||
        result.proctoringManifestPath!.trim().isEmpty) {
      return 'No additional review record required';
    }
    return 'Saved for review';
  }

  String get _resultTitle {
    if (result.assessment.isStrictExam) return 'Exam submitted';
    if (result.assessment.attendanceOnly) return 'Practice submitted';
    return 'Assessment submitted';
  }

  String get _gradeLabel {
    if (result.assessment.attendanceOnly) return 'Completed';
    final percent = result.percent;
    if (percent >= 70) return 'A';
    if (percent >= 60) return 'B';
    if (percent >= 50) return 'C';
    if (percent >= 45) return 'D';
    return 'F';
  }

  String _formatDateTime(DateTime value) {
    final local = value.toLocal();
    final day = local.day.toString().padLeft(2, '0');
    final month = local.month.toString().padLeft(2, '0');
    final year = local.year.toString();
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$day/$month/$year $hour:$minute';
  }
}

class _SubmissionHero extends StatelessWidget {
  const _SubmissionHero({
    required this.result,
    required this.gradeLabel,
    required this.showScore,
  });

  final DemoExamResult result;
  final String gradeLabel;
  final bool showScore;

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1F0F172A),
            blurRadius: 26,
            offset: Offset(0, 14),
          ),
        ],
      ),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [_brandDark, Color(0xFF113A63), _brand],
          ),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 760;
            final details = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
                  ),
                  child: const Text(
                    'Submitted successfully',
                    style: TextStyle(color: Color(0xFFDBEAFE), fontWeight: FontWeight.w900),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  result.assessment.title,
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.5,
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  '${result.assessment.course.code} • ${result.assessment.course.title}',
                  style: const TextStyle(
                    color: Color(0xFFE2E8F0),
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  'Lecturer: ${result.assessment.course.lecturer}',
                  style: const TextStyle(color: Color(0xFFCBD5E1), fontWeight: FontWeight.w600),
                ),
              ],
            );

            final statusBox = _SubmissionStatusBox(
              result: result,
              gradeLabel: gradeLabel,
              showScore: showScore,
            );

            if (!wide) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [details, const SizedBox(height: 18), statusBox],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: details),
                const SizedBox(width: 22),
                SizedBox(width: 250, child: statusBox),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _SubmissionStatusBox extends StatelessWidget {
  const _SubmissionStatusBox({
    required this.result,
    required this.gradeLabel,
    required this.showScore,
  });

  final DemoExamResult result;
  final String gradeLabel;
  final bool showScore;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.check_circle_outline, color: Color(0xFF86EFAC), size: 30),
          const SizedBox(height: 12),
          Text(
            showScore ? '${result.percent}%' : 'Completed',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 34,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            showScore
                ? '${result.scoredMarks} of ${result.totalMarks} marks'
                : 'Activity record saved',
            style: const TextStyle(color: Color(0xFFCBD5E1), fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          _ResultPill(
            label: showScore ? 'Grade: $gradeLabel' : gradeLabel,
            icon: Icons.workspace_premium_outlined,
            color: const Color(0xFF93C5FD),
          ),
        ],
      ),
    );
  }
}

class _ObservationCard extends StatelessWidget {
  const _ObservationCard({
    required this.controller,
    required this.saved,
    required this.onChanged,
    required this.onSave,
  });

  final TextEditingController controller;
  final bool saved;
  final VoidCallback onChanged;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _line),
        boxShadow: const [
          BoxShadow(
            color: Color(0x080F172A),
            blurRadius: 18,
            offset: Offset(0, 10),
          ),
        ],
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
                child: const Icon(Icons.edit_note_outlined, color: _brand),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Student observation',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: _brandDark,
                        fontWeight: FontWeight.w900,
                      ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Write any report, concern, or observation about your assessment before returning to the dashboard.',
            style: TextStyle(color: _muted, height: 1.45, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: controller,
            onChanged: (_) => onChanged(),
            minLines: 5,
            maxLines: 8,
            decoration: InputDecoration(
              hintText: 'Example: I had a network issue, power interruption, noise around me, or any other observation...',
              filled: true,
              fillColor: _surfaceSoft,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: _line),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: _line),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: _brand, width: 1.5),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text(
                  saved ? 'Observation saved on this page.' : 'Optional. You can leave it empty.',
                  style: TextStyle(
                    color: saved ? _success : _muted,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              FilledButton.icon(
                onPressed: onSave,
                icon: Icon(saved ? Icons.check_circle_outline : Icons.save_outlined),
                label: Text(saved ? 'Saved' : 'Save'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _NextActions extends StatelessWidget {
  const _NextActions({required this.onDashboard, required this.onFeedback});

  final VoidCallback onDashboard;
  final VoidCallback onFeedback;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _line),
      ),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          const Text(
            'You can now return to your dashboard.',
            style: TextStyle(color: _muted, fontWeight: FontWeight.w700),
          ),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              OutlinedButton.icon(
                onPressed: onFeedback,
                icon: const Icon(Icons.rate_review_outlined),
                label: const Text('Write feedback'),
              ),
              FilledButton.icon(
                onPressed: onDashboard,
                icon: const Icon(Icons.dashboard_outlined),
                label: const Text('Back to dashboard'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ResultPill extends StatelessWidget {
  const _ResultPill({
    required this.label,
    required this.icon,
    required this.color,
  });

  final String label;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.42)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 7),
          Text(
            label,
            style: TextStyle(color: color, fontWeight: FontWeight.w900),
          ),
        ],
      ),
    );
  }
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({required this.title, required this.rows});

  final String title;
  final List<(String, String)> rows;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _line),
        boxShadow: const [
          BoxShadow(
            color: Color(0x080F172A),
            blurRadius: 18,
            offset: Offset(0, 10),
          ),
        ],
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
          const SizedBox(height: 12),
          ...rows.map(
            (row) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 150,
                    child: Text(
                      row.$1,
                      style: const TextStyle(color: _muted, fontWeight: FontWeight.w800),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      row.$2,
                      style: const TextStyle(color: _brandDark, fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

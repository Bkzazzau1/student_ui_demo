import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../proctoring_demo/companion_cam_panel.dart';
import '../proctoring_demo/live_exam_monitor.dart';
import '../proctoring_demo/live_proctoring_event_service.dart';
import '../proctoring_demo/live_status_panel.dart';
import '../proctoring_demo/live_system_security_monitor.dart';
import '../proctoring_demo/review_clip_sampler.dart';
import 'demo_exam_models.dart';
import 'demo_exam_service.dart';

class DemoExamAttemptView extends StatefulWidget {
  const DemoExamAttemptView({
    super.key,
    required this.assessment,
    required this.proctoringManifestPath,
    required this.agentDecision,
    required this.attemptId,
    this.examStartToken = '',
    this.studentId = 'KASU/STU/2026/001',
  });

  final DemoAssessment assessment;
  final String? proctoringManifestPath;
  final String agentDecision;
  final String attemptId;
  final String examStartToken;
  final String studentId;

  @override
  State<DemoExamAttemptView> createState() => _DemoExamAttemptViewState();
}

class _DemoExamAttemptViewState extends State<DemoExamAttemptView>
    with WidgetsBindingObserver {
  final LiveProctoringEventService _events = LiveProctoringEventService(
    baseUrl: const String.fromEnvironment(
      'KSLAS_API_BASE_URL',
      defaultValue: 'http://127.0.0.1:8080',
    ),
  );

  late final DateTime _startedAt;
  late final List<DemoQuestion> _questions;
  late int _remainingSeconds;
  Timer? _timer;
  int _currentIndex = 0;
  bool _paused = false;
  bool _exitWarningShowing = false;
  bool _submitting = false;
  String _pauseMessage = '';
  final Map<String, String> _answers = <String, String>{};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startedAt = DateTime.now();
    _questions = DemoExamService.questionsFor(widget.assessment);
    _remainingSeconds = widget.assessment.durationMinutes * 60;
    _startTimer();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _events.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!widget.assessment.remoteProctored) return;

    if (state == AppLifecycleState.inactive) {
      unawaited(_sendRuntimeSessionEvent(
        eventType: 'exam_screen_focus_changed',
        severity: 'warning',
        message: 'Exam screen focus changed. Please stay on the exam screen.',
        metadata: <String, Object?>{'state': state.name},
      ));
      unawaited(_showLeaveExamWarning());
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      unawaited(_sendRuntimeSessionEvent(
        eventType: 'exam_screen_backgrounded',
        severity: 'high',
        message: 'You moved away from the exam screen. The exam will be submitted.',
        metadata: <String, Object?>{'state': state.name},
      ));
      unawaited(_submit(autoSubmitted: true, force: true));
    } else if (state == AppLifecycleState.resumed) {
      unawaited(_sendRuntimeSessionEvent(
        eventType: 'exam_screen_restored',
        severity: 'info',
        message: 'Exam screen restored. Runtime checks are continuing.',
        metadata: <String, Object?>{'state': state.name},
      ));
    }
  }

  Future<void> _sendRuntimeSessionEvent({
    required String eventType,
    required String severity,
    required String message,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) {
    return _events.send(
      LiveProctoringEvent(
        studentId: widget.studentId,
        examId: widget.assessment.id,
        attemptId: widget.attemptId,
        eventType: eventType,
        severity: severity,
        message: message,
        createdAt: DateTime.now(),
        assessmentType: widget.assessment.assessmentType,
        reviewAudience: widget.assessment.reviewAudience,
        metadata: metadata,
      ),
    );
  }

  Future<void> _showLeaveExamWarning() async {
    if (!mounted || _exitWarningShowing || _submitting || _paused) return;
    _exitWarningShowing = true;
    _timer?.cancel();

    final submitNow = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Stay on the exam screen'),
        content: const Text(
          'If you minimize, close, or move away from this exam screen, your exam will be submitted automatically.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Stay in exam'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Submit now'),
          ),
        ],
      ),
    );

    _exitWarningShowing = false;
    if (!mounted) return;
    if (submitNow == true) {
      await _submit(autoSubmitted: true, force: true);
      return;
    }
    _startTimer();
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _paused) return;
      if (_remainingSeconds <= 1) {
        _submit(autoSubmitted: true);
      } else {
        setState(() => _remainingSeconds--);
      }
    });
  }

  void _handleCriticalMonitoringEvent(String message) {
    if (!mounted) return;
    setState(() {
      _paused = true;
      _pauseMessage = message;
    });
  }

  int get _answeredCount =>
      _answers.values.where((value) => value.trim().isNotEmpty).length;

  @override
  Widget build(BuildContext context) {
    final question = _questions[_currentIndex];
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 820;
        return PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, result) {
            if (!didPop) unawaited(_showLeaveExamWarning());
          },
          child: Scaffold(
          backgroundColor: const Color(0xFFF4F7FB),
          appBar: AppBar(
            backgroundColor: Colors.white,
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            automaticallyImplyLeading: false,
            title: Text(
              widget.assessment.isStrictExam
                  ? 'Secure exam attempt'
                  : 'Assessment attempt',
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 16),
                child: _TimerPill(
                  text: _paused ? 'Paused' : _formatTime(_remainingSeconds),
                  warning: _remainingSeconds <= 300,
                  paused: _paused,
                ),
              ),
            ],
          ),
          bottomNavigationBar: compact
              ? _MobileExamActionBar(
                  canGoBack: _currentIndex > 0 && !_paused,
                  canGoNext: _currentIndex < _questions.length - 1 && !_paused,
                  canSubmit: !_paused,
                  onPrevious: () => setState(() => _currentIndex--),
                  onNext: () => setState(() => _currentIndex++),
                  onSubmit: () => _submit(autoSubmitted: false),
                )
              : null,
          body: DecoratedBox(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFFF8FAFC), Color(0xFFF1F5F9)],
              ),
            ),
            child: SafeArea(
              child: compact
                  ? _buildCompactAttempt(question)
                  : _buildWideAttempt(question),
            ),
          ),
          ),
        );
      },
    );
  }

  Widget _buildWideAttempt(DemoQuestion question) {
    return Row(
      children: [
        SizedBox(
          width: 290,
          child: _paused
              ? const _QuestionListLockedCard(compact: false)
              : _QuestionNavigator(
                  questions: _questions,
                  currentIndex: _currentIndex,
                  answers: _answers,
                  enabled: true,
                  onSelect: (index) => setState(() => _currentIndex = index),
                ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 28),
            children: [
              _CompactExamHeader(
                assessment: widget.assessment,
                answered: _answeredCount,
                total: _questions.length,
                current: _currentIndex + 1,
                remainingText: _formatTime(_remainingSeconds),
                paused: _paused,
              ),
              if (_paused) ...[
                const SizedBox(height: 12),
                _PauseBanner(message: _pauseMessage),
              ],
              const SizedBox(height: 12),
              _paused
                  ? _PausedQuestionLockCard(message: _pauseMessage)
                  : _QuestionWorkArea(
                      question: question,
                      value: _answers[question.id] ?? '',
                      enabled: true,
                      onChanged: (value) =>
                          setState(() => _answers[question.id] = value),
                      canPrevious: _currentIndex > 0,
                      canNext: _currentIndex < _questions.length - 1,
                      onPrevious: () => setState(() => _currentIndex--),
                      onNext: () => setState(() => _currentIndex++),
                      onSubmit: () => _submit(autoSubmitted: false),
                    ),
            ],
          ),
        ),
        if (widget.assessment.remoteProctored)
          SizedBox(
            width: 330,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(0, 14, 18, 18),
              children: _buildProctoringPanels(),
            ),
          ),
      ],
    );
  }

  Widget _buildCompactAttempt(DemoQuestion question) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
      children: [
        _CompactExamHeader(
          assessment: widget.assessment,
          answered: _answeredCount,
          total: _questions.length,
          current: _currentIndex + 1,
          remainingText: _formatTime(_remainingSeconds),
          paused: _paused,
          compact: true,
        ),
        const SizedBox(height: 12),
        if (_paused) ...[
          _PauseBanner(message: _pauseMessage),
          const SizedBox(height: 12),
          const _QuestionListLockedCard(compact: true),
        ] else
          _QuestionNavigator(
            questions: _questions,
            currentIndex: _currentIndex,
            answers: _answers,
            enabled: true,
            onSelect: (index) => setState(() => _currentIndex = index),
            compact: true,
          ),
        const SizedBox(height: 12),
        _paused
            ? _PausedQuestionLockCard(message: _pauseMessage)
            : _QuestionCard(
                question: question,
                value: _answers[question.id] ?? '',
                enabled: true,
                onChanged: (value) => setState(() => _answers[question.id] = value),
              ),
        if (widget.assessment.remoteProctored) ...[
          const SizedBox(height: 12),
          ..._buildProctoringPanels(compact: true),
        ],
      ],
    );
  }

  List<Widget> _buildProctoringPanels({bool compact = false}) {
    return [
      _PanelTitle(title: 'Live exam checks', compact: compact),
      SizedBox(height: compact ? 10 : 12),
      LiveExamMonitor(
        studentId: widget.studentId,
        examId: widget.assessment.id,
        attemptId: widget.attemptId,
        onCriticalEvent: _handleCriticalMonitoringEvent,
        assessmentType: widget.assessment.assessmentType,
        reviewAudience: widget.assessment.reviewAudience,
      ),
      SizedBox(height: compact ? 10 : 12),
      LiveSystemSecurityMonitor(
        studentId: widget.studentId,
        examId: widget.assessment.id,
        attemptId: widget.attemptId,
        onCriticalEvent: _handleCriticalMonitoringEvent,
        assessmentType: widget.assessment.assessmentType,
        reviewAudience: widget.assessment.reviewAudience,
      ),
      SizedBox(height: compact ? 10 : 12),
      ReviewClipSampler(
        studentId: widget.studentId,
        examId: widget.assessment.id,
        attemptId: widget.attemptId,
        examDurationSeconds: widget.assessment.durationMinutes * 60,
        assessmentType: widget.assessment.assessmentType,
        reviewAudience: widget.assessment.reviewAudience,
      ),
      SizedBox(height: compact ? 10 : 12),
      CompanionCamPanel(
        studentId: widget.studentId,
        examId: widget.assessment.id,
        attemptId: widget.attemptId,
        onCompanionLost: _handleCriticalMonitoringEvent,
        assessmentType: widget.assessment.assessmentType,
        reviewAudience: widget.assessment.reviewAudience,
      ),
      SizedBox(height: compact ? 10 : 12),
      const LiveStatusPanel(),
    ];
  }

  Future<void> _submit({
    required bool autoSubmitted,
    bool force = false,
  }) async {
    if (_submitting) return;
    if (_paused && !force) return;
    _submitting = true;
    _timer?.cancel();
    if (!autoSubmitted && mounted) {
      final unanswered = _questions.length - _answeredCount;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Submit now?'),
          content: Text(
            unanswered == 0
                ? 'All questions have an answer. Submit your work now?'
                : '$unanswered question${unanswered == 1 ? '' : 's'} still need${unanswered == 1 ? 's' : ''} an answer. You can continue writing or submit now.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Continue writing'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Submit'),
            ),
          ],
        ),
      );
      if (confirmed != true) {
        _submitting = false;
        _startTimer();
        return;
      }
    }

    final result = _score();
    await _sendSubmissionEvent(result, autoSubmitted: autoSubmitted);
    if (!mounted) return;
    Navigator.of(context).pop(result);
  }

  Future<void> _sendSubmissionEvent(
    DemoExamResult result, {
    required bool autoSubmitted,
  }) {
    return _events.send(
      LiveProctoringEvent(
        studentId: widget.studentId,
        examId: widget.assessment.id,
        attemptId: widget.attemptId,
        eventType: autoSubmitted ? 'assessment_auto_submitted' : 'assessment_submitted',
        severity: 'info',
        message: widget.assessment.sendsEventsToLecturer
            ? 'Graded assessment submitted for lecturer review.'
            : 'Exam attempt submitted for invigilator review.',
        createdAt: DateTime.now(),
        assessmentType: widget.assessment.assessmentType,
        reviewAudience: widget.assessment.reviewAudience,
        metadata: <String, Object?>{
          'answered_count': _answeredCount,
          'question_count': _questions.length,
          'total_marks': result.totalMarks,
          'scored_marks': result.scoredMarks,
          'percent': result.percent,
          'auto_submitted': autoSubmitted,
          'recipient_role': widget.assessment.reviewAudience,
          'has_exam_start_token': widget.examStartToken.trim().isNotEmpty,
        },
      ),
    );
  }

  DemoExamResult _score() {
    var total = 0;
    var scored = 0;
    for (final question in _questions) {
      total += question.marks;
      final answer = (_answers[question.id] ?? '').trim().toLowerCase();
      if (answer.isEmpty) continue;
      if (question.section == DemoExamSection.objective ||
          question.section == DemoExamSection.fillBlank) {
        if (answer == question.answer?.trim().toLowerCase()) scored += question.marks;
      } else {
        final hits = question.keywords
            .where((keyword) => answer.contains(keyword.toLowerCase()))
            .length;
        scored += math.min(question.marks, hits);
      }
    }
    return DemoExamResult(
      assessment: widget.assessment,
      totalMarks: total,
      scoredMarks: scored,
      startedAt: _startedAt,
      endedAt: DateTime.now(),
      proctoringManifestPath: widget.proctoringManifestPath,
      agentDecision: widget.agentDecision,
    );
  }

  String _formatTime(int seconds) {
    final minutes = seconds ~/ 60;
    final secs = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }
}

class _CompactExamHeader extends StatelessWidget {
  const _CompactExamHeader({
    required this.assessment,
    required this.answered,
    required this.total,
    required this.current,
    required this.remainingText,
    required this.paused,
    this.compact = false,
  });

  final DemoAssessment assessment;
  final int answered;
  final int total;
  final int current;
  final String remainingText;
  final bool paused;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final progress = total == 0 ? 0.0 : answered / total;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 14 : 16,
        vertical: compact ? 12 : 13,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(color: Color(0x120F172A), blurRadius: 16, offset: Offset(0, 8)),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 620;
          final title = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 7,
                runSpacing: 7,
                children: [
                  _DarkTag(assessment.course.code),
                  _DarkTag(paused ? 'Paused' : assessment.remoteProctored ? 'Checks active' : 'Standard access'),
                ],
              ),
              const SizedBox(height: 9),
              Text(
                assessment.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: compact ? 20 : 23,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                '${assessment.course.title} • Lecturer: ${assessment.course.lecturer}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Color(0xFFCBD5E1), fontSize: 13),
              ),
            ],
          );
          final stats = Container(
            width: wide ? 220 : double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0x12FFFFFF),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0x24FFFFFF)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _HeaderStat(label: 'Time left', value: remainingText),
                const SizedBox(height: 5),
                _HeaderStat(label: 'Question', value: '$current of $total'),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: progress.clamp(0.0, 1.0),
                    minHeight: 7,
                    backgroundColor: const Color(0x24FFFFFF),
                    color: const Color(0xFF60A5FA),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '$answered of $total answered',
                  style: const TextStyle(
                    color: Color(0xFFCBD5E1),
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          );
          if (!wide) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [title, const SizedBox(height: 12), stats],
            );
          }
          return Row(children: [Expanded(child: title), const SizedBox(width: 14), stats]);
        },
      ),
    );
  }
}

class _HeaderStat extends StatelessWidget {
  const _HeaderStat({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12, fontWeight: FontWeight.w700),
          ),
        ),
        Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
      ],
    );
  }
}

class _QuestionWorkArea extends StatelessWidget {
  const _QuestionWorkArea({
    required this.question,
    required this.value,
    required this.enabled,
    required this.onChanged,
    required this.canPrevious,
    required this.canNext,
    required this.onPrevious,
    required this.onNext,
    required this.onSubmit,
  });

  final DemoQuestion question;
  final String value;
  final bool enabled;
  final ValueChanged<String> onChanged;
  final bool canPrevious;
  final bool canNext;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    if (!enabled) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _QuestionCard(question: question, value: value, enabled: enabled, onChanged: onChanged),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Row(
            children: [
              OutlinedButton.icon(
                onPressed: canPrevious ? onPrevious : null,
                icon: const Icon(Icons.chevron_left),
                label: const Text('Previous'),
              ),
              const SizedBox(width: 10),
              FilledButton.icon(
                onPressed: canNext ? onNext : null,
                icon: const Icon(Icons.chevron_right),
                label: const Text('Next'),
              ),
              const Spacer(),
              FilledButton.icon(
                onPressed: onSubmit,
                icon: const Icon(Icons.upload_file),
                label: const Text('Submit'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _QuestionCard extends StatelessWidget {
  const _QuestionCard({
    required this.question,
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final DemoQuestion question;
  final String value;
  final bool enabled;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: const [BoxShadow(color: Color(0x080F172A), blurRadius: 18, offset: Offset(0, 8))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _Pill(question.section.label),
              _Pill('${question.marks} mark${question.marks == 1 ? '' : 's'}'),
            ],
          ),
          const SizedBox(height: 15),
          Text(
            question.prompt,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 18),
          if (question.options.isNotEmpty)
            ...question.options.map((option) {
              final selected = value == option;
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: InkWell(
                  onTap: enabled ? () => onChanged(option) : null,
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: selected ? const Color(0xFF2563EB) : const Color(0xFFE2E8F0),
                      ),
                      color: selected ? const Color(0xFFEFF6FF) : const Color(0xFFF8FAFC),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                          color: selected ? const Color(0xFF2563EB) : const Color(0xFF64748B),
                        ),
                        const SizedBox(width: 10),
                        Expanded(child: Text(option, style: const TextStyle(fontWeight: FontWeight.w700))),
                      ],
                    ),
                  ),
                ),
              );
            })
          else
            TextFormField(
              key: ValueKey(question.id),
              enabled: enabled,
              initialValue: value,
              onChanged: onChanged,
              minLines: question.section == DemoExamSection.theory ? 8 : 2,
              maxLines: question.section == DemoExamSection.theory ? 12 : 4,
              decoration: InputDecoration(
                filled: true,
                fillColor: const Color(0xFFF8FAFC),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                hintText: question.section == DemoExamSection.theory
                    ? 'Write your explanation here'
                    : 'Type your answer',
              ),
            ),
        ],
      ),
    );
  }
}

class _QuestionNavigator extends StatelessWidget {
  const _QuestionNavigator({
    required this.questions,
    required this.currentIndex,
    required this.answers,
    required this.enabled,
    required this.onSelect,
    this.compact = false,
  });

  final List<DemoQuestion> questions;
  final int currentIndex;
  final Map<String, String> answers;
  final bool enabled;
  final ValueChanged<int> onSelect;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Questions', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
            const Spacer(),
            Text('${currentIndex + 1}/${questions.length}', style: const TextStyle(color: Color(0xFF475569), fontWeight: FontWeight.w900)),
          ],
        ),
        const SizedBox(height: 12),
        compact
            ? SizedBox(
                height: 54,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: questions.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, index) => _QuestionNumberButton(
                    number: index + 1,
                    selected: index == currentIndex,
                    answered: answers[questions[index].id]?.trim().isNotEmpty ?? false,
                    enabled: enabled,
                    onTap: () => onSelect(index),
                  ),
                ),
              )
            : Expanded(
                child: GridView.builder(
                  itemCount: questions.length,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 4,
                    mainAxisSpacing: 9,
                    crossAxisSpacing: 9,
                  ),
                  itemBuilder: (context, index) => _QuestionNumberButton(
                    number: index + 1,
                    selected: index == currentIndex,
                    answered: answers[questions[index].id]?.trim().isNotEmpty ?? false,
                    enabled: enabled,
                    onTap: () => onSelect(index),
                  ),
                ),
              ),
      ],
    );
    return Container(
      height: compact ? null : double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: compact ? BorderRadius.circular(18) : BorderRadius.zero,
        border: compact ? Border.all(color: const Color(0xFFE2E8F0)) : null,
      ),
      child: content,
    );
  }
}

class _QuestionNumberButton extends StatelessWidget {
  const _QuestionNumberButton({
    required this.number,
    required this.selected,
    required this.answered,
    required this.enabled,
    required this.onTap,
  });

  final int number;
  final bool selected;
  final bool answered;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected
        ? const Color(0xFF2563EB)
        : answered
            ? const Color(0xFF16A34A)
            : const Color(0xFF64748B);
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: 54,
        height: 54,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected
              ? const Color(0xFF2563EB)
              : answered
                  ? const Color(0xFFF0FDF4)
                  : const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: selected ? const Color(0xFF2563EB) : color.withValues(alpha: 0.25)),
        ),
        child: Text(
          '$number',
          style: TextStyle(color: selected ? Colors.white : const Color(0xFF0F172A), fontWeight: FontWeight.w900),
        ),
      ),
    );
  }
}

class _TimerPill extends StatelessWidget {
  const _TimerPill({required this.text, required this.warning, required this.paused});

  final String text;
  final bool warning;
  final bool paused;

  @override
  Widget build(BuildContext context) {
    final color = paused
        ? const Color(0xFFE11D48)
        : warning
            ? const Color(0xFFB45309)
            : const Color(0xFF2563EB);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.30)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(paused ? Icons.pause_circle : Icons.timer_outlined, size: 18, color: color),
          const SizedBox(width: 7),
          Text(text, style: TextStyle(color: color, fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }
}

class _PauseBanner extends StatelessWidget {
  const _PauseBanner({required this.message});
  final String message;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFE4E6),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFFB7185)),
      ),
      child: Row(
        children: [
          const Icon(Icons.pause_circle_filled, color: Color(0xFFE11D48)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Please wait: $message',
              style: const TextStyle(color: Color(0xFF9F1239), fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }
}

class _PausedQuestionLockCard extends StatelessWidget {
  const _PausedQuestionLockCard({required this.message});
  final String message;
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFFECACA)),
      ),
      child: Column(
        children: [
          const Icon(Icons.visibility_off_outlined, color: Color(0xFFE11D48), size: 44),
          const SizedBox(height: 12),
          Text(
            'Questions hidden during review',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: const Color(0xFF9F1239),
                ),
          ),
          const SizedBox(height: 8),
          const Text(
            'The exam content is temporarily hidden while the monitoring check is active. Please wait for an authorized officer to review and resume the attempt.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Color(0xFF475569), fontWeight: FontWeight.w600),
          ),
          if (message.trim().isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFF9F1239), fontWeight: FontWeight.w800),
            ),
          ],
        ],
      ),
    );
  }
}

class _QuestionListLockedCard extends StatelessWidget {
  const _QuestionListLockedCard({required this.compact});
  final bool compact;
  @override
  Widget build(BuildContext context) {
    return Container(
      height: compact ? null : double.infinity,
      padding: const EdgeInsets.all(16),
      color: Colors.white,
      child: Column(
        mainAxisSize: compact ? MainAxisSize.min : MainAxisSize.max,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          Text('Questions', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
          SizedBox(height: 12),
          _LockedNotice(),
        ],
      ),
    );
  }
}

class _LockedNotice extends StatelessWidget {
  const _LockedNotice();
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: const Row(
        children: [
          Icon(Icons.lock_outline, color: Color(0xFF64748B)),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'Question list hidden while review is active.',
              style: TextStyle(color: Color(0xFF475569), fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

class _PanelTitle extends StatelessWidget {
  const _PanelTitle({required this.title, required this.compact});
  final String title;
  final bool compact;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          const Icon(Icons.health_and_safety_outlined, color: Color(0xFF2563EB)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill(this.text);
  final String text;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFBFDBFE)),
      ),
      child: Text(text, style: const TextStyle(color: Color(0xFF1E3A8A), fontWeight: FontWeight.w800)),
    );
  }
}

class _DarkTag extends StatelessWidget {
  const _DarkTag(this.text);
  final String text;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFF1F2937),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFF334155)),
      ),
      child: Text(
        text,
        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12),
      ),
    );
  }
}

class _MobileExamActionBar extends StatelessWidget {
  const _MobileExamActionBar({
    required this.canGoBack,
    required this.canGoNext,
    required this.canSubmit,
    required this.onPrevious,
    required this.onNext,
    required this.onSubmit,
  });

  final bool canGoBack;
  final bool canGoNext;
  final bool canSubmit;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: Color(0xFFE2E8F0))),
          boxShadow: [BoxShadow(color: Color(0x140F172A), blurRadius: 18, offset: Offset(0, -8))],
        ),
        child: Row(
          children: [
            IconButton.outlined(
              onPressed: canGoBack ? onPrevious : null,
              icon: const Icon(Icons.chevron_left),
              tooltip: 'Previous question',
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton.icon(
                onPressed: canGoNext ? onNext : null,
                icon: const Icon(Icons.chevron_right),
                label: const Text('Next'),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filledTonal(
              onPressed: canSubmit ? onSubmit : null,
              icon: const Icon(Icons.upload_file),
              tooltip: 'Submit',
            ),
          ],
        ),
      ),
    );
  }
}

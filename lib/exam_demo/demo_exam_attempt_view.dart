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

class _DemoExamAttemptViewState extends State<DemoExamAttemptView> {
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
  String _pauseMessage = '';
  final Map<String, String> _answers = <String, String>{};

  @override
  void initState() {
    super.initState();
    _startedAt = DateTime.now();
    _questions = DemoExamService.questionsFor(widget.assessment);
    _remainingSeconds = widget.assessment.durationMinutes * 60;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _paused) return;
      if (_remainingSeconds <= 1) {
        _submit(autoSubmitted: true);
      } else {
        setState(() => _remainingSeconds--);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _events.dispose();
    super.dispose();
  }

  void _handleCriticalMonitoringEvent(String message) {
    if (!mounted) return;
    setState(() {
      _paused = true;
      _pauseMessage = message;
    });
  }

  @override
  Widget build(BuildContext context) {
    final question = _questions[_currentIndex];
    final answered = _answers.length;
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 760;
        return Scaffold(
          backgroundColor: const Color(0xFFF5F7FB),
          appBar: AppBar(
            title: Text(
              widget.assessment.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            automaticallyImplyLeading: false,
            actions: [
              Padding(
                padding: EdgeInsets.only(right: compact ? 12 : 16),
                child: Center(
                  child: Text(
                    _paused ? 'PAUSED' : _formatTime(_remainingSeconds),
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
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
          body: SafeArea(
            child: compact
                ? _buildCompactAttempt(question, answered)
                : _buildWideAttempt(question, answered),
          ),
        );
      },
    );
  }

  Widget _buildWideAttempt(DemoQuestion question, int answered) {
    return Row(
      children: [
        SizedBox(
          width: 270,
          child: _QuestionNavigator(
            questions: _questions,
            currentIndex: _currentIndex,
            answers: _answers,
            enabled: !_paused,
            onSelect: (index) => setState(() => _currentIndex = index),
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(18),
            children: [
              if (_paused) ...[
                _PauseBanner(message: _pauseMessage),
                const SizedBox(height: 14),
              ],
              _ExamStatusBar(
                assessment: widget.assessment,
                answered: answered,
                total: _questions.length,
                paused: _paused,
              ),
              const SizedBox(height: 14),
              _buildQuestionWorkArea(question, showActions: true),
            ],
          ),
        ),
        if (widget.assessment.remoteProctored)
          SizedBox(
            width: 320,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(0, 18, 18, 18),
              child: ListView(children: _buildProctoringPanels()),
            ),
          ),
      ],
    );
  }

  Widget _buildCompactAttempt(DemoQuestion question, int answered) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 96),
      children: [
        if (_paused) ...[
          _PauseBanner(message: _pauseMessage),
          const SizedBox(height: 12),
        ],
        _QuestionNavigator(
          questions: _questions,
          currentIndex: _currentIndex,
          answers: _answers,
          enabled: !_paused,
          onSelect: (index) => setState(() => _currentIndex = index),
          compact: true,
        ),
        const SizedBox(height: 12),
        _ExamStatusBar(
          assessment: widget.assessment,
          answered: answered,
          total: _questions.length,
          paused: _paused,
          compact: true,
        ),
        const SizedBox(height: 12),
        _buildQuestionWorkArea(question, showActions: false),
        if (widget.assessment.remoteProctored) ...[
          const SizedBox(height: 12),
          ..._buildProctoringPanels(compact: true),
        ],
      ],
    );
  }

  Widget _buildQuestionWorkArea(
    DemoQuestion question, {
    required bool showActions,
  }) {
    return AbsorbPointer(
      absorbing: _paused,
      child: Opacity(
        opacity: _paused ? 0.55 : 1,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _QuestionCard(
              question: question,
              value: _answers[question.id] ?? '',
              enabled: !_paused,
              onChanged: (value) =>
                  setState(() => _answers[question.id] = value),
            ),
            if (showActions) ...[
              const SizedBox(height: 14),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                alignment: WrapAlignment.spaceBetween,
                children: [
                  OutlinedButton.icon(
                    onPressed: _currentIndex == 0 || _paused
                        ? null
                        : () => setState(() => _currentIndex--),
                    icon: const Icon(Icons.chevron_left),
                    label: const Text('Previous'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _currentIndex == _questions.length - 1 || _paused
                        ? null
                        : () => setState(() => _currentIndex++),
                    icon: const Icon(Icons.chevron_right),
                    label: const Text('Next'),
                  ),
                  FilledButton.icon(
                    onPressed: _paused
                        ? null
                        : () => _submit(autoSubmitted: false),
                    icon: const Icon(Icons.upload_file),
                    label: const Text('Submit exam'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  List<Widget> _buildProctoringPanels({bool compact = false}) {
    return [
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

  Future<void> _submit({required bool autoSubmitted}) async {
    if (_paused) return;
    _timer?.cancel();
    if (!autoSubmitted && mounted) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Submit exam?'),
          content: Text(
            'You answered ${_answers.length} of ${_questions.length} questions.',
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
        _timer = Timer.periodic(const Duration(seconds: 1), (_) {
          if (!mounted || _paused) return;
          if (_remainingSeconds <= 1) {
            _submit(autoSubmitted: true);
          } else {
            setState(() => _remainingSeconds--);
          }
        });
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
        eventType: autoSubmitted
            ? 'assessment_auto_submitted'
            : 'assessment_submitted',
        severity: 'info',
        message: widget.assessment.sendsEventsToLecturer
            ? 'Graded assessment submitted for lecturer review.'
            : 'Exam attempt submitted for invigilator review.',
        createdAt: DateTime.now(),
        assessmentType: widget.assessment.assessmentType,
        reviewAudience: widget.assessment.reviewAudience,
        metadata: <String, Object?>{
          'answered_count': _answers.length,
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
        if (answer == question.answer?.trim().toLowerCase()) {
          scored += question.marks;
        }
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

class _PauseBanner extends StatelessWidget {
  const _PauseBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFE4E6),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFFB7185)),
      ),
      child: Row(
        children: [
          const Icon(Icons.pause_circle_filled, color: Color(0xFFE11D48)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Exam paused: $message',
              style: const TextStyle(
                color: Color(0xFF9F1239),
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ExamStatusBar extends StatelessWidget {
  const _ExamStatusBar({
    required this.assessment,
    required this.answered,
    required this.total,
    required this.paused,
    this.compact = false,
  });

  final DemoAssessment assessment;
  final int answered;
  final int total;
  final bool paused;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Wrap(
        spacing: 10,
        runSpacing: compact ? 8 : 10,
        children: [
          _Pill('${assessment.course.code} ${assessment.kind}'),
          _Pill('$answered/$total answered'),
          _Pill(
            paused
                ? 'Paused for check'
                : assessment.remoteProctored
                ? 'Exam check active'
                : 'Standard access',
          ),
          if (assessment.remoteProctored)
            _Pill(compact ? 'Check active' : 'Sound check active'),
          if (assessment.remoteProctored && !compact)
            const _Pill('Device check active'),
          if (assessment.remoteProctored && !compact)
            const _Pill('Short camera checks active'),
          _Pill(assessment.graded ? 'Graded' : 'Practice'),
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
    if (compact) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'Questions',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const Spacer(),
                Text(
                  '${currentIndex + 1}/${questions.length}',
                  style: const TextStyle(
                    color: Color(0xFF475569),
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 54,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: questions.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final selected = index == currentIndex;
                  final answered =
                      answers[questions[index].id]?.isNotEmpty ?? false;
                  return _QuestionNumberButton(
                    number: index + 1,
                    selected: selected,
                    answered: answered,
                    enabled: enabled,
                    onTap: () => onSelect(index),
                  );
                },
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Questions',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: GridView.builder(
              itemCount: questions.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 4,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
              ),
              itemBuilder: (context, index) {
                final selected = index == currentIndex;
                final answered =
                    answers[questions[index].id]?.isNotEmpty ?? false;
                return _QuestionNumberButton(
                  number: index + 1,
                  selected: selected,
                  answered: answered,
                  enabled: enabled,
                  onTap: () => onSelect(index),
                );
              },
            ),
          ),
        ],
      ),
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
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 54,
        height: 54,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected
              ? const Color(0xFF1D4ED8)
              : answered
              ? const Color(0xFFDCFCE7)
              : const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(8),
          border: selected
              ? null
              : Border.all(
                  color: answered
                      ? const Color(0xFF86EFAC)
                      : const Color(0xFFE2E8F0),
                ),
        ),
        child: Text(
          '$number',
          style: TextStyle(
            color: selected ? Colors.white : const Color(0xFF0F172A),
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
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
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${question.section.label} - ${question.marks} mark${question.marks == 1 ? '' : 's'}',
            style: const TextStyle(
              color: Color(0xFF1D4ED8),
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            question.prompt,
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 16),
          if (question.options.isNotEmpty)
            ...question.options.map(
              (option) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: InkWell(
                  onTap: enabled ? () => onChanged(option) : null,
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: value == option
                            ? const Color(0xFF1D4ED8)
                            : const Color(0xFFE2E8F0),
                      ),
                      color: value == option
                          ? const Color(0xFFEFF6FF)
                          : Colors.white,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          value == option
                              ? Icons.radio_button_checked
                              : Icons.radio_button_unchecked,
                          color: value == option
                              ? const Color(0xFF1D4ED8)
                              : const Color(0xFF64748B),
                        ),
                        const SizedBox(width: 10),
                        Expanded(child: Text(option)),
                      ],
                    ),
                  ),
                ),
              ),
            )
          else
            TextField(
              enabled: enabled,
              controller: TextEditingController(text: value)
                ..selection = TextSelection.collapsed(offset: value.length),
              onChanged: onChanged,
              minLines: question.section == DemoExamSection.theory ? 7 : 1,
              maxLines: question.section == DemoExamSection.theory ? 10 : 2,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'Type your answer',
              ),
            ),
        ],
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
          boxShadow: [
            BoxShadow(
              color: Color(0x140F172A),
              blurRadius: 18,
              offset: Offset(0, -8),
            ),
          ],
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
              tooltip: 'Submit exam',
            ),
          ],
        ),
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
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Color(0xFF1E3A8A),
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

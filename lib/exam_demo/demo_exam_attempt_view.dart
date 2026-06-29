import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../proctoring_demo/companion_cam_panel.dart';
import '../proctoring_demo/live_exam_monitor.dart';
import '../proctoring_demo/live_proctoring_event_service.dart';
import '../proctoring_demo/live_status_panel.dart';
import '../proctoring_demo/live_system_security_monitor.dart';
import '../proctoring_demo/proctoring_risk_policy.dart';
import '../proctoring_demo/review_clip_sampler.dart';
import 'assessment_device_gate.dart';
import 'assessment_monitoring_profile.dart';
import 'demo_exam_models.dart';
import 'demo_exam_result_view.dart';
import 'demo_exam_service.dart';

const Color _brand = Color(0xFF0F4C81);
const Color _brandDark = Color(0xFF0B1220);
const Color _pageBg = Color(0xFFF4F7FB);
const Color _surface = Colors.white;
const Color _surfaceSoft = Color(0xFFF8FAFC);
const Color _line = Color(0xFFE2E8F0);
const Color _muted = Color(0xFF64748B);
const Color _success = Color(0xFF16A34A);
const Color _warning = Color(0xFFF59E0B);
const Color _danger = Color(0xFFDC2626);

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
  static const bool _allowExamOverride = bool.fromEnvironment(
    'KSLAS_ALLOW_EXAM_OVERRIDE',
    defaultValue: false,
  );
  static const bool _allowMonitoringReviewOverride = bool.fromEnvironment(
    'KSLAS_ALLOW_MONITORING_REVIEW_OVERRIDE',
    defaultValue: false,
  );
  static const bool _monitoringWarnOnly =
      _allowExamOverride || _allowMonitoringReviewOverride;

  final LiveProctoringEventService _events = LiveProctoringEventService(
    baseUrl: const String.fromEnvironment(
      'KSLAS_API_BASE_URL',
      defaultValue: 'http://127.0.0.1:8080',
    ),
  );
  final Map<String, DateTime> _lastAttemptEventAt = <String, DateTime>{};
  final Map<String, String> _answers = <String, String>{};

  late final DateTime _startedAt;
  late final List<DemoQuestion> _questions;
  late final AssessmentMonitoringProfile _monitoringProfile;
  late int _remainingSeconds;
  Timer? _timer;
  int _currentIndex = 0;
  bool _paused = false;
  bool _exitWarningShowing = false;
  bool _submitting = false;
  String _pauseMessage = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startedAt = DateTime.now();
    _questions = DemoExamService.questionsFor(widget.assessment);
    _monitoringProfile = AssessmentMonitoringProfile.forAssessment(widget.assessment);
    _remainingSeconds = widget.assessment.durationMinutes * 60;
    _startTimer();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_monitoringProfile.showsLiveMonitor) {
        unawaited(
          _sendRuntimeSessionEvent(
            eventType: 'assessment_started',
            severity: 'info',
            message: 'Assessment started.',
          ),
        );
      }
    });
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
    if (!_monitoringProfile.showsLiveMonitor) return;

    if (state == AppLifecycleState.inactive) {
      unawaited(
        _sendRuntimeSessionEvent(
          eventType: 'exam_screen_focus_changed',
          severity: 'warning',
          message: 'Please stay on the assessment screen.',
          metadata: <String, Object?>{'state': state.name},
        ),
      );
      unawaited(_showLeaveExamWarning());
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      final autoSubmit = _monitoringProfile.autoSubmitWhenBackgrounded;
      unawaited(
        _sendRuntimeSessionEvent(
          eventType: 'exam_screen_backgrounded',
          severity: autoSubmit ? 'high' : 'warning',
          message: autoSubmit
              ? 'You moved away from the assessment screen. The work will be submitted.'
              : 'Please return to the assessment screen to continue.',
          metadata: <String, Object?>{
            'state': state.name,
            'auto_submit_when_backgrounded': autoSubmit,
          },
        ),
      );
      if (autoSubmit) {
        unawaited(_submit(autoSubmitted: true, force: true));
      }
    } else if (state == AppLifecycleState.resumed) {
      unawaited(
        _sendRuntimeSessionEvent(
          eventType: 'exam_screen_restored',
          severity: 'info',
          message: 'Assessment screen restored.',
          metadata: <String, Object?>{'state': state.name},
        ),
      );
    }
  }

  int get _answeredCount =>
      _answers.values.where((value) => value.trim().isNotEmpty).length;

  bool get _isLastQuestion => _currentIndex == _questions.length - 1;
  bool get _isFirstQuestion => _currentIndex == 0;

  @override
  Widget build(BuildContext context) {
    final question = _questions[_currentIndex];
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 900;
        return AssessmentDeviceGate(
          assessment: widget.assessment,
          child: PopScope(
            canPop: false,
            onPopInvokedWithResult: (didPop, result) {
              if (!didPop) unawaited(_showLeaveExamWarning());
            },
            child: Scaffold(
              backgroundColor: _pageBg,
              appBar: AppBar(
                backgroundColor: Colors.white,
                surfaceTintColor: Colors.transparent,
                elevation: 0,
                automaticallyImplyLeading: false,
                titleSpacing: 20,
                title: _ExamAppTitle(assessment: widget.assessment),
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
                bottom: const PreferredSize(
                  preferredSize: Size.fromHeight(1),
                  child: Divider(height: 1, color: _line),
                ),
              ),
              bottomNavigationBar: compact
                  ? _MobileExamActionBar(
                      canGoBack: !_isFirstQuestion && !_paused && !_submitting,
                      canGoNext: !_isLastQuestion && !_paused && !_submitting,
                      canSubmit: !_paused && !_submitting,
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
                    colors: [Color(0xFFF8FAFC), Color(0xFFEFF4FA)],
                  ),
                ),
                child: SafeArea(
                  child: compact
                      ? _buildCompactAttempt(question)
                      : _buildWideAttempt(question),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildWideAttempt(DemoQuestion question) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: 270,
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
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 34),
            children: [
              _ExamProgressHeader(
                assessment: widget.assessment,
                monitoringLabel: _friendlyModeLabel,
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
              const SizedBox(height: 14),
              _paused
                  ? _PausedQuestionLockCard(message: _pauseMessage)
                  : _QuestionWorkArea(
                      question: question,
                      value: _answers[question.id] ?? '',
                      enabled: true,
                      onChanged: (value) =>
                          setState(() => _answers[question.id] = value),
                      canPrevious: !_isFirstQuestion,
                      canNext: !_isLastQuestion,
                      onPrevious: () => setState(() => _currentIndex--),
                      onNext: () => setState(() => _currentIndex++),
                      onSubmit: _submitting
                          ? null
                          : () => _submit(autoSubmitted: false),
                      submitting: _submitting,
                    ),
            ],
          ),
        ),
        SizedBox(
          width: 300,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(0, 16, 18, 18),
            children: [
              _ExamStatusPanel(
                assessment: widget.assessment,
                profile: _monitoringProfile,
                paused: _paused,
                answered: _answeredCount,
                total: _questions.length,
              ),
              if (_monitoringProfile.showsLiveMonitor)
                _HiddenMonitoringRuntime(child: Column(children: _buildRuntimePanels())),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCompactAttempt(DemoQuestion question) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 100),
      children: [
        _ExamProgressHeader(
          assessment: widget.assessment,
          monitoringLabel: _friendlyModeLabel,
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
                onChanged: (value) =>
                    setState(() => _answers[question.id] = value),
              ),
        const SizedBox(height: 12),
        _ExamStatusPanel(
          assessment: widget.assessment,
          profile: _monitoringProfile,
          paused: _paused,
          answered: _answeredCount,
          total: _questions.length,
          compact: true,
        ),
        if (_monitoringProfile.showsLiveMonitor)
          _HiddenMonitoringRuntime(child: Column(children: _buildRuntimePanels())),
      ],
    );
  }

  List<Widget> _buildRuntimePanels() {
    final panels = <Widget>[];
    if (_monitoringProfile.showsLiveMonitor) {
      panels.add(
        LiveExamMonitor(
          studentId: widget.studentId,
          examId: widget.assessment.id,
          attemptId: widget.attemptId,
          onCriticalEvent: _handleCriticalMonitoringEvent,
          assessmentType: widget.assessment.assessmentType,
          reviewAudience: _monitoringProfile.reviewAudience,
        ),
      );
    }
    if (_monitoringProfile.usesSystemSecurityPanel) {
      panels.add(
        LiveSystemSecurityMonitor(
          studentId: widget.studentId,
          examId: widget.assessment.id,
          attemptId: widget.attemptId,
          onCriticalEvent: _handleCriticalMonitoringEvent,
          assessmentType: widget.assessment.assessmentType,
          reviewAudience: _monitoringProfile.reviewAudience,
        ),
      );
    }
    if (_monitoringProfile.usesReviewClipSampler) {
      panels.add(
        ReviewClipSampler(
          studentId: widget.studentId,
          examId: widget.assessment.id,
          attemptId: widget.attemptId,
          examDurationSeconds: widget.assessment.durationMinutes * 60,
          assessmentType: widget.assessment.assessmentType,
          reviewAudience: _monitoringProfile.reviewAudience,
        ),
      );
    }
    if (_monitoringProfile.usesCompanionCamera) {
      panels.add(
        CompanionCamPanel(
          studentId: widget.studentId,
          examId: widget.assessment.id,
          attemptId: widget.attemptId,
          onCompanionLost: _handleCriticalMonitoringEvent,
          assessmentType: widget.assessment.assessmentType,
          reviewAudience: _monitoringProfile.reviewAudience,
        ),
      );
    }
    if (_monitoringProfile.mode == AssessmentMonitoringMode.strictExam) {
      panels.add(const LiveStatusPanel());
    }
    return panels;
  }

  Future<void> _sendRuntimeSessionEvent({
    required String eventType,
    required String severity,
    required String message,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) async {
    if (!_shouldSendAttemptEvent(eventType)) return;
    final riskDecision = ProctoringRiskPolicy.decisionFor(eventType);
    final effectiveSeverity = riskDecision.points > 0
        ? ProctoringRiskPolicy.severityForPoints(riskDecision.points)
        : severity;
    final enrichedMetadata = <String, Object?>{
      ...metadata,
      'risk_policy_version': ProctoringRiskPolicy.version,
      'risk_points': riskDecision.points,
      'risk_level': riskDecision.level,
      'should_pause': riskDecision.shouldPause,
      'original_severity': severity,
      'effective_severity': effectiveSeverity,
      'source_component': 'demo_exam_attempt_view',
      'assessment_monitoring_profile': _monitoringProfile.toJson(),
    };

    await _events.send(
      LiveProctoringEvent(
        studentId: widget.studentId,
        examId: widget.assessment.id,
        attemptId: widget.attemptId,
        eventType: eventType,
        severity: effectiveSeverity,
        message: message,
        createdAt: DateTime.now(),
        assessmentType: widget.assessment.assessmentType,
        reviewAudience: widget.assessment.reviewAudience,
        metadata: enrichedMetadata,
      ),
    );
  }

  bool _shouldSendAttemptEvent(String eventType) {
    final now = DateTime.now();
    final last = _lastAttemptEventAt[eventType];
    if (last != null && now.difference(last).inSeconds < 15) return false;
    _lastAttemptEventAt[eventType] = now;
    return true;
  }

  Future<void> _showLeaveExamWarning() async {
    if (!mounted || _exitWarningShowing || _submitting || _paused) return;
    if (!_monitoringProfile.autoSubmitWhenBackgrounded) return;
    _exitWarningShowing = true;
    _timer?.cancel();

    final submitNow = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Stay on the assessment screen'),
        content: const Text(
          'If you minimize, close, or move away from this screen, your work may be submitted automatically.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Continue writing'),
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
    if (!_monitoringProfile.pauseOnCriticalMonitoringEvent) return;
    if (_monitoringWarnOnly) return;
    if (!mounted) return;
    setState(() {
      _paused = true;
      _pauseMessage = _studentFriendlyMessage(message);
    });
  }

  Future<void> _submit({
    required bool autoSubmitted,
    bool force = false,
  }) async {
    if (_submitting) return;
    if (_paused && !force) return;
    if (mounted) {
      setState(() => _submitting = true);
    } else {
      _submitting = true;
    }
    _timer?.cancel();

    if (!autoSubmitted && mounted) {
      final unanswered = _questions.length - _answeredCount;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Submit assessment?'),
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
        if (mounted) {
          setState(() => _submitting = false);
        } else {
          _submitting = false;
        }
        _startTimer();
        return;
      }
    }

    final result = _score();
    unawaited(
      _sendSubmissionEvent(result, autoSubmitted: autoSubmitted)
          .timeout(const Duration(seconds: 3))
          .catchError((_) {}),
    );
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => DemoExamResultView(result: result),
      ),
    );
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
            ? 'Assessment submitted for lecturer review.'
            : 'Assessment submitted for review.',
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

  String get _friendlyModeLabel {
    switch (_monitoringProfile.mode) {
      case AssessmentMonitoringMode.strictExam:
        return 'Exam mode active';
      case AssessmentMonitoringMode.gradedLight:
        return 'Assessment checks active';
      case AssessmentMonitoringMode.standardAccess:
        return 'Standard access';
    }
  }

  String _formatTime(int seconds) {
    final minutes = seconds ~/ 60;
    final secs = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  String _studentFriendlyMessage(String message) {
    final trimmed = message.trim();
    if (trimmed.isEmpty) return 'Your assessment needs attention before you continue.';
    return trimmed
        .replaceAll('proctoring', 'exam check')
        .replaceAll('Proctoring', 'Exam check')
        .replaceAll('risk', 'attention')
        .replaceAll('Risk', 'Attention')
        .replaceAll('violation', 'exam rule alert')
        .replaceAll('Violation', 'Exam rule alert')
        .replaceAll('backend', 'system')
        .replaceAll('Backend', 'System');
  }
}

class _ExamAppTitle extends StatelessWidget {
  const _ExamAppTitle({required this.assessment});

  final DemoAssessment assessment;

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
            color: _brand,
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(Icons.edit_document, color: Colors.white, size: 19),
        ),
        const SizedBox(width: 10),
        Text(
          assessment.isStrictExam ? 'Exam writing' : 'Assessment writing',
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
      ],
    );
  }
}

class _TimerPill extends StatelessWidget {
  const _TimerPill({
    required this.text,
    required this.warning,
    required this.paused,
  });

  final String text;
  final bool warning;
  final bool paused;

  @override
  Widget build(BuildContext context) {
    final color = paused ? _danger : warning ? _warning : _brand;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        border: Border.all(color: color.withValues(alpha: 0.28)),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(paused ? Icons.pause_circle : Icons.timer_outlined, color: color, size: 18),
          const SizedBox(width: 7),
          Text(
            text,
            style: TextStyle(color: color, fontWeight: FontWeight.w900),
          ),
        ],
      ),
    );
  }
}

class _ExamProgressHeader extends StatelessWidget {
  const _ExamProgressHeader({
    required this.assessment,
    required this.monitoringLabel,
    required this.answered,
    required this.total,
    required this.current,
    required this.remainingText,
    required this.paused,
    this.compact = false,
  });

  final DemoAssessment assessment;
  final String monitoringLabel;
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
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        boxShadow: const [
          BoxShadow(
            color: Color(0x140F172A),
            blurRadius: 22,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: Container(
        padding: EdgeInsets.all(compact ? 16 : 18),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [_brandDark, Color(0xFF113A63), _brand],
          ),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 620;
            final title = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _HeroTag(assessment.course.code),
                    _HeroTag(paused ? 'Paused' : monitoringLabel),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  assessment.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: compact ? 21 : 25,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.4,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${assessment.course.title} • ${assessment.course.lecturer}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFFCBD5E1),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            );
            final stats = Container(
              width: wide ? 235 : double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _HeaderStat(label: 'Time left', value: remainingText),
                  const SizedBox(height: 6),
                  _HeaderStat(label: 'Question', value: '$current of $total'),
                  const SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      value: progress.clamp(0.0, 1.0),
                      minHeight: 8,
                      backgroundColor: Colors.white.withValues(alpha: 0.18),
                      color: const Color(0xFF60A5FA),
                    ),
                  ),
                  const SizedBox(height: 7),
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
                children: [title, const SizedBox(height: 14), stats],
              );
            }
            return Row(
              children: [
                Expanded(child: title),
                const SizedBox(width: 16),
                stats,
              ],
            );
          },
        ),
      ),
    );
  }
}

class _HeroTag extends StatelessWidget {
  const _HeroTag(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
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
            style: const TextStyle(
              color: Color(0xFF94A3B8),
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Text(
          value,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
        ),
      ],
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
    final content = Container(
      margin: EdgeInsets.all(compact ? 0 : 16),
      padding: const EdgeInsets.all(14),
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
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Questions',
                  style: TextStyle(
                    color: _brandDark,
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                  ),
                ),
              ),
              Text(
                '${currentIndex + 1}/${questions.length}',
                style: const TextStyle(color: _muted, fontWeight: FontWeight.w800),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (var i = 0; i < questions.length; i++)
                _QuestionNumberButton(
                  number: i + 1,
                  selected: i == currentIndex,
                  answered: (answers[questions[i].id] ?? '').trim().isNotEmpty,
                  enabled: enabled,
                  onTap: () => onSelect(i),
                ),
            ],
          ),
        ],
      ),
    );

    if (compact) return content;
    return Container(color: _pageBg, child: SingleChildScrollView(child: content));
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
    final color = selected ? _brand : answered ? _success : _muted;
    return Material(
      color: selected ? _brand : answered ? const Color(0xFFF0FDF4) : _surfaceSoft,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: 42,
          height: 42,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withValues(alpha: selected ? 1 : 0.28)),
          ),
          child: Text(
            '$number',
            style: TextStyle(
              color: selected ? Colors.white : color,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ),
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
    required this.submitting,
  });

  final DemoQuestion question;
  final String value;
  final bool enabled;
  final ValueChanged<String> onChanged;
  final bool canPrevious;
  final bool canNext;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback? onSubmit;
  final bool submitting;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _QuestionCard(
          question: question,
          value: value,
          enabled: enabled,
          onChanged: onChanged,
        ),
        const SizedBox(height: 14),
        _QuestionActions(
          canPrevious: canPrevious && enabled,
          canNext: canNext && enabled,
          onPrevious: onPrevious,
          onNext: onNext,
          onSubmit: onSubmit,
          submitting: submitting,
        ),
      ],
    );
  }
}

class _QuestionCard extends StatefulWidget {
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
  State<_QuestionCard> createState() => _QuestionCardState();
}

class _QuestionCardState extends State<_QuestionCard> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value);
  }

  @override
  void didUpdateWidget(covariant _QuestionCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.question.id != widget.question.id ||
        _controller.text != widget.value) {
      _controller.text = widget.value;
      _controller.selection = TextSelection.collapsed(offset: _controller.text.length);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final question = widget.question;
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: _surface,
        border: Border.all(color: _line),
        borderRadius: BorderRadius.circular(22),
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
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SectionBadge(section: question.section),
              const SizedBox(width: 10),
              _MarksBadge(marks: question.marks),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            question.prompt,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: _brandDark,
                  fontWeight: FontWeight.w900,
                  height: 1.35,
                ),
          ),
          const SizedBox(height: 20),
          if (question.section == DemoExamSection.objective)
            _ObjectiveOptions(
              options: question.options,
              value: widget.value,
              enabled: widget.enabled,
              onChanged: widget.onChanged,
            )
          else
            TextField(
              controller: _controller,
              enabled: widget.enabled,
              minLines: question.section == DemoExamSection.theory ? 8 : 2,
              maxLines: question.section == DemoExamSection.theory ? 14 : 4,
              onChanged: widget.onChanged,
              decoration: InputDecoration(
                hintText: question.section == DemoExamSection.theory
                    ? 'Write your answer here...'
                    : 'Enter your answer...',
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
                  borderSide: const BorderSide(color: _brand, width: 1.6),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ObjectiveOptions extends StatelessWidget {
  const _ObjectiveOptions({
    required this.options,
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final List<String> options;
  final String value;
  final bool enabled;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final option in options)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: RadioListTile<String>(
              value: option,
              groupValue: value.isEmpty ? null : value,
              onChanged: enabled ? (selected) {
                if (selected != null) onChanged(selected);
              } : null,
              title: Text(
                option,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              tileColor: _surfaceSoft,
              selectedTileColor: const Color(0xFFEFF6FF),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            ),
          ),
      ],
    );
  }
}

class _SectionBadge extends StatelessWidget {
  const _SectionBadge({required this.section});

  final DemoExamSection section;

  @override
  Widget build(BuildContext context) {
    return _SmallBadge(
      label: section.label,
      color: section == DemoExamSection.theory ? _warning : _brand,
    );
  }
}

class _MarksBadge extends StatelessWidget {
  const _MarksBadge({required this.marks});

  final int marks;

  @override
  Widget build(BuildContext context) {
    return _SmallBadge(label: '$marks marks', color: _success);
  }
}

class _SmallBadge extends StatelessWidget {
  const _SmallBadge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 12),
      ),
    );
  }
}

class _QuestionActions extends StatelessWidget {
  const _QuestionActions({
    required this.canPrevious,
    required this.canNext,
    required this.onPrevious,
    required this.onNext,
    required this.onSubmit,
    required this.submitting,
  });

  final bool canPrevious;
  final bool canNext;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback? onSubmit;
  final bool submitting;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _surface,
        border: Border.all(color: _line),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          OutlinedButton.icon(
            onPressed: canPrevious ? onPrevious : null,
            icon: const Icon(Icons.arrow_back_rounded),
            label: const Text('Previous'),
          ),
          const SizedBox(width: 10),
          OutlinedButton.icon(
            onPressed: canNext ? onNext : null,
            icon: const Icon(Icons.arrow_forward_rounded),
            label: const Text('Next'),
          ),
          const Spacer(),
          FilledButton.icon(
            onPressed: onSubmit,
            icon: submitting
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.task_alt_rounded),
            label: Text(submitting ? 'Submitting...' : 'Submit'),
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
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: _line)),
        ),
        child: Row(
          children: [
            IconButton.outlined(
              onPressed: canGoBack ? onPrevious : null,
              icon: const Icon(Icons.arrow_back_rounded),
            ),
            const SizedBox(width: 8),
            IconButton.outlined(
              onPressed: canGoNext ? onNext : null,
              icon: const Icon(Icons.arrow_forward_rounded),
            ),
            const Spacer(),
            FilledButton.icon(
              onPressed: canSubmit ? onSubmit : null,
              icon: const Icon(Icons.task_alt_rounded),
              label: const Text('Submit'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ExamStatusPanel extends StatelessWidget {
  const _ExamStatusPanel({
    required this.assessment,
    required this.profile,
    required this.paused,
    required this.answered,
    required this.total,
    this.compact = false,
  });

  final DemoAssessment assessment;
  final AssessmentMonitoringProfile profile;
  final bool paused;
  final int answered;
  final int total;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: paused ? const Color(0xFFFEF2F2) : const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  paused ? Icons.pause_circle_outline : Icons.verified_outlined,
                  color: paused ? _danger : _brand,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  paused ? 'Needs attention' : _statusTitle,
                  style: const TextStyle(
                    color: _brandDark,
                    fontWeight: FontWeight.w900,
                    fontSize: 17,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _StatusLine(
            label: 'Progress',
            value: '$answered of $total answered',
            color: _brand,
          ),
          if (profile.requiresCamera)
            const _StatusLine(label: 'Camera check', value: 'Active', color: _success),
          if (profile.requiresMicrophone)
            const _StatusLine(label: 'Microphone check', value: 'Active', color: _success),
          if (profile.usesSystemSecurityPanel)
            const _StatusLine(label: 'Device check', value: 'Active', color: _success),
          if (!profile.showsLiveMonitor)
            const _StatusLine(label: 'Access mode', value: 'Standard', color: _muted),
          const SizedBox(height: 12),
          Text(
            _helperText,
            style: const TextStyle(
              color: _muted,
              height: 1.45,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  String get _statusTitle {
    switch (profile.mode) {
      case AssessmentMonitoringMode.strictExam:
        return 'Exam mode active';
      case AssessmentMonitoringMode.gradedLight:
        return 'Assessment checks active';
      case AssessmentMonitoringMode.standardAccess:
        return 'Standard access';
    }
  }

  String get _helperText {
    if (paused) return 'Please wait and follow the instruction shown on the screen.';
    if (profile.mode == AssessmentMonitoringMode.strictExam) {
      return 'Stay on this screen until you submit your work.';
    }
    return 'Your work is saved on this page while you continue.';
  }
}

class _StatusLine extends StatelessWidget {
  const _StatusLine({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Row(
        children: [
          Container(
            width: 9,
            height: 9,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(color: _muted, fontWeight: FontWeight.w700),
            ),
          ),
          Text(
            value,
            style: const TextStyle(color: _brandDark, fontWeight: FontWeight.w900),
          ),
        ],
      ),
    );
  }
}

class _HiddenMonitoringRuntime extends StatelessWidget {
  const _HiddenMonitoringRuntime({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Offstage(offstage: true, child: child);
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
        color: const Color(0xFFFEF2F2),
        border: Border.all(color: const Color(0xFFFECACA)),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline, color: _danger),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message.isEmpty ? 'Your assessment needs attention before you continue.' : message,
              style: const TextStyle(
                color: Color(0xFF7F1D1D),
                fontWeight: FontWeight.w800,
                height: 1.4,
              ),
            ),
          ),
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
      margin: EdgeInsets.all(compact ? 0 : 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _surface,
        border: Border.all(color: _line),
        borderRadius: BorderRadius.circular(18),
      ),
      child: const Text(
        'Question navigation is paused for now.',
        style: TextStyle(color: _muted, fontWeight: FontWeight.w700),
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
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: _surface,
        border: Border.all(color: _line),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.lock_outline, color: _danger, size: 34),
          const SizedBox(height: 12),
          Text(
            'Writing is paused',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: _brandDark,
                  fontWeight: FontWeight.w900,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            message.isEmpty
                ? 'Please wait and follow the instruction shown on the screen.'
                : message,
            style: const TextStyle(color: _muted, height: 1.45, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

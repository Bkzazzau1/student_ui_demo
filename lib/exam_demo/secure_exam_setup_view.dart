import 'package:flutter/material.dart';

import '../face_demo/demo_face_id_service.dart';
import '../face_demo/demo_face_id_view.dart';
import '../proctoring_demo/audio_system_review_view.dart';
import '../proctoring_demo/proctoring_demo_home.dart';
import 'demo_exam_attempt_view.dart';
import 'demo_exam_models.dart';
import 'demo_exam_service.dart';
import 'exam_start_approval_service.dart';

const Color _brand = Color(0xFF0F4C81);
const Color _brandDark = Color(0xFF0B1220);
const Color _surface = Colors.white;
const Color _surfaceSoft = Color(0xFFF8FAFC);
const Color _line = Color(0xFFE2E8F0);
const Color _muted = Color(0xFF64748B);
const Color _success = Color(0xFF16A34A);
const Color _warning = Color(0xFFF59E0B);
const Color _purple = Color(0xFF7C3AED);

class SecureExamSetupView extends StatefulWidget {
  const SecureExamSetupView({super.key, required this.assessment});

  final DemoAssessment assessment;

  @override
  State<SecureExamSetupView> createState() => _SecureExamSetupViewState();
}

class _SecureExamSetupViewState extends State<SecureExamSetupView> {
  static const String _baseUrl = String.fromEnvironment(
    'KSLAS_API_BASE_URL',
    defaultValue: 'http://127.0.0.1:8080',
  );
  static const bool _allowExamOverride = bool.fromEnvironment(
    'KSLAS_ALLOW_EXAM_OVERRIDE',
    defaultValue: false,
  );

  final DemoFaceIdService _faceIdService = DemoFaceIdService();
  late final ExamStartApprovalService _approvalService;
  late DemoFaceIdSnapshot _faceId;
  late String _attemptId;
  bool _roomApproved = false;
  bool _audioApproved = false;
  bool _systemApproved = false;
  bool _requestingApproval = false;
  bool _startApproved = false;
  String? _manifestPath;
  String? _startToken;
  String _approvalMessage = _allowExamOverride
      ? 'You may begin when ready.'
      : 'Complete the required steps before starting.';
  AudioSystemReviewResult? _audioSystemReview;
  ExamStartApprovalResult? _approvalResult;

  @override
  void initState() {
    super.initState();
    _faceId = _faceIdService.load();
    _attemptId = 'attempt-${DateTime.now().millisecondsSinceEpoch}';
    _approvalService = ExamStartApprovalService(baseUrl: _baseUrl);
  }

  @override
  void dispose() {
    _approvalService.dispose();
    super.dispose();
  }

  bool get _needsChecks =>
      widget.assessment.isStrictExam && widget.assessment.remoteProctored;
  bool get _faceOk => !widget.assessment.graded || _faceId.isComplete;
  bool get _roomOk => !_needsChecks || (_roomApproved && _manifestPath != null);
  bool get _audioOk => !_needsChecks || _audioApproved;
  bool get _systemOk => !_needsChecks || _systemApproved;
  bool get _allChecksReady => _faceOk && _roomOk && _audioOk && _systemOk;
  bool get _approvalRequired =>
      widget.assessment.remoteProctored || widget.assessment.graded;
  bool get _approvalOk =>
      _allowExamOverride || !_approvalRequired || (_startApproved && _startToken != null);

  bool _canStartOnDevice(BuildContext context) {
    final phoneSized = MediaQuery.sizeOf(context).shortestSide < 600;
    return !phoneSized || !widget.assessment.isStrictExam;
  }

  bool _canRequestApproval(BuildContext context) {
    return _allChecksReady && _canStartOnDevice(context) && !_requestingApproval;
  }

  bool _canStart(BuildContext context) {
    if (!_canStartOnDevice(context)) return false;
    if (_allowExamOverride) return true;
    return _allChecksReady && _approvalOk;
  }

  void _clearApproval([String? message]) {
    _startApproved = false;
    _startToken = null;
    _approvalResult = null;
    _approvalMessage = _allowExamOverride
        ? 'You may begin when ready.'
        : message ?? 'Please complete the final readiness step again.';
  }

  @override
  Widget build(BuildContext context) {
    final questions = DemoExamService.questionsFor(widget.assessment);
    final checksPassed = <bool>[_faceOk, _roomOk, _audioOk, _systemOk]
        .where((passed) => passed)
        .length;
    final requiredChecks = <bool>[_faceOk, _roomOk, _audioOk, _systemOk].length;

    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FB),
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        titleSpacing: 0,
        title: Text(
          _setupTitle,
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: TextButton.icon(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.arrow_back_rounded, size: 18),
              label: const Text('Back'),
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
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 110),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1080),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _PreparationHero(
                      assessment: widget.assessment,
                      questionCount: questions.length,
                      checksPassed: checksPassed,
                      requiredChecks: requiredChecks,
                      startReady: _canStart(context),
                    ),
                    const SizedBox(height: 14),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final wide = constraints.maxWidth >= 920;
                        final steps = _PreparationSteps(steps: _buildSteps(context));
                        final startPanel = _StartPanel(
                          assessment: widget.assessment,
                          ready: _canStart(context),
                          startLabel: _allowExamOverride ? 'Start now' : _startLabel,
                          approvalCard: _ReadinessCard(
                            approved: _approvalOk,
                            requesting: _requestingApproval,
                            message: _approvalMessage,
                            result: _approvalResult,
                          ),
                          onStart: _canStart(context) ? _startExam : null,
                        );

                        if (!wide) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [steps, const SizedBox(height: 14), startPanel],
                          );
                        }
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(flex: 7, child: steps),
                            const SizedBox(width: 14),
                            Expanded(flex: 4, child: startPanel),
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

  List<_SetupStepData> _buildSteps(BuildContext context) {
    final steps = <_SetupStepData>[
      _SetupStepData(
        number: 1,
        title: 'Identity check',
        subtitle: widget.assessment.graded
            ? 'Confirm your student identity before continuing.'
            : 'Identity setup is available for this activity.',
        status: _faceOk ? _StepStatus.complete : _StepStatus.pending,
        icon: Icons.account_circle_outlined,
        actionLabel: _faceId.isComplete ? 'Review identity' : 'Set up identity',
        onPressed: _openFaceId,
      ),
      if (_needsChecks)
        _SetupStepData(
          number: 2,
          title: 'Camera and room check',
          subtitle: 'Show your desk and exam area clearly before the exam begins.',
          status: _roomOk ? _StepStatus.complete : _StepStatus.pending,
          icon: Icons.photo_camera_front_outlined,
          actionLabel: _roomOk ? 'Check again' : 'Start check',
          onPressed: _openRoomScan,
        ),
      if (_needsChecks)
        _SetupStepData(
          number: 3,
          title: 'Sound and device check',
          subtitle: 'Confirm your microphone and device are ready for the assessment.',
          status: _audioOk && _systemOk ? _StepStatus.complete : _StepStatus.pending,
          icon: Icons.devices_outlined,
          actionLabel: _audioOk && _systemOk ? 'Check again' : 'Start check',
          onPressed: _openAudioSystemReview,
        ),
      if (_approvalRequired && !_allowExamOverride)
        _SetupStepData(
          number: _needsChecks ? 4 : 2,
          title: 'Final readiness',
          subtitle: _allChecksReady
              ? 'Confirm that everything is ready before you start.'
              : 'Complete the required steps first.',
          status: _approvalOk
              ? _StepStatus.complete
              : _requestingApproval
                  ? _StepStatus.running
                  : _StepStatus.pending,
          icon: Icons.verified_outlined,
          actionLabel: _requestingApproval
              ? 'Checking...'
              : _approvalOk
                  ? 'Ready'
                  : 'Confirm readiness',
          onPressed: _canRequestApproval(context) ? _requestApproval : null,
        ),
    ];

    if (steps.isEmpty) {
      return <_SetupStepData>[
        _SetupStepData(
          number: 1,
          title: 'Ready to start',
          subtitle: 'You may begin when ready.',
          status: _StepStatus.complete,
          icon: Icons.check_circle_outline,
          actionLabel: 'Ready',
          onPressed: null,
        ),
      ];
    }
    return steps;
  }

  Future<void> _openFaceId() async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => DemoFaceIdView(
          onComplete: () => setState(() {
            _faceId = _faceIdService.load();
            _clearApproval('Identity check updated. Please confirm readiness again.');
          }),
        ),
      ),
    );
    if (!mounted) return;
    setState(() {
      _faceId = _faceIdService.load();
      _clearApproval('Identity check completed. Please confirm readiness again.');
    });
  }

  Future<void> _openRoomScan() async {
    setState(() {
      _roomApproved = false;
      _manifestPath = null;
      _clearApproval('Camera and room check changed. Please confirm readiness after all steps are complete.');
    });
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => ProctoringDemoHome(
          compactExamGate: true,
          examId: widget.assessment.id,
          attemptId: _attemptId,
          onApproved: (manifestPath) {
            if (manifestPath == null || manifestPath.trim().isEmpty) {
              setState(() {
                _roomApproved = false;
                _manifestPath = null;
                _clearApproval('Camera and room check was not completed. Please try again.');
              });
              return;
            }
            setState(() {
              _roomApproved = true;
              _manifestPath = manifestPath;
              _clearApproval('Camera and room check complete. Please confirm readiness after all steps are complete.');
            });
            Navigator.of(context).pop();
          },
        ),
      ),
    );
  }

  Future<void> _openAudioSystemReview() async {
    final result = await Navigator.of(context).push<AudioSystemReviewResult>(
      MaterialPageRoute<AudioSystemReviewResult>(
        builder: (_) => const AudioSystemReviewView(),
      ),
    );
    if (!mounted || result == null) return;
    setState(() {
      _audioSystemReview = result;
      _audioApproved = result.audioReady;
      _systemApproved = result.systemReady;
      _clearApproval('Sound or device check changed. Please confirm readiness again.');
    });
  }

  Future<void> _requestApproval() async {
    if (!_canStartOnDevice(context)) {
      await _showPhoneBlockedMessage();
      return;
    }
    if (!_allChecksReady) {
      await _showBlockedStartMessage();
      return;
    }
    setState(() {
      _requestingApproval = true;
      _approvalMessage = 'Confirming your assessment readiness...';
    });
    try {
      final result = await _approvalService.requestStartApproval(
        studentId: _faceId.studentId,
        examId: widget.assessment.id,
        attemptId: _attemptId,
        manifestPath: _manifestPath,
        faceIdReady: _faceOk,
        faceIdLocked: _faceId.locked,
        faceEnrollmentId: _faceId.enrollmentId,
        roomScanReady: _roomOk,
        audioReady: _audioOk,
        systemReady: _systemOk,
        audioReview: _audioSystemReview?.audioReview?.toJson() ?? const <String, Object?>{},
        systemReview: _audioSystemReview?.systemReview?.toJson() ?? const <String, Object?>{},
      );
      if (!mounted) return;
      setState(() {
        _requestingApproval = false;
        _approvalResult = result;
        _startApproved = result.approved && result.hasToken;
        _startToken = result.approved && result.hasToken ? result.examStartToken : null;
        _approvalMessage = result.approved && result.hasToken
            ? 'Everything is ready. You may now begin.'
            : _friendlyApprovalMessage(result);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _requestingApproval = false;
        _startApproved = false;
        _startToken = null;
        _approvalMessage = 'Readiness confirmation could not be completed. Check your connection and try again.';
      });
    }
  }

  String _friendlyApprovalMessage(ExamStartApprovalResult result) {
    if (result.issues.isNotEmpty) return result.issues.join(' ');
    return result.message
        .replaceAll('Backend ', '')
        .replaceAll('backend ', '')
        .replaceAll('approved_to_start', 'ready to start')
        .replaceAll('_', ' ');
  }

  Future<void> _startExam() async {
    if (!_canStartOnDevice(context)) {
      await _showPhoneBlockedMessage();
      return;
    }
    if (!_allowExamOverride && (!_canStart(context) || (_approvalRequired && _startToken == null))) {
      await _showBlockedStartMessage();
      return;
    }
    final result = await Navigator.of(context).push<DemoExamResult>(
      MaterialPageRoute<DemoExamResult>(
        builder: (_) => DemoExamAttemptView(
          assessment: widget.assessment,
          proctoringManifestPath: _manifestPath,
          attemptId: _attemptId,
          examStartToken: _startToken ?? (_allowExamOverride ? 'dev_override_$_attemptId' : ''),
          agentDecision: _allowExamOverride
              ? 'testing_override_start'
              : _approvalRequired
                  ? 'start_approved'
                  : widget.assessment.attendanceOnly
                      ? 'attendance_only'
                      : 'local_setup_ready',
        ),
      ),
    );
    if (!mounted || result == null) return;
    Navigator.of(context).pop(result);
  }

  Future<void> _showBlockedStartMessage() {
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Not ready yet'),
        content: const Text('Complete each required step before starting.'),
        actions: [
          FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('OK')),
        ],
      ),
    );
  }

  Future<void> _showPhoneBlockedMessage() {
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Use a larger device'),
        content: const Text(
          'Supervised examinations must be completed on a desktop or laptop. '
          'Other assessments may be completed on phone, tablet, desktop, or laptop when allowed by the lecturer.',
        ),
        actions: [
          FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('OK')),
        ],
      ),
    );
  }

  String get _setupTitle {
    if (widget.assessment.isStrictExam) return 'Prepare for exam';
    if (widget.assessment.attendanceOnly) return 'Prepare for practice';
    return 'Prepare for assessment';
  }

  String get _startLabel {
    if (widget.assessment.isStrictExam) return 'Start exam';
    if (widget.assessment.attendanceOnly) return 'Start practice';
    return 'Start assessment';
  }
}

enum _StepStatus { complete, pending, running }

class _SetupStepData {
  const _SetupStepData({
    required this.number,
    required this.title,
    required this.subtitle,
    required this.status,
    required this.icon,
    required this.actionLabel,
    required this.onPressed,
  });

  final int number;
  final String title;
  final String subtitle;
  final _StepStatus status;
  final IconData icon;
  final String actionLabel;
  final VoidCallback? onPressed;
}

class _PreparationHero extends StatelessWidget {
  const _PreparationHero({
    required this.assessment,
    required this.questionCount,
    required this.checksPassed,
    required this.requiredChecks,
    required this.startReady,
  });

  final DemoAssessment assessment;
  final int questionCount;
  final int checksPassed;
  final int requiredChecks;
  final bool startReady;

  @override
  Widget build(BuildContext context) {
    final progress = requiredChecks == 0 ? 1.0 : checksPassed / requiredChecks;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [
          BoxShadow(color: Color(0x1F0F172A), blurRadius: 24, offset: Offset(0, 14)),
        ],
      ),
      child: Container(
        padding: const EdgeInsets.all(22),
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
            final info = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _HeroTag(
                      icon: Icons.verified_user_outlined,
                      text: assessment.isStrictExam
                          ? 'Supervised exam'
                          : assessment.graded
                              ? 'Graded assessment'
                              : 'Practice',
                    ),
                    _HeroTag(icon: Icons.schedule_outlined, text: '${assessment.durationMinutes} minutes'),
                    _HeroTag(icon: Icons.quiz_outlined, text: '$questionCount questions'),
                  ],
                ),
                const SizedBox(height: 14),
                const Text(
                  'Exam check',
                  style: TextStyle(color: Color(0xFFDBEAFE), fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 7),
                Text(
                  assessment.title,
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.4,
                      ),
                ),
                const SizedBox(height: 7),
                Text(
                  '${assessment.course.code} • ${assessment.course.title}',
                  style: const TextStyle(
                    color: Color(0xFFE2E8F0),
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Lecturer: ${assessment.course.lecturer}',
                  style: const TextStyle(color: Color(0xFFCBD5E1), fontWeight: FontWeight.w600),
                ),
              ],
            );

            final status = _PreparationStatus(
              startReady: startReady,
              progress: progress,
              checksPassed: checksPassed,
              requiredChecks: requiredChecks,
            );

            if (!wide) {
              return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [info, const SizedBox(height: 16), status]);
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: info),
                const SizedBox(width: 22),
                SizedBox(width: 260, child: status),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _HeroTag extends StatelessWidget {
  const _HeroTag({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 15),
          const SizedBox(width: 7),
          Text(text, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }
}

class _PreparationStatus extends StatelessWidget {
  const _PreparationStatus({
    required this.startReady,
    required this.progress,
    required this.checksPassed,
    required this.requiredChecks,
  });

  final bool startReady;
  final double progress;
  final int checksPassed;
  final int requiredChecks;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            startReady ? Icons.check_circle_outline : Icons.pending_actions_outlined,
            color: startReady ? const Color(0xFF86EFAC) : const Color(0xFFBFDBFE),
            size: 28,
          ),
          const SizedBox(height: 10),
          Text(
            startReady ? 'Ready to start' : 'Steps remaining',
            style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              minHeight: 9,
              value: progress.clamp(0.0, 1.0),
              backgroundColor: Colors.white.withValues(alpha: 0.18),
              color: startReady ? const Color(0xFF22C55E) : const Color(0xFF60A5FA),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            '$checksPassed of $requiredChecks steps ready',
            style: const TextStyle(color: Color(0xFFCBD5E1), fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

class _PreparationSteps extends StatelessWidget {
  const _PreparationSteps({required this.steps});

  final List<_SetupStepData> steps;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _line),
        boxShadow: const [
          BoxShadow(color: Color(0x080F172A), blurRadius: 18, offset: Offset(0, 10)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(color: const Color(0xFFEFF6FF), borderRadius: BorderRadius.circular(14)),
                child: const Icon(Icons.task_alt_outlined, color: _brand),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Complete these steps',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(color: _brandDark, fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 3),
                    const Text(
                      'Follow the steps below. The start button opens when everything is ready.',
                      style: TextStyle(color: _muted, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          for (var index = 0; index < steps.length; index++) ...[
            _StepCard(step: steps[index]),
            if (index != steps.length - 1) const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}

class _StepCard extends StatelessWidget {
  const _StepCard({required this.step});

  final _SetupStepData step;

  @override
  Widget build(BuildContext context) {
    final complete = step.status == _StepStatus.complete;
    final running = step.status == _StepStatus.running;
    final accent = complete
        ? _success
        : running
            ? _brand
            : _warning;
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: complete
            ? const Color(0xFFF0FDF4)
            : running
                ? const Color(0xFFEFF6FF)
                : _surfaceSoft,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: complete
              ? const Color(0xFFBBF7D0)
              : running
                  ? const Color(0xFFBFDBFE)
                  : _line,
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 600;
          final leading = Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: accent.withValues(alpha: 0.20)),
            ),
            child: Icon(step.icon, color: accent),
          );
          final text = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _StepNumber(number: step.number, color: accent),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      step.title,
                      style: const TextStyle(color: _brandDark, fontSize: 17, fontWeight: FontWeight.w900),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(step.subtitle, style: const TextStyle(color: _muted, height: 1.35, fontWeight: FontWeight.w600)),
              const SizedBox(height: 10),
              _StepStatusPill(status: step.status),
            ],
          );
          final action = FilledButton.icon(
            onPressed: step.onPressed,
            style: FilledButton.styleFrom(
              backgroundColor: complete ? Colors.white : _brand,
              foregroundColor: complete ? _brand : Colors.white,
              disabledBackgroundColor: const Color(0xFFE2E8F0),
              disabledForegroundColor: _muted,
              side: complete ? const BorderSide(color: _line) : BorderSide.none,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              textStyle: const TextStyle(fontWeight: FontWeight.w900),
            ),
            icon: Icon(complete ? Icons.refresh_rounded : Icons.arrow_forward_rounded, size: 18),
            label: Text(step.actionLabel),
          );

          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [leading, const SizedBox(width: 12), Expanded(child: text)]),
                const SizedBox(height: 12),
                action,
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              leading,
              const SizedBox(width: 14),
              Expanded(child: text),
              const SizedBox(width: 14),
              action,
            ],
          );
        },
      ),
    );
  }
}

class _StepNumber extends StatelessWidget {
  const _StepNumber({required this.number, required this.color});

  final int number;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 26,
      height: 26,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.11),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Text('$number', style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 12)),
    );
  }
}

class _StepStatusPill extends StatelessWidget {
  const _StepStatusPill({required this.status});

  final _StepStatus status;

  @override
  Widget build(BuildContext context) {
    final color = status == _StepStatus.complete
        ? _success
        : status == _StepStatus.running
            ? _brand
            : _warning;
    final label = status == _StepStatus.complete
        ? 'Completed'
        : status == _StepStatus.running
            ? 'Checking now'
            : 'Waiting';
    final icon = status == _StepStatus.complete
        ? Icons.check_circle
        : status == _StepStatus.running
            ? Icons.sync
            : Icons.radio_button_unchecked;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 12)),
        ],
      ),
    );
  }
}

class _StartPanel extends StatelessWidget {
  const _StartPanel({
    required this.assessment,
    required this.ready,
    required this.startLabel,
    required this.approvalCard,
    required this.onStart,
  });

  final DemoAssessment assessment;
  final bool ready;
  final String startLabel;
  final Widget approvalCard;
  final VoidCallback? onStart;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: _surface,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: _line),
            boxShadow: const [
              BoxShadow(color: Color(0x080F172A), blurRadius: 18, offset: Offset(0, 10)),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(color: const Color(0xFFEFF6FF), borderRadius: BorderRadius.circular(14)),
                    child: Icon(ready ? Icons.play_circle_outline : Icons.lock_outline_rounded, color: ready ? _success : _brand),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Final step',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(color: _brandDark, fontWeight: FontWeight.w900),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _SummaryLine(icon: Icons.book_outlined, label: assessment.course.code),
              _SummaryLine(icon: Icons.schedule_outlined, label: '${assessment.durationMinutes} minutes'),
              _SummaryLine(
                icon: Icons.check_circle_outline,
                label: assessment.remoteProctored ? 'Preparation required' : 'Standard access',
              ),
              _SummaryLine(
                icon: Icons.rate_review_outlined,
                label: assessment.graded ? 'Submission will be reviewed' : 'Feedback activity',
              ),
              const SizedBox(height: 16),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: ready
                      ? const LinearGradient(colors: [_brand, Color(0xFF1D4ED8), _success])
                      : const LinearGradient(colors: [Color(0xFFE2E8F0), Color(0xFFCBD5E1)]),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: ready
                      ? const [
                          BoxShadow(color: Color(0x200F4C81), blurRadius: 14, offset: Offset(0, 8)),
                        ]
                      : const [],
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: onStart,
                    borderRadius: BorderRadius.circular(14),
                    child: SizedBox(
                      height: 52,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(ready ? Icons.play_arrow_rounded : Icons.lock_outline_rounded, color: ready ? Colors.white : _muted),
                          const SizedBox(width: 8),
                          Text(
                            startLabel,
                            style: TextStyle(color: ready ? Colors.white : _muted, fontWeight: FontWeight.w900),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              if (!ready) ...[
                const SizedBox(height: 10),
                const Text(
                  'Complete the required steps to unlock this button.',
                  style: TextStyle(color: _muted, fontWeight: FontWeight.w700),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 14),
        approvalCard,
        const SizedBox(height: 14),
        const _SimpleReminder(),
      ],
    );
  }
}

class _SummaryLine extends StatelessWidget {
  const _SummaryLine({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Icon(icon, size: 18, color: _muted),
          const SizedBox(width: 9),
          Expanded(
            child: Text(label, style: const TextStyle(color: Color(0xFF334155), fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }
}

class _ReadinessCard extends StatelessWidget {
  const _ReadinessCard({
    required this.approved,
    required this.requesting,
    required this.message,
    required this.result,
  });

  final bool approved;
  final bool requesting;
  final String message;
  final ExamStartApprovalResult? result;

  @override
  Widget build(BuildContext context) {
    final color = requesting
        ? _brand
        : approved
            ? _success
            : _warning;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withValues(alpha: 0.30)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            requesting
                ? Icons.sync
                : approved
                    ? Icons.verified_outlined
                    : Icons.info_outline,
            color: color,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  approved ? 'Ready' : 'Readiness status',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(color: _brandDark, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 6),
                Text(message, style: const TextStyle(color: Color(0xFF334155), height: 1.35, fontWeight: FontWeight.w600)),
                if (result != null && !approved && result!.issues.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  ...result!.issues.map((issue) => Text('• $issue')),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SimpleReminder extends StatelessWidget {
  const _SimpleReminder();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFFDE68A)),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, color: _warning, size: 20),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Sit in a quiet place, keep your device charged, and stay on the assessment screen until you submit.',
              style: TextStyle(color: Color(0xFF78350F), height: 1.45, fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }
}

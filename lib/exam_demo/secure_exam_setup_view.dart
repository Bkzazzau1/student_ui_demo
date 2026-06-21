import 'package:flutter/material.dart';

import '../face_demo/demo_face_id_service.dart';
import '../face_demo/demo_face_id_view.dart';
import '../proctoring_demo/audio_system_review_view.dart';
import '../proctoring_demo/proctoring_demo_home.dart';
import 'demo_exam_attempt_view.dart';
import 'demo_exam_models.dart';
import 'demo_exam_service.dart';
import 'exam_start_approval_service.dart';

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
      ? 'Testing override is active. Start exam is unlocked for development testing only.'
      : 'Start approval has not been requested.';
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
        ? 'Testing override is active. Start exam is unlocked for development testing only.'
        : message ?? 'Start approval must be requested again.';
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
        title: Text(_setupTitle, style: const TextStyle(fontWeight: FontWeight.w900)),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: OutlinedButton.icon(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.arrow_back_rounded, size: 18),
              label: const Text('Back'),
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
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 120),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1220),
                child: Column(
                  children: [
                    _Header(
                      assessment: widget.assessment,
                      questionCount: questions.length,
                      checksPassed: checksPassed,
                      requiredChecks: requiredChecks,
                      startReady: _canStart(context),
                    ),
                    const SizedBox(height: 16),
                    if (_allowExamOverride) ...[
                      const _OverrideNotice(),
                      const SizedBox(height: 16),
                    ],
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final wide = constraints.maxWidth >= 940;
                        final timeline = _SetupTimeline(
                          steps: _buildSteps(context),
                        );
                        final sidePanel = _SetupSidePanel(
                          assessment: widget.assessment,
                          approvalCard: _ApprovalCard(
                            approved: _approvalOk,
                            requesting: _requestingApproval,
                            message: _approvalMessage,
                            result: _approvalResult,
                          ),
                          rules: _Rules(remote: widget.assessment.remoteProctored),
                          canStart: _canStart(context),
                          startLabel: _allowExamOverride
                              ? 'Start exam for testing'
                              : _startLabel,
                          onStart: _canStart(context) ? _startExam : null,
                        );

                        if (!wide) {
                          return Column(
                            children: [timeline, const SizedBox(height: 16), sidePanel],
                          );
                        }
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(flex: 7, child: timeline),
                            const SizedBox(width: 16),
                            Expanded(flex: 4, child: sidePanel),
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
        title: 'Confirm your identity',
        subtitle: widget.assessment.graded
            ? 'Face ID is required for this activity.'
            : 'Face ID is optional for this practice activity.',
        status: _faceOk ? _StepStatus.complete : _StepStatus.pending,
        icon: Icons.face_retouching_natural_outlined,
        actionLabel: _faceId.isComplete ? 'Update Face ID' : 'Set up Face ID',
        onPressed: widget.assessment.graded || !_faceId.isComplete ? _openFaceId : _openFaceId,
      ),
      if (_needsChecks)
        _SetupStepData(
          number: 2,
          title: 'Scan your exam area',
          subtitle: 'Show your desk and surroundings before the exam starts.',
          status: _roomOk ? _StepStatus.complete : _StepStatus.pending,
          icon: Icons.screen_rotation_alt_outlined,
          actionLabel: _roomOk ? 'Run scan again' : 'Start room scan',
          onPressed: _openRoomScan,
        ),
      if (_needsChecks)
        _SetupStepData(
          number: 3,
          title: 'Check sound and device',
          subtitle: 'Confirm microphone, system readiness, and exam access settings.',
          status: _audioOk && _systemOk ? _StepStatus.complete : _StepStatus.pending,
          icon: Icons.settings_voice_outlined,
          actionLabel: _audioOk && _systemOk
              ? 'Run checks again'
              : 'Start sound and device check',
          onPressed: _openAudioSystemReview,
        ),
      if (_approvalRequired && !_allowExamOverride)
        _SetupStepData(
          number: _needsChecks ? 4 : 2,
          title: 'Request start approval',
          subtitle: _allChecksReady
              ? 'Send your completed checks for exam start approval.'
              : 'Complete the required checks first.',
          status: _approvalOk
              ? _StepStatus.complete
              : _requestingApproval
                  ? _StepStatus.running
                  : _StepStatus.pending,
          icon: Icons.verified_user_outlined,
          actionLabel: _requestingApproval
              ? 'Requesting approval...'
              : _approvalOk
                  ? 'Approval granted'
                  : 'Request approval',
          onPressed: _canRequestApproval(context) ? _requestApproval : null,
        ),
    ];

    if (steps.isEmpty) {
      return <_SetupStepData>[
        _SetupStepData(
          number: 1,
          title: 'Ready to start',
          subtitle: 'This activity uses standard access. You may begin when ready.',
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
            _clearApproval('Face ID was updated. Request start approval again.');
          }),
        ),
      ),
    );
    if (!mounted) return;
    setState(() {
      _faceId = _faceIdService.load();
      _clearApproval('Face ID check completed. Request start approval again.');
    });
  }

  Future<void> _openRoomScan() async {
    setState(() {
      _roomApproved = false;
      _manifestPath = null;
      _clearApproval('Room scan changed. Request start approval after all checks pass.');
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
                _clearApproval('Room scan was not approved. Run the scan again.');
              });
              return;
            }
            setState(() {
              _roomApproved = true;
              _manifestPath = manifestPath;
              _clearApproval('Room scan complete. Request start approval after all checks pass.');
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
      _clearApproval('Sound or device check changed. Request start approval again.');
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
      _approvalMessage = 'Checking saved records and exam setup...';
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
            ? 'Start approval granted. You may now begin.'
            : _friendlyApprovalMessage(result);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _requestingApproval = false;
        _startApproved = false;
        _startToken = null;
        _approvalMessage = 'Start approval could not be completed. Check your connection and try again.';
      });
    }
  }

  String _friendlyApprovalMessage(ExamStartApprovalResult result) {
    if (result.issues.isNotEmpty) return result.issues.join(' ');
    return result.message
        .replaceAll('Backend ', '')
        .replaceAll('backend ', '')
        .replaceAll('approved_to_start', 'approved to start')
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
        title: const Text('Activity cannot start yet'),
        content: const Text('Complete each required check, then request start approval before starting.'),
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
          'Graded assessments may be completed on phone, tablet, desktop, or laptop when allowed by the lecturer.',
        ),
        actions: [
          FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('OK')),
        ],
      ),
    );
  }

  String get _setupTitle {
    if (widget.assessment.isStrictExam) return 'Exam setup';
    if (widget.assessment.attendanceOnly) return 'Attendance practice';
    return 'Assessment setup';
  }

  String get _startLabel {
    if (widget.assessment.isStrictExam) return 'Start exam';
    if (widget.assessment.attendanceOnly) return 'Mark attendance and start';
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

class _Header extends StatelessWidget {
  const _Header({
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
          final wide = constraints.maxWidth >= 780;
          final main = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _DarkTag(assessment.isStrictExam ? 'Supervised exam' : assessment.graded ? 'Graded assessment' : 'Practice'),
                  _DarkTag('${assessment.durationMinutes} minutes'),
                  _DarkTag('$questionCount questions'),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                assessment.title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 31,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.4,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '${assessment.course.code} - ${assessment.course.title}',
                style: const TextStyle(color: Color(0xFFCBD5E1), fontSize: 16),
              ),
              const SizedBox(height: 6),
              Text(
                'Lecturer: ${assessment.course.lecturer}',
                style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 14),
              ),
            ],
          );

          final progressCard = Container(
            width: wide ? 260 : double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0x12FFFFFF),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: const Color(0x24FFFFFF)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      startReady ? Icons.check_circle : Icons.pending_actions_outlined,
                      color: startReady ? const Color(0xFF86EFAC) : const Color(0xFFBFDBFE),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        startReady ? 'Ready to start' : 'Setup in progress',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    minHeight: 9,
                    value: progress.clamp(0.0, 1.0),
                    backgroundColor: const Color(0x24FFFFFF),
                    color: startReady ? const Color(0xFF22C55E) : const Color(0xFF60A5FA),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  '$checksPassed of $requiredChecks checks ready',
                  style: const TextStyle(
                    color: Color(0xFFCBD5E1),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          );

          if (!wide) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [main, const SizedBox(height: 18), progressCard],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: main),
              const SizedBox(width: 24),
              progressCard,
            ],
          );
        },
      ),
    );
  }
}

class _SetupTimeline extends StatelessWidget {
  const _SetupTimeline({required this.steps});

  final List<_SetupStepData> steps;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xB3FFFFFF),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Required setup steps',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.3,
                ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Complete the steps below in order. Your activity will open only when the required checks are ready.',
            style: TextStyle(color: Color(0xFF64748B)),
          ),
          const SizedBox(height: 16),
          for (var index = 0; index < steps.length; index++) ...[
            _StepCard(step: steps[index]),
            if (index != steps.length - 1) const SizedBox(height: 12),
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
        ? const Color(0xFF16A34A)
        : running
            ? const Color(0xFF2563EB)
            : const Color(0xFF64748B);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: complete ? const Color(0xFFBBF7D0) : const Color(0xFFE2E8F0),
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x080F172A),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 560;
          final leading = Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: complete ? const Color(0xFFF0FDF4) : const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(18),
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
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(step.subtitle, style: const TextStyle(color: Color(0xFF64748B))),
              const SizedBox(height: 10),
              _StepStatusPill(status: step.status),
            ],
          );
          final action = FilledButton.icon(
            onPressed: step.onPressed,
            icon: Icon(complete ? Icons.refresh_rounded : Icons.arrow_forward_rounded, size: 18),
            label: Text(step.actionLabel),
          );

          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [leading, const SizedBox(width: 12), Expanded(child: text)],
                ),
                const SizedBox(height: 14),
                Align(
                  alignment: Alignment.centerRight,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 260),
                    child: SizedBox(width: double.infinity, child: action),
                  ),
                ),
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              leading,
              const SizedBox(width: 14),
              Expanded(child: text),
              const SizedBox(width: 16),
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
      child: Text(
        '$number',
        style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 12),
      ),
    );
  }
}

class _StepStatusPill extends StatelessWidget {
  const _StepStatusPill({required this.status});

  final _StepStatus status;

  @override
  Widget build(BuildContext context) {
    final color = status == _StepStatus.complete
        ? const Color(0xFF16A34A)
        : status == _StepStatus.running
            ? const Color(0xFF2563EB)
            : const Color(0xFF64748B);
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
          Text(
            label,
            style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _SetupSidePanel extends StatelessWidget {
  const _SetupSidePanel({
    required this.assessment,
    required this.approvalCard,
    required this.rules,
    required this.canStart,
    required this.startLabel,
    required this.onStart,
  });

  final DemoAssessment assessment;
  final Widget approvalCard;
  final Widget rules;
  final bool canStart;
  final String startLabel;
  final VoidCallback? onStart;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(26),
            border: Border.all(color: const Color(0xFFE2E8F0)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x080F172A),
                blurRadius: 18,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Start summary',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
              ),
              const SizedBox(height: 12),
              _SummaryLine(icon: Icons.book_outlined, label: assessment.course.code),
              _SummaryLine(icon: Icons.schedule_outlined, label: '${assessment.durationMinutes} minutes'),
              _SummaryLine(
                icon: Icons.security_outlined,
                label: assessment.remoteProctored ? 'Exam checks required' : 'Standard access',
              ),
              _SummaryLine(
                icon: Icons.rate_review_outlined,
                label: assessment.graded ? 'Submission will be reviewed' : 'Feedback / attendance activity',
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: onStart,
                  icon: Icon(canStart ? Icons.play_arrow_rounded : Icons.lock_outline_rounded),
                  label: Text(startLabel),
                ),
              ),
              if (!canStart) ...[
                const SizedBox(height: 10),
                const Text(
                  'Complete the required steps to unlock this button.',
                  style: TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.w700),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 14),
        approvalCard,
        const SizedBox(height: 14),
        rules,
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
          Icon(icon, size: 18, color: const Color(0xFF64748B)),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: Color(0xFF334155),
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ApprovalCard extends StatelessWidget {
  const _ApprovalCard({
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
        ? const Color(0xFF2563EB)
        : approved
            ? const Color(0xFF16A34A)
            : const Color(0xFFB45309);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: approved ? const Color(0xFFF0FDF4) : const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            requesting
                ? Icons.sync
                : approved
                    ? Icons.verified_user
                    : Icons.admin_panel_settings_outlined,
            color: color,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Start approval',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                ),
                const SizedBox(height: 6),
                Text(message),
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

class _OverrideNotice extends StatelessWidget {
  const _OverrideNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7ED),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFFDBA74)),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.science_outlined, color: Color(0xFFC2410C)),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Testing mode is active. This temporarily unlocks exam start so the writing, monitoring, timer, alert, and submission flow can be tested. Do not use this build for real exams.',
            ),
          ),
        ],
      ),
    );
  }
}

class _Rules extends StatelessWidget {
  const _Rules({required this.remote});

  final bool remote;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFFDE68A)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Before you start',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            remote
                ? 'Complete each setup check separately, then request start approval. The activity starts only after approval is granted.'
                : 'Keep your login secure and submit before the timer ends.',
          ),
        ],
      ),
    );
  }
}

class _DarkTag extends StatelessWidget {
  const _DarkTag(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF1F2937),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFF334155)),
      ),
      child: Text(
        text,
        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
      ),
    );
  }
}

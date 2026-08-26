import 'dart:async';

import 'package:flutter/material.dart';

import '../face_demo/demo_face_id_service.dart';
import '../face_demo/demo_face_id_view.dart';
import '../face_demo/face_identity_check_view.dart';
import '../proctoring_demo/audio_system_review_view.dart';
import '../proctoring_demo/audio_calibration_profile.dart';
import '../proctoring_demo/edge_ai_runtime_preflight_service.dart';
import '../proctoring_demo/gaze_calibration_view.dart';
import '../proctoring_demo/proctoring_demo_home.dart';
import '../rust/api/gaze_calibration.dart';
import 'demo_exam_attempt_view.dart';
import 'demo_exam_models.dart';
import 'demo_exam_service.dart';
import 'exam_start_approval_service.dart';
import 'exam_lockdown_service.dart';

const Color _brand = Color(0xFF0F4C81);
const Color _brandDark = Color(0xFF0B1220);
const Color _surface = Colors.white;
const Color _surfaceSoft = Color(0xFFF8FAFC);
const Color _line = Color(0xFFE2E8F0);
const Color _muted = Color(0xFF64748B);
const Color _success = Color(0xFF16A34A);
const Color _warning = Color(0xFFF59E0B);

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
  final AudioCalibrationProfileStore _audioProfileStore =
      AudioCalibrationProfileStore();
  final EdgeAiRuntimePreflightService _aiPreflight =
      EdgeAiRuntimePreflightService();
  final ExamLockdownService _lockdown = const ExamLockdownService();
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
  GazeCalibrationProfileV2? _gazeCalibration;
  EdgeAiRuntimePreflightResult? _aiRuntimeResult;
  bool _aiRuntimeChecking = false;
  bool _secureDeviceChecking = false;
  bool _secureDeviceReady = false;
  bool _readinessConfirmed = false;
  String _secureDeviceMessage =
      'Sound and secure-screen controls have not been checked.';

  @override
  void initState() {
    super.initState();
    _faceId = _faceIdService.load();
    _attemptId = 'attempt-${DateTime.now().millisecondsSinceEpoch}';
    _approvalService = ExamStartApprovalService(baseUrl: _baseUrl);
    if (_needsChecks) unawaited(_runAiPreflight());
    if (widget.assessment.graded) unawaited(_runSecureDeviceReadiness());
  }

  @override
  void dispose() {
    _approvalService.dispose();
    super.dispose();
  }

  // Enrollment (`_faceId.isComplete`) only proves a Face ID was set up at
  // some point; it is not evidence the person at this device right now is
  // that student. `_identityChecked` is the fresh, per-attempt 1:1
  // comparison and is reset whenever enrollment changes underneath it, so
  // it can never be satisfied by a stale check against a since-replaced
  // identity.
  bool _identityChecked = false;

  bool get _needsChecks =>
      widget.assessment.isStrictExam && widget.assessment.remoteProctored;
  bool get _faceOk =>
      !widget.assessment.graded || (_faceId.isComplete && _identityChecked);
  bool get _runtimeOk => !_needsChecks || _aiRuntimeResult?.ready == true;
  bool get _roomOk => !_needsChecks || (_roomApproved && _manifestPath != null);
  bool get _audioOk => !_needsChecks || _audioApproved;
  bool get _systemOk => !_needsChecks || _systemApproved;
  bool get _calibrationOk => !_needsChecks || _gazeCalibration?.usable == true;
  bool get _secureDeviceOk => !widget.assessment.graded || _secureDeviceReady;
  bool get _readinessChecksReady =>
      _runtimeOk &&
      _calibrationOk &&
      _roomOk &&
      _audioOk &&
      _systemOk &&
      _secureDeviceOk;
  bool get _allChecksReady =>
      _readinessChecksReady && _readinessConfirmed && _faceOk;
  bool get _approvalRequired => widget.assessment.remoteProctored;
  bool get _approvalOk =>
      _allowExamOverride ||
      !_approvalRequired ||
      (_startApproved && _startToken != null);

  bool _canStartOnDevice(BuildContext context) {
    final phoneSized = MediaQuery.sizeOf(context).shortestSide < 600;
    return !phoneSized || !widget.assessment.isStrictExam;
  }

  bool _canStart(BuildContext context) {
    if (!_canStartOnDevice(context)) return false;
    if (_allowExamOverride) return true;
    return _allChecksReady && _approvalOk;
  }

  void _clearApproval([String? message]) {
    _readinessConfirmed = false;
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
    final checksPassed = <bool>[
      _runtimeOk,
      _faceOk,
      _calibrationOk,
      _roomOk,
      _audioOk,
      _systemOk,
      _secureDeviceOk,
      _readinessConfirmed,
    ].where((passed) => passed).length;
    final requiredChecks = <bool>[
      _runtimeOk,
      _faceOk,
      _calibrationOk,
      _roomOk,
      _audioOk,
      _systemOk,
      _secureDeviceOk,
      _readinessConfirmed,
    ].length;

    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FB),
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        titleSpacing: 0,
        title: Text(
          _setupTitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 20),
        ),
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
          padding: EdgeInsets.fromLTRB(
            MediaQuery.sizeOf(context).width < 600 ? 14 : 20,
            MediaQuery.sizeOf(context).width < 600 ? 14 : 20,
            MediaQuery.sizeOf(context).width < 600 ? 14 : 20,
            120,
          ),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1120),
                child: Column(
                  children: [
                    _PreparationHero(
                      assessment: widget.assessment,
                      questionCount: questions.length,
                      checksPassed: checksPassed,
                      requiredChecks: requiredChecks,
                      startReady: _canStart(context),
                    ),
                    const SizedBox(height: 18),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final wide = constraints.maxWidth >= 940;
                        final steps = _PreparationSteps(
                          steps: _buildSteps(context),
                        );
                        final startPanel = _StartPanel(
                          assessment: widget.assessment,
                          ready:
                              !widget.assessment.graded && _canStart(context),
                          startLabel: widget.assessment.graded
                              ? 'Opens after identity confirmation'
                              : _allowExamOverride
                              ? 'Start now'
                              : _startLabel,
                          approvalCard: _ReadinessCard(
                            approved: _approvalOk,
                            requesting: _requestingApproval,
                            message: _approvalMessage,
                            result: _approvalResult,
                          ),
                          onStart:
                              !widget.assessment.graded && _canStart(context)
                              ? _startExam
                              : null,
                        );

                        if (!wide) {
                          return Column(
                            children: [
                              steps,
                              const SizedBox(height: 16),
                              startPanel,
                            ],
                          );
                        }
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(flex: 7, child: steps),
                            const SizedBox(width: 16),
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
    final steps = <_SetupStepData>[];
    var number = 0;
    if (_needsChecks) {
      steps.add(
        _SetupStepData(
          number: ++number,
          title: 'Edge AI runtime',
          subtitle: _aiRuntimeChecking
              ? 'Checking native models, secure Rust services, and the local Python intelligence runtime.'
              : _aiRuntimeResult?.ready == true
              ? 'All required on-device AI components passed integrity and runtime checks.'
              : _aiRuntimeResult?.blockingReasons.firstOrNull ??
                    'Verify the on-device AI runtime before continuing.',
          status: _aiRuntimeChecking
              ? _StepStatus.running
              : _runtimeOk
              ? _StepStatus.complete
              : _StepStatus.pending,
          icon: Icons.memory_outlined,
          actionLabel: _aiRuntimeChecking
              ? 'Checking...'
              : _runtimeOk
              ? 'Check again'
              : 'Run check',
          onPressed: _aiRuntimeChecking ? null : _runAiPreflight,
        ),
      );
      steps.add(
        _SetupStepData(
          number: ++number,
          title: 'Personal gaze calibration',
          subtitle:
              'Follow five screen markers so monitoring can use your normal '
              'eye and head position instead of generic thresholds.',
          status: _calibrationOk ? _StepStatus.complete : _StepStatus.pending,
          icon: Icons.center_focus_strong,
          actionLabel: _calibrationOk ? 'Calibrate again' : 'Start calibration',
          onPressed: _runtimeOk ? _openGazeCalibration : null,
        ),
      );
      steps.add(
        _SetupStepData(
          number: ++number,
          title: 'Camera and room check',
          subtitle:
              'Show your desk and exam area clearly before the exam begins.',
          status: _roomOk ? _StepStatus.complete : _StepStatus.pending,
          icon: Icons.photo_camera_front_outlined,
          actionLabel: _roomOk ? 'Check again' : 'Start check',
          onPressed: _runtimeOk ? _openRoomScan : null,
        ),
      );
      steps.add(
        _SetupStepData(
          number: ++number,
          title: 'Sound and device check',
          subtitle: _calibrationOk
              ? 'Confirm your microphone and device are ready for the assessment.'
              : 'Complete personal gaze calibration before microphone observation begins.',
          status: _audioOk && _systemOk
              ? _StepStatus.complete
              : _StepStatus.pending,
          icon: Icons.devices_outlined,
          actionLabel: _audioOk && _systemOk ? 'Check again' : 'Start check',
          onPressed: _runtimeOk && _calibrationOk
              ? _openAudioSystemReview
              : null,
        ),
      );
    }

    if (widget.assessment.graded) {
      steps.add(
        _SetupStepData(
          number: ++number,
          title: 'Phone security and sound',
          subtitle: _secureDeviceMessage,
          status: _secureDeviceChecking
              ? _StepStatus.running
              : _secureDeviceOk
              ? _StepStatus.complete
              : _StepStatus.pending,
          icon: Icons.phonelink_lock_outlined,
          actionLabel: _secureDeviceChecking
              ? 'Checking...'
              : _secureDeviceOk
              ? 'Check again'
              : 'Run secure check',
          onPressed: _secureDeviceChecking ? null : _runSecureDeviceReadiness,
        ),
      );
    }

    steps.add(
      _SetupStepData(
        number: ++number,
        title: 'Final readiness',
        subtitle: _readinessChecksReady
            ? 'Confirm you are ready. Identity verification comes next and the assessment opens immediately after it passes.'
            : 'Complete every device and environment check first.',
        status: _readinessConfirmed
            ? _StepStatus.complete
            : _StepStatus.pending,
        icon: Icons.fact_check_outlined,
        actionLabel: _readinessConfirmed ? 'Ready' : 'Confirm readiness',
        onPressed: _readinessChecksReady && !_readinessConfirmed
            ? _confirmReadiness
            : null,
      ),
    );

    if (widget.assessment.graded) {
      steps.add(
        _SetupStepData(
          number: ++number,
          title: 'Identity check — final step',
          subtitle: !_faceId.isComplete
              ? 'Set up Face ID before the assessment can begin.'
              : _identityChecked
              ? 'Identity confirmed. Opening the assessment securely...'
              : 'After confirmation, the assessment opens immediately and cannot be left before submission.',
          status: _faceOk ? _StepStatus.complete : _StepStatus.pending,
          icon: Icons.verified_user_outlined,
          actionLabel: !_faceId.isComplete
              ? 'Set up identity'
              : _identityChecked
              ? 'Opening...'
              : 'Confirm identity and start',
          onPressed: _readinessConfirmed
              ? (_faceId.isComplete ? _openIdentityCheck : _openFaceId)
              : null,
        ),
      );
    }

    return steps;
  }

  void _confirmReadiness() {
    if (!_readinessChecksReady) return;
    setState(() {
      _readinessConfirmed = true;
      _approvalMessage = widget.assessment.graded
          ? 'Readiness confirmed. Complete the final identity check to start.'
          : 'Everything is ready. You may begin.';
    });
    if (!widget.assessment.graded) unawaited(_startExam());
  }

  Future<void> _runSecureDeviceReadiness() async {
    if (_secureDeviceChecking) return;
    setState(() {
      _secureDeviceChecking = true;
      _secureDeviceReady = false;
      _readinessConfirmed = false;
      _secureDeviceMessage =
          'Checking sound, clipboard, and screen-capture protection...';
    });
    try {
      final result = await _lockdown.prepare();
      if (!mounted) return;
      setState(() {
        _secureDeviceChecking = false;
        _secureDeviceReady = result.ready;
        _secureDeviceMessage = result.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _secureDeviceChecking = false;
        _secureDeviceReady = false;
        _secureDeviceMessage =
            'Secure device readiness could not be completed. Try again.';
      });
    }
  }

  Future<void> _runAiPreflight() async {
    if (_aiRuntimeChecking) return;
    setState(() {
      _aiRuntimeChecking = true;
      _aiRuntimeResult = null;
      _clearApproval('Edge AI readiness is being checked.');
    });
    final result = await _aiPreflight.run();
    if (!mounted) return;
    setState(() {
      _aiRuntimeChecking = false;
      _aiRuntimeResult = result;
      if (!result.ready) {
        _clearApproval(
          'Edge AI is not ready: ${result.blockingReasons.firstOrNull ?? 'unknown runtime error'}',
        );
      }
    });
  }

  /// Opens enrollment. This is only reachable while the student has no
  /// completed enrollment yet; once enrolled, the "Identity check" step
  /// routes to [_openIdentityCheck] instead, never back here, so a student
  /// cannot re-enroll to replace an approved identity from the exam setup
  /// screen.
  Future<void> _openFaceId() async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => DemoFaceIdView(
          onComplete: () => setState(() {
            _faceId = _faceIdService.load();
            _identityChecked = false;
            _clearApproval(
              'Identity setup changed. Please confirm your identity again.',
            );
          }),
        ),
      ),
    );
    if (!mounted) return;
    setState(() {
      _faceId = _faceIdService.load();
      _identityChecked = false;
      _clearApproval(
        'Identity setup completed. Please confirm your identity before this attempt.',
      );
    });
  }

  /// Runs the fresh, per-attempt 1:1 identity check against the student's
  /// already-approved template. This never enrolls, never resets, and never
  /// searches across students — see [FaceIdentityCheckView].
  Future<void> _openIdentityCheck() async {
    final approved = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => FaceIdentityCheckView(
          examId: widget.assessment.id,
          attemptId: _attemptId,
        ),
      ),
    );
    if (!mounted) return;
    final confirmed = approved == true;
    setState(() {
      _identityChecked = confirmed;
      _approvalMessage = confirmed
          ? 'Identity confirmed. Opening the assessment securely...'
          : 'Identity was not confirmed. Please try again.';
    });
    if (confirmed) await _finalizeIdentityAndStart();
  }

  Future<void> _finalizeIdentityAndStart() async {
    if (_approvalRequired && !_allowExamOverride) {
      await _requestApproval();
      if (!mounted || !_approvalOk) return;
    }
    await _startExam();
  }

  Future<void> _openRoomScan() async {
    setState(() {
      _roomApproved = false;
      _manifestPath = null;
      _clearApproval(
        'Camera and room check changed. Please confirm readiness after all steps are complete.',
      );
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
                _clearApproval(
                  'Camera and room check was not completed. Please try again.',
                );
              });
              return;
            }
            setState(() {
              _roomApproved = true;
              _manifestPath = manifestPath;
              _clearApproval(
                'Camera and room check complete. Please confirm readiness after all steps are complete.',
              );
            });
            Navigator.of(context).pop();
          },
        ),
      ),
    );
  }

  Future<void> _openGazeCalibration() async {
    final profile = await Navigator.of(context).push<GazeCalibrationProfileV2>(
      MaterialPageRoute<GazeCalibrationProfileV2>(
        builder: (_) => GazeCalibrationView(
          studentId: _faceId.studentId,
          examId: widget.assessment.id,
          attemptId: _attemptId,
        ),
      ),
    );
    if (!mounted || profile == null) return;
    setState(() {
      _gazeCalibration = profile;
      _clearApproval(
        'Personal gaze calibration changed. Please confirm readiness again.',
      );
    });
  }

  Future<void> _openAudioSystemReview() async {
    if (!_calibrationOk) {
      return;
    }
    final result = await Navigator.of(context).push<AudioSystemReviewResult>(
      MaterialPageRoute<AudioSystemReviewResult>(
        builder: (_) => const AudioSystemReviewView(),
      ),
    );
    if (!mounted || result == null) return;
    final audioReview = result.audioReview;
    final audioProfile = result.audioReady && audioReview != null
        ? await _audioProfileStore.createAndSave(
            result: audioReview,
            studentId: _faceId.studentId,
            examId: widget.assessment.id,
            attemptId: _attemptId,
          )
        : null;
    if (!mounted) return;
    setState(() {
      _audioSystemReview = result;
      _audioApproved = result.audioReady && audioProfile?.usable == true;
      _systemApproved = result.systemReady;
      _clearApproval(
        'Sound or device check changed. Please confirm readiness again.',
      );
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
        audioReview:
            _audioSystemReview?.audioReview?.toJson() ??
            const <String, Object?>{},
        systemReview:
            _audioSystemReview?.systemReview?.toJson() ??
            const <String, Object?>{},
      );
      if (!mounted) return;
      setState(() {
        _requestingApproval = false;
        _approvalResult = result;
        _startApproved = result.approved && result.hasToken;
        _startToken = result.approved && result.hasToken
            ? result.examStartToken
            : null;
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
        _approvalMessage =
            'Readiness confirmation could not be completed. Check your connection and try again.';
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
    if (!_allowExamOverride &&
        (!_canStart(context) || (_approvalRequired && _startToken == null))) {
      await _showBlockedStartMessage();
      return;
    }
    if (widget.assessment.graded) {
      try {
        var secure = await _lockdown.enter();
        if (_lockdown.isAndroid && !secure.lockTaskActive) {
          for (var retry = 0; retry < 3 && !secure.lockTaskActive; retry++) {
            await Future<void>.delayed(const Duration(seconds: 1));
            secure = await _lockdown.prepare();
          }
        }
        if (!secure.ready || (_lockdown.isAndroid && !secure.lockTaskActive)) {
          if (!mounted) return;
          await showDialog<void>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Secure mode is not ready'),
              content: Text(
                !secure.ready
                    ? secure.message
                    : 'Allow Android screen pinning to prevent leaving the assessment before submission.',
              ),
              actions: [
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Try again'),
                ),
              ],
            ),
          );
          return;
        }
      } catch (_) {
        if (!mounted) return;
        await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Could not enter secure mode'),
            content: const Text(
              'Secure exam controls could not be enabled. Run the phone security check again.',
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('OK'),
              ),
            ],
          ),
        );
        return;
      }
    }
    if (!mounted) return;
    Navigator.of(context).pushReplacement<DemoExamResult, DemoExamResult>(
      MaterialPageRoute<DemoExamResult>(
        builder: (_) => DemoExamAttemptView(
          assessment: widget.assessment,
          proctoringManifestPath: _manifestPath,
          attemptId: _attemptId,
          examStartToken:
              _startToken ??
              (_allowExamOverride ? 'dev_override_$_attemptId' : ''),
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
  }

  Future<void> _showBlockedStartMessage() {
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Not ready yet'),
        content: const Text('Complete each required step before starting.'),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
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
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
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
    final compact = MediaQuery.sizeOf(context).width < 600;
    final progress = requiredChecks == 0 ? 1.0 : checksPassed / requiredChecks;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(compact ? 20 : 24),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1F0F172A),
            blurRadius: 26,
            offset: Offset(0, 14),
          ),
        ],
      ),
      child: Container(
        padding: EdgeInsets.all(compact ? 18 : 24),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [_brandDark, Color(0xFF113A63), _brand],
          ),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 780;
            final info = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _HeroTag(
                      assessment.isStrictExam
                          ? 'Supervised exam'
                          : assessment.graded
                          ? 'Graded assessment'
                          : 'Practice',
                    ),
                    _HeroTag('${assessment.durationMinutes} minutes'),
                    _HeroTag('$questionCount questions'),
                  ],
                ),
                const SizedBox(height: 16),
                const Text(
                  'Prepare before you start',
                  style: TextStyle(
                    color: Color(0xFFDBEAFE),
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  assessment.title,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: compact ? 24 : 30,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '${assessment.course.code} • ${assessment.course.title}',
                  style: const TextStyle(
                    color: Color(0xFFE2E8F0),
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  'Lecturer: ${assessment.course.lecturer}',
                  style: const TextStyle(
                    color: Color(0xFFCBD5E1),
                    fontWeight: FontWeight.w600,
                  ),
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
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [info, const SizedBox(height: 18), status],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: info),
                const SizedBox(width: 24),
                SizedBox(width: 275, child: status),
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
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w800,
        ),
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
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                startReady
                    ? Icons.check_circle
                    : Icons.pending_actions_outlined,
                color: startReady
                    ? const Color(0xFF86EFAC)
                    : const Color(0xFFBFDBFE),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  startReady ? 'Ready to start' : 'Preparation in progress',
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
              backgroundColor: Colors.white.withValues(alpha: 0.18),
              color: startReady
                  ? const Color(0xFF22C55E)
                  : const Color(0xFF60A5FA),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            '$checksPassed of $requiredChecks steps ready',
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

class _PreparationSteps extends StatelessWidget {
  const _PreparationSteps({required this.steps});

  final List<_SetupStepData> steps;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 600;
    return Container(
      padding: EdgeInsets.all(compact ? 14 : 18),
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
            'Preparation steps',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: _brandDark,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 5),
          const Text(
            'Complete readiness first. Identity is the final step and starts the assessment immediately.',
            style: TextStyle(color: _muted, fontWeight: FontWeight.w600),
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
    final phone = MediaQuery.sizeOf(context).width < 600;
    final complete = step.status == _StepStatus.complete;
    final running = step.status == _StepStatus.running;
    final accent = complete
        ? _success
        : running
        ? _brand
        : _muted;
    return Container(
      padding: EdgeInsets.all(phone ? 13 : 16),
      decoration: BoxDecoration(
        color: complete ? const Color(0xFFF0FDF4) : _surfaceSoft,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: complete ? const Color(0xFFBBF7D0) : _line),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 560;
          final leading = Container(
            width: phone ? 44 : 50,
            height: phone ? 44 : 50,
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
                      style: TextStyle(
                        color: _brandDark,
                        fontSize: phone ? 16 : 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                step.subtitle,
                style: const TextStyle(
                  color: _muted,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 10),
              _StepStatusPill(status: step.status),
            ],
          );
          final action = FilledButton.icon(
            onPressed: step.onPressed,
            style: FilledButton.styleFrom(
              backgroundColor: complete ? Colors.white : _brand,
              foregroundColor: complete ? _brand : Colors.white,
              side: complete ? const BorderSide(color: _line) : BorderSide.none,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            icon: Icon(
              complete ? Icons.refresh_rounded : Icons.arrow_forward_rounded,
              size: 18,
            ),
            label: Text(step.actionLabel),
          );

          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    leading,
                    const SizedBox(width: 12),
                    Expanded(child: text),
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
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w900,
          fontSize: 12,
        ),
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
        ? _success
        : status == _StepStatus.running
        ? _brand
        : _muted;
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
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w900,
              fontSize: 12,
            ),
          ),
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
                'Start summary',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: _brandDark,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 12),
              _SummaryLine(
                icon: Icons.book_outlined,
                label: assessment.course.code,
              ),
              _SummaryLine(
                icon: Icons.schedule_outlined,
                label: '${assessment.durationMinutes} minutes',
              ),
              _SummaryLine(
                icon: Icons.check_circle_outline,
                label: assessment.remoteProctored
                    ? 'Preparation required'
                    : 'Standard access',
              ),
              _SummaryLine(
                icon: Icons.rate_review_outlined,
                label: assessment.graded
                    ? 'Submission will be reviewed'
                    : 'Feedback activity',
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: onStart,
                  style: FilledButton.styleFrom(
                    backgroundColor: ready ? _brand : const Color(0xFFCBD5E1),
                    foregroundColor: ready
                        ? Colors.white
                        : const Color(0xFF475569),
                    minimumSize: const Size.fromHeight(52),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    textStyle: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  icon: Icon(
                    ready
                        ? Icons.play_arrow_rounded
                        : Icons.lock_outline_rounded,
                  ),
                  label: Text(startLabel),
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
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: _brandDark,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                Text(message, style: const TextStyle(color: Color(0xFF334155))),
                if (result != null &&
                    !approved &&
                    result!.issues.isNotEmpty) ...[
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
        color: _surfaceSoft,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _line),
      ),
      child: const Text(
        'Sit in a quiet place, keep your device charged, and stay on the assessment screen until you submit.',
        style: TextStyle(
          color: _muted,
          height: 1.45,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

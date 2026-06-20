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
  bool get _approvalRequired => widget.assessment.remoteProctored || widget.assessment.graded;
  bool get _approvalOk => _allowExamOverride || !_approvalRequired || (_startApproved && _startToken != null);

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
    return Scaffold(
      appBar: AppBar(title: Text(_setupTitle)),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          _Header(assessment: widget.assessment, questionCount: questions.length),
          const SizedBox(height: 14),
          if (_allowExamOverride) ...[
            const _OverrideNotice(),
            const SizedBox(height: 14),
          ],
          _Checklist(
            faceOk: _faceOk,
            roomOk: _roomOk,
            audioOk: _audioOk,
            systemOk: _systemOk,
            approvalOk: _approvalOk,
            needsChecks: _needsChecks,
            approvalRequired: _approvalRequired,
          ),
          const SizedBox(height: 14),
          _ApprovalCard(
            approved: _approvalOk,
            requesting: _requestingApproval,
            message: _approvalMessage,
            result: _approvalResult,
          ),
          const SizedBox(height: 14),
          _Rules(remote: widget.assessment.remoteProctored),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              if (widget.assessment.graded)
                FilledButton.icon(
                  onPressed: _openFaceId,
                  icon: const Icon(Icons.face_retouching_natural),
                  label: Text(_faceId.isComplete ? 'Face ID active' : 'Set up Face ID'),
                ),
              if (_needsChecks)
                FilledButton.icon(
                  onPressed: _openRoomScan,
                  icon: const Icon(Icons.screen_rotation_alt_outlined),
                  label: Text(_roomOk ? '360 room scan complete' : 'Run 360 room scan'),
                ),
              if (_needsChecks)
                FilledButton.icon(
                  onPressed: _openAudioSystemReview,
                  icon: const Icon(Icons.settings_voice_outlined),
                  label: Text(
                    _audioApproved && _systemApproved
                        ? 'Sound and device check complete'
                        : 'Run sound and device check',
                  ),
                ),
              if (_approvalRequired && !_allowExamOverride)
                FilledButton.icon(
                  onPressed: _canRequestApproval(context) ? _requestApproval : null,
                  icon: const Icon(Icons.verified_user_outlined),
                  label: Text(
                    _requestingApproval
                        ? 'Requesting approval...'
                        : _approvalOk
                            ? 'Start approval granted'
                            : 'Request start approval',
                  ),
                ),
              FilledButton.icon(
                onPressed: _canStart(context) ? _startExam : null,
                icon: const Icon(Icons.edit_document),
                label: Text(_allowExamOverride ? 'Start exam for testing' : _startLabel),
              ),
              OutlinedButton.icon(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.arrow_back),
                label: const Text('Back'),
              ),
            ],
          ),
        ],
      ),
    );
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
      MaterialPageRoute<AudioSystemReviewResult>(builder: (_) => const AudioSystemReviewView()),
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
            ? 'Start approval granted. You may now begin the exam.'
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
        title: const Text('Exam cannot start yet'),
        content: const Text('Complete each required check, then request start approval before starting the exam.'),
        actions: [FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('OK'))],
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
        actions: [FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('OK'))],
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

class _Header extends StatelessWidget {
  const _Header({required this.assessment, required this.questionCount});
  final DemoAssessment assessment;
  final int questionCount;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: const Color(0xFF111827), borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(assessment.title, style: Theme.of(context).textTheme.headlineSmall?.copyWith(color: Colors.white, fontWeight: FontWeight.w900)),
          const SizedBox(height: 6),
          Text('${assessment.course.code} - ${assessment.course.title}', style: const TextStyle(color: Color(0xFFCBD5E1), fontSize: 16)),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _DarkTag('${assessment.durationMinutes} minutes'),
              _DarkTag('$questionCount questions'),
              _DarkTag(assessment.graded ? 'Official graded' : 'Practice'),
              _DarkTag(assessment.remoteProctored ? 'Full exam check required' : 'Standard access'),
            ],
          ),
        ],
      ),
    );
  }
}

class _Checklist extends StatelessWidget {
  const _Checklist({
    required this.faceOk,
    required this.roomOk,
    required this.audioOk,
    required this.systemOk,
    required this.approvalOk,
    required this.needsChecks,
    required this.approvalRequired,
  });

  final bool faceOk;
  final bool roomOk;
  final bool audioOk;
  final bool systemOk;
  final bool approvalOk;
  final bool needsChecks;
  final bool approvalRequired;

  @override
  Widget build(BuildContext context) {
    final rows = <_CheckRow>[
      _CheckRow('Face ID', faceOk),
      if (needsChecks) _CheckRow('360 room scan', roomOk),
      if (needsChecks) _CheckRow('Sound check', audioOk),
      if (needsChecks) _CheckRow('Device check', systemOk),
      if (approvalRequired) _CheckRow('Start approval', approvalOk),
    ];
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFE2E8F0))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Startup checklist', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
          const SizedBox(height: 12),
          ...rows,
        ],
      ),
    );
  }
}

class _CheckRow extends StatelessWidget {
  const _CheckRow(this.label, this.ok);
  final String label;
  final bool ok;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(ok ? Icons.check_circle : Icons.radio_button_unchecked, color: ok ? const Color(0xFF16A34A) : const Color(0xFF94A3B8)),
          const SizedBox(width: 8),
          Text(label),
        ],
      ),
    );
  }
}

class _ApprovalCard extends StatelessWidget {
  const _ApprovalCard({required this.approved, required this.requesting, required this.message, required this.result});
  final bool approved;
  final bool requesting;
  final String message;
  final ExamStartApprovalResult? result;

  @override
  Widget build(BuildContext context) {
    final color = requesting ? const Color(0xFF2563EB) : approved ? const Color(0xFF16A34A) : const Color(0xFFB45309);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: approved ? const Color(0xFFF0FDF4) : const Color(0xFFFFFBEB), borderRadius: BorderRadius.circular(12), border: Border.all(color: color.withOpacity(0.35))),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(requesting ? Icons.sync : approved ? Icons.verified_user : Icons.admin_panel_settings_outlined, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Start approval', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
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
        borderRadius: BorderRadius.circular(12),
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
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: const Color(0xFFFFFBEB), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFFDE68A))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Rules before you start', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          Text(remote ? 'Complete each setup check separately, then request start approval. The exam starts only after approval is granted.' : 'Keep your login secure and submit before the timer ends.'),
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
      decoration: BoxDecoration(color: const Color(0xFF1F2937), borderRadius: BorderRadius.circular(999)),
      child: Text(text, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
    );
  }
}

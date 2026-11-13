import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../auth/student_session.dart';
import 'face_embedding_pipeline.dart';
import 'face_identity_liveness_gate.dart';
import 'face_identity_verification_service.dart';
import 'identity_evidence.dart';
import 'official_identity_session.dart';
import 'windows_speech_prompt_service.dart';

/// What the identity check screen returns to its caller.
class FaceIdentityCheckResult {
  const FaceIdentityCheckResult._({
    required this.passed,
    required this.exhausted,
    this.evidenceRecordId = '',
    this.templateId = '',
    this.problem = OfficialIdentityProblem.none,
  });

  const FaceIdentityCheckResult.passed({
    required String evidenceRecordId,
    required String templateId,
  }) : this._(
         passed: true,
         exhausted: false,
         evidenceRecordId: evidenceRecordId,
         templateId: templateId,
       );

  /// Every allowed attempt was used without a pass. The student must contact
  /// the invigilator; this is never a misconduct decision by itself.
  const FaceIdentityCheckResult.exhausted({required String evidenceRecordId})
    : this._(
        passed: false,
        exhausted: true,
        evidenceRecordId: evidenceRecordId,
      );

  const FaceIdentityCheckResult.notReady(OfficialIdentityProblem problem)
    : this._(passed: false, exhausted: false, problem: problem);

  const FaceIdentityCheckResult.cancelled()
    : this._(passed: false, exhausted: false);

  final bool passed;
  final bool exhausted;
  final String evidenceRecordId;
  final String templateId;

  /// Why the check could not start (no approved Face ID, school offline...).
  final OfficialIdentityProblem problem;
}

/// The 1:1 identity check a student must pass before an exam opens, and
/// again whenever an in-exam check pauses the exam.
///
/// It compares the person in front of the camera with exactly one template:
/// the signed-in student's official, school-approved Face ID. The liveness
/// challenge and the identity match use the same camera frames.
class FaceIdentityCheckView extends StatefulWidget {
  const FaceIdentityCheckView({
    super.key,
    required this.examId,
    required this.attemptId,
    this.kind = IdentityCheckKind.preExam,
    this.studentId,
    this.allowCancel = true,
    this.maxFailedAttempts = 3,
  });

  final String examId;
  final String attemptId;
  final IdentityCheckKind kind;

  /// Defaults to the signed-in student.
  final String? studentId;
  final bool allowCancel;
  final int maxFailedAttempts;

  @override
  State<FaceIdentityCheckView> createState() => _FaceIdentityCheckViewState();
}

enum _CheckStage {
  loadingTemplate,
  notReady,
  ready,
  running,
  passed,
  exhausted,
}

class _FaceIdentityCheckViewState extends State<FaceIdentityCheckView> {
  final FaceEmbeddingPipeline _pipeline = FaceEmbeddingPipeline();
  final FaceIdentityLivenessGate _livenessGate = FaceIdentityLivenessGate();
  final FaceIdentityVerificationService _verificationService =
      const FaceIdentityVerificationService();
  final WindowsSpeechPromptService _speech = WindowsSpeechPromptService();

  static const int _samplesWanted = 3;
  static const int _maxBoundFrames = 6;
  static const int _maxFreshStills = 2;
  static const Duration _freshStillWindow = Duration(seconds: 4);

  late final String _studentId = widget.studentId ?? StudentSession.studentId;
  CameraController? _controller;
  OfficialFaceTemplateContext? _template;
  OfficialIdentityProblem _problem = OfficialIdentityProblem.none;
  _CheckStage _stage = _CheckStage.loadingTemplate;
  String _message = 'Loading your official Face ID...';
  FaceIdentityCheckOutcome? _lastOutcome;
  String _lastEvidenceId = '';
  bool _leaving = false;
  int _failedAttempts = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_loadTemplate());
  }

  @override
  void dispose() {
    _controller?.dispose();
    unawaited(_speech.dispose());
    super.dispose();
  }

  Future<void> _loadTemplate() async {
    setState(() {
      _stage = _CheckStage.loadingTemplate;
      _message = 'Loading your official Face ID...';
    });
    final session = OfficialIdentitySession.instance;
    OfficialFaceTemplateContext? context;
    var message = '';
    var problem = OfficialIdentityProblem.none;
    if (widget.kind != IdentityCheckKind.preExam) {
      // Rechecks during an exam use the template verified at exam start, so
      // a network drop cannot block a paused student from resuming.
      context =
          session.activeFor(_studentId) ??
          await session.restoreCached(_studentId);
    }
    if (context == null) {
      final loaded = await session.loadForExam(_studentId);
      context = loaded.context;
      message = loaded.message;
      problem = loaded.problem;
    }
    if (!mounted) return;
    if (context == null) {
      setState(() {
        _stage = _CheckStage.notReady;
        _problem = problem;
        _message = message;
      });
      return;
    }
    setState(() {
      _template = context;
      _stage = _CheckStage.ready;
      _message = 'Look at the camera, then start the identity check.';
    });
    await _openCamera();
  }

  Future<void> _openCamera() async {
    if (_controller?.value.isInitialized ?? false) return;
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        if (!mounted) return;
        setState(
          () => _message =
              'No camera was found. The identity check needs a camera.',
        );
        return;
      }
      final selected = cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        selected,
        ResolutionPreset.medium,
        enableAudio: false,
      );
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() => _controller = controller);
    } catch (error) {
      if (!mounted) return;
      setState(() => _message = 'The camera could not open: $error');
    }
  }

  Future<void> _runCheck() async {
    final controller = _controller;
    final template = _template;
    if (_stage == _CheckStage.running ||
        template == null ||
        controller == null ||
        !controller.value.isInitialized) {
      return;
    }
    setState(() {
      _stage = _CheckStage.running;
      _message = 'Get ready...';
      _lastOutcome = null;
    });
    try {
      final burst = await _livenessGate.runBoundBurst(
        controller: controller,
        keepFrames: _maxBoundFrames,
        onChallengeStarted: (session) {
          if (!mounted) return;
          setState(() => _message = session.instruction);
          unawaited(_speech.speak(session.instruction));
        },
      );
      if (!mounted) return;
      final burstEndedAt = DateTime.now();
      final reviewPhoto = burst.frames.isEmpty
          ? null
          : burst.frames.first.encodedImage;

      if (!burst.passed) {
        final outcome = FaceIdentityCheckOutcome.livenessFailed(
          burst.result.reason,
        );
        await _finishAttempt(
          outcome,
          burst: burst,
          samplesAttempted: 0,
          boundFrames: 0,
          reviewPhoto: reviewPhoto,
        );
        return;
      }

      final aiAvailable = await _pipeline.initialize();
      if (!mounted) return;
      setState(() => _message = 'Hold still. Checking your identity...');
      final outcomes = <FaceIdentityCheckOutcome>[];
      var boundReliable = 0;
      var boundMatched = 0;
      var attempted = 0;
      for (final frame in burst.frames) {
        if (_reliableCount(outcomes) >= _samplesWanted) break;
        attempted++;
        final outcome = await _evaluate(
          frame.encodedImage,
          aiAvailable,
          template,
        );
        outcomes.add(outcome);
        if (_isReliable(outcome)) boundReliable++;
        if (outcome.verified) boundMatched++;
        if (outcome.state == FaceIdentityCheckState.aiUnavailable) break;
      }
      // Fresh stills are only a top-up for bound frames that were too
      // blurred to use, taken straight after the challenge. A pass still
      // needs at least one matching frame from inside the challenge itself.
      var fresh = 0;
      while (aiAvailable &&
          boundReliable > 0 &&
          _reliableCount(outcomes) < _samplesWanted &&
          fresh < _maxFreshStills &&
          DateTime.now().difference(burstEndedAt) < _freshStillWindow) {
        fresh++;
        attempted++;
        final XFile file;
        try {
          file = await controller.takePicture();
        } catch (_) {
          break;
        }
        outcomes.add(
          await _evaluate(
            await File(file.path).readAsBytes(),
            aiAvailable,
            template,
          ),
        );
      }
      var outcome = aiAvailable
          ? _verificationService.evaluateConsensus(outcomes: outcomes)
          : FaceIdentityCheckOutcome.aiUnavailable(
              'Face identity AI is unavailable on this device.',
            );
      if (outcome.verified && boundMatched == 0) {
        outcome = FaceIdentityCheckOutcome.qualityRetry(
          'Keep your face in view during the whole check and try again.',
        );
      }
      await _finishAttempt(
        outcome,
        burst: burst,
        samplesAttempted: attempted,
        boundFrames: boundReliable,
        reviewPhoto: reviewPhoto,
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _stage = _CheckStage.ready;
        _message = 'The identity check could not run: $error';
      });
    }
  }

  Future<FaceIdentityCheckOutcome> _evaluate(
    Uint8List encoded,
    bool aiAvailable,
    OfficialFaceTemplateContext template,
  ) async {
    final sample = aiAvailable
        ? await _pipeline.processEncodedImage(encoded)
        : null;
    return _verificationService.evaluateSample(
      aiAvailable: aiAvailable,
      sample: sample,
      pipelineFailureReason: _pipeline.lastFailureReason,
      template: template,
    );
  }

  static bool _isReliable(FaceIdentityCheckOutcome outcome) =>
      outcome.state == FaceIdentityCheckState.verified ||
      outcome.state == FaceIdentityCheckState.mismatch;

  static int _reliableCount(List<FaceIdentityCheckOutcome> outcomes) =>
      outcomes.where(_isReliable).length;

  Future<void> _finishAttempt(
    FaceIdentityCheckOutcome outcome, {
    required BoundLivenessBurst burst,
    required int samplesAttempted,
    required int boundFrames,
    required Uint8List? reviewPhoto,
  }) async {
    final evidenceId = await _recordEvidence(
      outcome,
      burst: burst,
      samplesAttempted: samplesAttempted,
      boundFrames: boundFrames,
      reviewPhoto: reviewPhoto,
    );
    if (!mounted) return;
    if (outcome.countsAsFailure) _failedAttempts++;
    final exhausted =
        !outcome.verified && _failedAttempts >= widget.maxFailedAttempts;
    final remaining = widget.maxFailedAttempts - _failedAttempts;
    final triesLeft = '($remaining ${remaining == 1 ? 'try' : 'tries'} left)';
    setState(() {
      _lastOutcome = outcome;
      _lastEvidenceId = evidenceId;
      _stage = outcome.verified
          ? _CheckStage.passed
          : exhausted
          ? _CheckStage.exhausted
          : _CheckStage.ready;
      _message = switch (outcome.state) {
        FaceIdentityCheckState.verified => 'Identity confirmed.',
        _ when exhausted =>
          'Your identity could not be confirmed. Please contact your '
              'invigilator. Your attempts have been recorded for review.',
        FaceIdentityCheckState.mismatch =>
          'Your face did not match your official Face ID. Make sure your '
              'face is well lit and fully visible, then try again $triesLeft.',
        FaceIdentityCheckState.livenessFailed =>
          'The live check was not completed: ${outcome.reason} Try again '
              '$triesLeft.',
        FaceIdentityCheckState.aiUnavailable =>
          'Face identity AI is unavailable on this device. Please contact '
              'your invigilator.',
        FaceIdentityCheckState.qualityRetry ||
        FaceIdentityCheckState.uncertain =>
          '${outcome.reason} This try was not counted.',
      };
    });
    if (outcome.verified) {
      await _speech.speak('Identity confirmed.');
      await Future<void>.delayed(const Duration(milliseconds: 1200));
      await _finish(
        FaceIdentityCheckResult.passed(
          evidenceRecordId: evidenceId,
          templateId: _template?.templateId ?? '',
        ),
      );
    }
  }

  Future<String> _recordEvidence(
    FaceIdentityCheckOutcome outcome, {
    required BoundLivenessBurst burst,
    required int samplesAttempted,
    required int boundFrames,
    required Uint8List? reviewPhoto,
  }) async {
    try {
      final outbox = await SchoolIdentityServices.instance.outbox();
      final record = await outbox.record(
        IdentityEvidenceDraft(
          kind: widget.kind,
          studentId: _studentId,
          examId: widget.examId,
          attemptId: widget.attemptId,
          outcome: outcome,
          samplesAttempted: samplesAttempted,
          template: _template,
          liveness: burst.result,
          boundIdentityFrames: boundFrames,
          reviewPhotoJpeg: reviewPhoto,
          policy: <String, Object?>{
            'match_threshold': _verificationService.matchThreshold,
            'min_signal_quality': _verificationService.minSignalQuality,
            'max_failed_attempts': widget.maxFailedAttempts,
            'failed_attempts_before': _failedAttempts,
          },
        ),
      );
      unawaited(_flushEvidence(outbox));
      return record['record_id']?.toString() ?? '';
    } catch (_) {
      // Evidence storage problems must not decide the identity result.
      return '';
    }
  }

  Future<void> _flushEvidence(IdentityEvidenceOutbox outbox) async {
    try {
      await outbox.flush(await SchoolIdentityServices.instance.school());
    } catch (_) {
      // Queued records upload on a later check.
    }
  }

  Future<void> _finish(FaceIdentityCheckResult result) async {
    if (_leaving || !mounted) return;
    _leaving = true;
    final controller = _controller;
    setState(() => _controller = null);
    await controller?.dispose();
    if (!mounted) return;
    Navigator.of(context).pop(result);
  }

  String get _notReadyButtonLabel => switch (_problem) {
    OfficialIdentityProblem.notSubmitted ||
    OfficialIdentityProblem.rejected => 'Go back and register Face ID',
    OfficialIdentityProblem.schoolUnavailable => 'Try again',
    _ => 'Go back',
  };

  @override
  Widget build(BuildContext context) {
    final ready = _controller?.value.isInitialized ?? false;
    final canLeave = widget.allowCancel && _stage != _CheckStage.running;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && canLeave) {
          _finish(const FaceIdentityCheckResult.cancelled());
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF07111F),
        appBar: AppBar(
          title: const Text('Confirm your identity'),
          backgroundColor: Colors.white,
          automaticallyImplyLeading: false,
          leading: widget.allowCancel
              ? IconButton(
                  icon: const Icon(Icons.arrow_back_rounded),
                  onPressed: canLeave
                      ? () => _finish(const FaceIdentityCheckResult.cancelled())
                      : null,
                )
              : null,
        ),
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AspectRatio(
                        aspectRatio: 4 / 3,
                        child: Container(
                          clipBehavior: Clip.antiAlias,
                          decoration: BoxDecoration(
                            color: const Color(0xFF0B1220),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: ready
                              ? CameraPreview(_controller!)
                              : Center(
                                  child: Icon(
                                    _stage == _CheckStage.notReady
                                        ? Icons.person_off_outlined
                                        : Icons.face_retouching_natural,
                                    color: Colors.white54,
                                    size: 48,
                                  ),
                                ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _message,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                height: 1.4,
                              ),
                            ),
                            if (_stage == _CheckStage.ready &&
                                _lastOutcome == null) ...[
                              const SizedBox(height: 8),
                              Text(
                                'You have ${widget.maxFailedAttempts} tries. '
                                'Your result is saved on this device and '
                                'sent to your school as evidence.',
                                style: const TextStyle(
                                  color: Color(0xFF64748B),
                                  height: 1.4,
                                ),
                              ),
                            ],
                            const SizedBox(height: 16),
                            _primaryAction(ready),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _primaryAction(bool cameraReady) {
    switch (_stage) {
      case _CheckStage.notReady:
        return FilledButton.icon(
          onPressed: _problem == OfficialIdentityProblem.schoolUnavailable
              ? _loadTemplate
              : () => _finish(FaceIdentityCheckResult.notReady(_problem)),
          icon: Icon(
            _problem == OfficialIdentityProblem.schoolUnavailable
                ? Icons.refresh
                : Icons.arrow_back,
          ),
          label: Text(_notReadyButtonLabel),
        );
      case _CheckStage.exhausted:
        return FilledButton.icon(
          onPressed: () => _finish(
            FaceIdentityCheckResult.exhausted(
              evidenceRecordId: _lastEvidenceId,
            ),
          ),
          icon: const Icon(Icons.support_agent),
          label: const Text('Close'),
        );
      case _CheckStage.loadingTemplate:
      case _CheckStage.ready:
      case _CheckStage.running:
      case _CheckStage.passed:
        return FilledButton.icon(
          onPressed: cameraReady && _stage == _CheckStage.ready
              ? _runCheck
              : null,
          icon: Icon(
            _stage == _CheckStage.running
                ? Icons.hourglass_top
                : Icons.verified_user_outlined,
          ),
          label: Text(
            _stage == _CheckStage.running
                ? 'Checking...'
                : _lastOutcome == null
                ? 'Start identity check'
                : 'Try again',
          ),
        );
    }
  }
}

import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import 'demo_face_id_service.dart';
import 'face_embedding_pipeline.dart';
import 'face_identity_liveness_gate.dart';
import 'face_identity_verification_service.dart';
import 'face_live_capture_engine.dart';
import 'native_face_embedding_runtime.dart';
import 'windows_speech_prompt_service.dart';
import '../rust/api/face_verification.dart';

/// The 1:1 identity check a student must pass immediately before writing an
/// exam attempt.
///
/// This is deliberately a separate screen from [DemoFaceIdView] (the
/// enrollment wizard). Enrollment happens once; this check happens every
/// time the student is about to write an exam. It never captures new
/// enrollment samples, never writes to [DemoFaceIdService], and never
/// searches across students — it loads exactly one locked template (the one
/// already approved for this student on this device) and asks only whether
/// the person in front of the camera right now matches it.
class FaceIdentityCheckView extends StatefulWidget {
  const FaceIdentityCheckView({
    super.key,
    required this.examId,
    required this.attemptId,
    this.allowCancel = true,
    this.maxFailedAttempts,
  });

  final String examId;
  final String attemptId;
  final bool allowCancel;
  final int? maxFailedAttempts;

  @override
  State<FaceIdentityCheckView> createState() => _FaceIdentityCheckViewState();
}

enum _CheckStage { loadingTemplate, noApprovedIdentity, ready, running, passed }

class _FaceIdentityCheckViewState extends State<FaceIdentityCheckView> {
  final FaceEmbeddingPipeline _pipeline = FaceEmbeddingPipeline();
  final FaceIdentityLivenessGate _livenessGate = FaceIdentityLivenessGate();
  final FaceIdentityVerificationService _verificationService =
      const FaceIdentityVerificationService();
  final FaceLiveCaptureEngine _liveCaptureEngine = FaceLiveCaptureEngine();
  final WindowsSpeechPromptService _speech = WindowsSpeechPromptService();
  final String _studentId = DemoFaceIdService.studentId;

  // Consecutive live-stream frames that must all pass the quality gate
  // before a verification sample is actually captured. Mirrors the same
  // cycle enrollment's `FaceLiveCaptureEngine` uses: a photo is only taken
  // once the camera has settled on a genuinely good frame, instead of
  // snapping on a fixed timer and hoping the frame was usable. Feeding the
  // matcher steadier, better-aligned samples narrows the embedding noise
  // that a marginal capture could otherwise let a false match slip through.
  static const int _liveCaptureStabilityFrames = 3;
  static const int _maxCaptureRetries = 8;
  int _liveConsecutiveGoodFrames = 0;

  CameraController? _controller;
  String? _templateJson;
  _CheckStage _stage = _CheckStage.loadingTemplate;
  String _message = 'Loading your approved identity...';
  FaceIdentityCheckOutcome? _lastOutcome;
  bool _leaving = false;
  int _failedAttempts = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_loadTemplate());
  }

  @override
  void dispose() {
    unawaited(_liveCaptureEngine.stop());
    _controller?.dispose();
    unawaited(_speech.dispose());
    super.dispose();
  }

  Future<void> _loadTemplate() async {
    final stored = await NativeFaceEmbeddingRuntime().loadProtectedTemplate(
      studentId: _studentId,
    );
    if (!mounted) return;
    if (stored == null || stored.isEmpty) {
      setState(() {
        _stage = _CheckStage.noApprovedIdentity;
        _message =
            'No approved identity was found on this device. Complete '
            'identity setup before this exam.';
      });
      return;
    }
    final status = validatePortableFaceTemplate(
      templateJson: stored,
      expectedStudentId: _studentId,
      expectedModelId: NativeFaceEmbeddingRuntime.modelId,
      expectedModelSha256: NativeFaceEmbeddingRuntime.modelSha256,
      nowMs: DateTime.now().toUtc().millisecondsSinceEpoch,
    );
    if (!status.valid) {
      setState(() {
        _stage = _CheckStage.noApprovedIdentity;
        _message =
            'The approved identity on this device is not valid (${status.reason}). '
            'Complete identity setup again before this exam.';
      });
      return;
    }
    setState(() {
      _templateJson = stored;
      _stage = _CheckStage.ready;
      _message = 'Look at the camera to confirm your identity.';
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
              'No camera was found. Identity check requires a camera.',
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
      if (!mounted) return;
      setState(() => _controller = controller);
    } catch (error) {
      if (!mounted) return;
      setState(() => _message = 'Camera could not open: $error');
    }
  }

  Future<void> _runCheck() async {
    final controller = _controller;
    final templateJson = _templateJson;
    if (_stage == _CheckStage.running ||
        templateJson == null ||
        controller == null ||
        !controller.value.isInitialized) {
      return;
    }
    setState(() {
      _stage = _CheckStage.running;
      _message = 'Get ready to confirm liveness...';
      _lastOutcome = null;
    });
    try {
      final liveness = await _livenessGate.runBurst(
        controller: controller,
        onChallengeStarted: (session) {
          if (!mounted) return;
          setState(() => _message = session.instruction);
          unawaited(_speech.speak(session.instruction));
        },
      );
      if (!mounted) return;
      if (liveness.state != 'live_challenge_passed') {
        setState(() {
          _stage = _CheckStage.ready;
          _message = 'Liveness could not be confirmed: ${liveness.reason}';
        });
        _failedAttempts++;
        final limit = widget.maxFailedAttempts;
        if (limit != null && _failedAttempts >= limit) {
          await Future<void>.delayed(const Duration(seconds: 2));
          await _finish(approved: false);
        }
        return;
      }
      final aiAvailable = await _pipeline.initialize();
      setState(
        () => _message =
            'Look straight at the camera. Capturing secure identity samples...',
      );
      final independentOutcomes = <FaceIdentityCheckOutcome>[];
      for (var index = 0; index < 3; index++) {
        if (!mounted) return;
        setState(() => _message = 'Hold still • sample ${index + 1} of 3');
        final sample = aiAvailable
            ? await _captureQualitySample(controller)
            : null;
        independentOutcomes.add(
          _verificationService.evaluateSample(
            aiAvailable: aiAvailable,
            sample: sample,
            pipelineFailureReason: _pipeline.lastFailureReason,
            templateJson: templateJson,
            liveness: liveness,
          ),
        );
      }
      final outcome = _verificationService.evaluateConsensus(
        outcomes: independentOutcomes,
      );
      if (!mounted) return;
      setState(() {
        _lastOutcome = outcome;
        _message = switch (outcome.state) {
          FaceIdentityCheckState.verified =>
            'Identity confirmed. Similarity ${(outcome.similarity * 100).toStringAsFixed(1)}%.',
          FaceIdentityCheckState.mismatch =>
            'This sample did not match the approved identity. It is not a '
                'misconduct decision; try again with better framing.',
          FaceIdentityCheckState.uncertain =>
            'The result was uncertain: ${outcome.reason}',
          FaceIdentityCheckState.aiUnavailable =>
            'Face identity AI is unavailable on this device. The check cannot run.',
          FaceIdentityCheckState.qualityRetry => outcome.reason,
          FaceIdentityCheckState.livenessFailed =>
            'Liveness could not be confirmed: ${outcome.reason}',
        };
        _stage = outcome.verified ? _CheckStage.passed : _CheckStage.ready;
      });
      if (outcome.verified) {
        await _speech.speak('Identity confirmed successfully.');
        await Future<void>.delayed(const Duration(seconds: 2));
        await _finish(approved: true);
      } else if (outcome.state == FaceIdentityCheckState.mismatch ||
          outcome.state == FaceIdentityCheckState.livenessFailed) {
        _failedAttempts++;
        final limit = widget.maxFailedAttempts;
        if (limit != null && _failedAttempts >= limit) {
          await Future<void>.delayed(const Duration(seconds: 2));
          await _finish(approved: false);
        }
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _stage = _CheckStage.ready;
        _message = 'Identity check could not run: $error';
      });
    }
  }

  /// Captures one verification sample using the same live-frame cycle
  /// enrollment relies on: wait for the camera stream to settle on several
  /// consecutive good-quality frames, then take the photo. Falls back to a
  /// short retry loop (discarding rejected captures instead of spending one
  /// of the three independent samples on them) on platforms where live
  /// streaming isn't supported, e.g. `camera_windows`.
  Future<FaceEmbeddingPipelineResult?> _captureQualitySample(
    CameraController controller,
  ) async {
    await _waitForLiveQualityFrame(controller);
    for (var attempt = 0; attempt < _maxCaptureRetries; attempt++) {
      if (!mounted || !controller.value.isInitialized) return null;
      final XFile file;
      try {
        file = await controller.takePicture();
      } catch (_) {
        return null;
      }
      final sample = await _pipeline.processEncodedImage(
        await File(file.path).readAsBytes(),
      );
      if (sample != null) return sample;
      if (attempt == _maxCaptureRetries - 1) return null;
      if (!mounted) return null;
      setState(() {
        _message = _pipeline.lastFailureReason.isEmpty
            ? 'Hold still and look directly at the camera.'
            : _pipeline.lastFailureReason;
      });
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
    return null;
  }

  /// Streams the live camera preview and waits until several consecutive
  /// frames pass the same quality gate enrollment uses, before returning so
  /// the caller can take the still photo. Returns without waiting long on
  /// platforms/builds where streaming isn't available (the still-capture
  /// retry loop in [_captureQualitySample] is the fallback quality gate
  /// there).
  Future<void> _waitForLiveQualityFrame(CameraController controller) async {
    _liveConsecutiveGoodFrames = 0;
    final completer = Completer<bool>();
    final started = await _liveCaptureEngine.start(
      controller: controller,
      onFrame: (landmarks, grade) {
        if (completer.isCompleted) return;
        if (!grade.accepted) {
          _liveConsecutiveGoodFrames = 0;
          if (mounted) {
            setState(() {
              _message = grade.failureReasons.isNotEmpty
                  ? grade.failureReasons.first
                  : 'Center your face in the frame and hold still.';
            });
          }
          return;
        }
        _liveConsecutiveGoodFrames++;
        if (_liveConsecutiveGoodFrames >= _liveCaptureStabilityFrames) {
          completer.complete(true);
        }
      },
    );
    if (!started) return;
    await completer.future.timeout(
      const Duration(seconds: 6),
      onTimeout: () => false,
    );
    await _liveCaptureEngine.stop();
  }

  Future<void> _finish({required bool approved}) async {
    if (_leaving || !mounted) return;
    _leaving = true;
    await _controller?.dispose();
    _controller = null;
    if (!mounted) return;
    Navigator.of(context).pop(approved);
  }

  @override
  Widget build(BuildContext context) {
    final ready = _controller?.value.isInitialized ?? false;
    return PopScope(
      canPop: widget.allowCancel,
      child: Scaffold(
        backgroundColor: const Color(0xFF07111F),
        appBar: AppBar(
          title: const Text('Confirm your identity'),
          backgroundColor: Colors.white,
          automaticallyImplyLeading: false,
          leading: widget.allowCancel
              ? IconButton(
                  icon: const Icon(Icons.arrow_back_rounded),
                  onPressed: () => _finish(approved: false),
                )
              : null,
        ),
        body: SafeArea(
          child: Center(
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
                                  _stage == _CheckStage.noApprovedIdentity
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
                          const SizedBox(height: 16),
                          if (_stage == _CheckStage.noApprovedIdentity)
                            FilledButton.icon(
                              onPressed: () => _finish(approved: false),
                              icon: const Icon(Icons.arrow_back),
                              label: const Text('Go back and set up identity'),
                            )
                          else
                            FilledButton.icon(
                              onPressed: ready && _stage != _CheckStage.running
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
                            ),
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
    );
  }
}

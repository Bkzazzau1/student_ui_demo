import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import 'demo_face_id_service.dart';
import 'face_embedding_pipeline.dart';
import 'face_identity_liveness_gate.dart';
import 'face_identity_verification_service.dart';
import 'native_face_embedding_runtime.dart';
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
  });

  final String examId;
  final String attemptId;

  @override
  State<FaceIdentityCheckView> createState() => _FaceIdentityCheckViewState();
}

enum _CheckStage { loadingTemplate, noApprovedIdentity, ready, running, passed }

class _FaceIdentityCheckViewState extends State<FaceIdentityCheckView> {
  final FaceEmbeddingPipeline _pipeline = FaceEmbeddingPipeline();
  final FaceIdentityLivenessGate _livenessGate = FaceIdentityLivenessGate();
  final FaceIdentityVerificationService _verificationService =
      const FaceIdentityVerificationService();
  final String _studentId = DemoFaceIdService.studentId;

  CameraController? _controller;
  String? _templateJson;
  _CheckStage _stage = _CheckStage.loadingTemplate;
  String _message = 'Loading your approved identity...';
  FaceIdentityCheckOutcome? _lastOutcome;
  bool _leaving = false;

  @override
  void initState() {
    super.initState();
    unawaited(_loadTemplate());
  }

  @override
  void dispose() {
    _controller?.dispose();
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
          () => _message = 'No camera was found. Identity check requires a camera.',
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
      _message = 'Confirm liveness: follow the on-screen prompt...';
      _lastOutcome = null;
    });
    try {
      final liveness = await _livenessGate.runBurst(controller: controller);
      if (!mounted) return;
      final aiAvailable = await _pipeline.initialize();
      setState(
        () => _message =
            'Look straight at the camera. Capturing your identity check...',
      );
      final file = await controller.takePicture();
      final sample = aiAvailable
          ? await _pipeline.processEncodedImage(await File(file.path).readAsBytes())
          : null;
      final outcome = _verificationService.evaluateSample(
        aiAvailable: aiAvailable,
        sample: sample,
        pipelineFailureReason: _pipeline.lastFailureReason,
        templateJson: templateJson,
        liveness: liveness,
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
          FaceIdentityCheckState.uncertain => 'The result was uncertain: ${outcome.reason}',
          FaceIdentityCheckState.aiUnavailable =>
            'Face identity AI is unavailable on this device. The check cannot run.',
          FaceIdentityCheckState.qualityRetry => outcome.reason,
          FaceIdentityCheckState.livenessFailed =>
            'Liveness could not be confirmed: ${outcome.reason}',
        };
        _stage = outcome.verified ? _CheckStage.passed : _CheckStage.ready;
      });
      if (outcome.verified) {
        await Future<void>.delayed(const Duration(milliseconds: 700));
        await _finish(approved: true);
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _stage = _CheckStage.ready;
        _message = 'Identity check could not run: $error';
      });
    }
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
    return Scaffold(
      backgroundColor: const Color(0xFF07111F),
      appBar: AppBar(
        title: const Text('Confirm your identity'),
        backgroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => _finish(approved: false),
        ),
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
                            onPressed:
                                ready && _stage != _CheckStage.running
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
    );
  }
}

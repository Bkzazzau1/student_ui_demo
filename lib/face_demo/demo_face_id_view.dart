import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import 'demo_face_id_service.dart';
import 'face_embedding_pipeline.dart';
import 'face_identity_enrollment_api.dart';
import 'native_face_embedding_runtime.dart';
import '../rust/api/face_verification.dart';

part 'demo_face_id_view_widgets.dart';

class DemoFaceIdView extends StatefulWidget {
  const DemoFaceIdView({super.key, this.onComplete});

  final VoidCallback? onComplete;

  @override
  State<DemoFaceIdView> createState() => _DemoFaceIdViewState();
}

class _IdentityGuide {
  const _IdentityGuide({
    required this.code,
    required this.title,
    required this.instruction,
    required this.icon,
  });

  final String code;
  final String title;
  final String instruction;
  final IconData icon;
}

class _DemoFaceIdViewState extends State<DemoFaceIdView> {
  static const List<_IdentityGuide> _guides = <_IdentityGuide>[
    _IdentityGuide(
      code: 'front_face',
      title: 'Front face',
      instruction:
          'Look straight at the camera and keep your face inside the guide.',
      icon: Icons.face_retouching_natural,
    ),
    _IdentityGuide(
      code: 'left_angle',
      title: 'Left angle',
      instruction:
          'Turn your face slightly to the left. Keep both eyes visible.',
      icon: Icons.keyboard_arrow_left,
    ),
    _IdentityGuide(
      code: 'right_angle',
      title: 'Right angle',
      instruction:
          'Turn your face slightly to the right. Keep your chin level.',
      icon: Icons.keyboard_arrow_right,
    ),
    _IdentityGuide(
      code: 'look_up',
      title: 'Look up',
      instruction: 'Raise your face slightly upward without leaving the guide.',
      icon: Icons.keyboard_arrow_up,
    ),
    _IdentityGuide(
      code: 'look_down',
      title: 'Look down',
      instruction: 'Lower your face slightly downward. Do not cover your eyes.',
      icon: Icons.keyboard_arrow_down,
    ),
    _IdentityGuide(
      code: 'eyes_closed',
      title: 'Close eyes',
      instruction: 'Close your eyes briefly for the final liveness image.',
      icon: Icons.visibility_off_outlined,
    ),
  ];

  final DemoFaceIdService _service = DemoFaceIdService();
  final FaceIdentityEnrollmentApi _identityApi = FaceIdentityEnrollmentApi(
    baseUrl: const String.fromEnvironment(
      'KSLAS_API_BASE_URL',
      defaultValue: 'http://127.0.0.1:8080',
    ),
    accessToken: const String.fromEnvironment('KSLAS_API_ACCESS_TOKEN'),
  );
  final List<FaceIdentityEnrollmentImage> _capturedImages =
      <FaceIdentityEnrollmentImage>[];
  final List<Float32List> _capturedEmbeddings = <Float32List>[];
  final FaceEmbeddingPipeline _embeddingPipeline = FaceEmbeddingPipeline();
  String? _portableTemplateJson;

  late DemoFaceIdSnapshot _snapshot;
  CameraController? _controller;
  bool _openingCamera = false;
  bool _capturing = false;
  bool _submitting = false;
  bool _syncing = false;
  bool _autoCaptureRunning = false;
  bool _autoCaptureStarted = false;
  bool _verificationRunning = false;
  bool _testingExistingTemplate = false;
  String? _cameraError;
  String? _statusMessage;

  _IdentityGuide get _currentGuide =>
      _guides[math.min(_snapshot.capturedSamples, _guides.length - 1)];

  @override
  void initState() {
    super.initState();
    _snapshot = _service.load();
    _syncSavedFaceId();
  }

  @override
  void dispose() {
    _controller?.dispose();
    _identityApi.dispose();
    super.dispose();
  }

  Future<void> _syncSavedFaceId() async {
    if (_syncing) return;
    setState(() {
      _syncing = true;
      _statusMessage = 'Checking your saved Face ID...';
    });
    try {
      final protectedTemplate = await NativeFaceEmbeddingRuntime()
          .loadProtectedTemplate(studentId: _snapshot.studentId);
      if (protectedTemplate != null && protectedTemplate.isNotEmpty) {
        final status = validatePortableFaceTemplate(
          templateJson: protectedTemplate,
          expectedStudentId: _snapshot.studentId,
          expectedModelId: NativeFaceEmbeddingRuntime.modelId,
          expectedModelSha256: NativeFaceEmbeddingRuntime.modelSha256,
          nowMs: DateTime.now().toUtc().millisecondsSinceEpoch,
        );
        if (status.valid) {
          if (!mounted) return;
          setState(() {
            _portableTemplateJson = protectedTemplate;
            _testingExistingTemplate = true;
            _syncing = false;
            _statusMessage =
                'A protected Face ID is stored on this device. You can test '
                'it now with a new live capture.';
          });
          await _openCamera(forVerification: true);
          await _askToVerifyEnrollment();
          return;
        }
      }
      final latest = await _identityApi.fetchLatest(
        studentId: DemoFaceIdService.studentId,
      );
      if (!mounted) return;
      if (latest != null && latest.activeLocked) {
        final synced = await _service.applyBackendEnrollment(latest);
        await _controller?.dispose();
        setState(() {
          _snapshot = synced;
          _capturedImages.clear();
          _controller = null;
          _syncing = false;
          _openingCamera = false;
          _statusMessage = 'Face ID is active and protected on this device.';
        });
        widget.onComplete?.call();
        return;
      }
      setState(() {
        _syncing = false;
        _statusMessage = latest == null
            ? 'No saved Face ID found. We will capture your identity images automatically.'
            : latest.message
                  .replaceAll('Backend ', '')
                  .replaceAll('backend ', '');
      });
      await _openCamera();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _syncing = false;
        _statusMessage =
            'We could not check your saved Face ID. Capture will continue and save when connection is available.';
      });
      await _openCamera();
    }
  }

  Future<void> _openCamera({bool forVerification = false}) async {
    if (_snapshot.locked && !forVerification) return;
    setState(() {
      _openingCamera = true;
      _cameraError = null;
    });
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        setState(() {
          _openingCamera = false;
          _cameraError =
              'No camera found. Face ID setup requires camera access.';
        });
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
      await _controller?.dispose();
      await controller.initialize();
      if (!mounted) return;
      setState(() {
        _controller = controller;
        _openingCamera = false;
        _statusMessage =
            'Automatic capture will start. Follow the guide on screen.';
      });
      _startAutomaticCapture();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _openingCamera = false;
        _cameraError = 'Camera could not open for Face ID setup: $e';
      });
    }
  }

  Future<void> _startAutomaticCapture() async {
    if (_autoCaptureRunning ||
        _autoCaptureStarted ||
        _snapshot.locked ||
        _snapshot.isComplete) {
      return;
    }
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    _autoCaptureStarted = true;
    _autoCaptureRunning = true;
    while (mounted &&
        !_snapshot.locked &&
        _snapshot.capturedSamples < _snapshot.requiredSamples) {
      final guide = _currentGuide;
      setState(() {
        _statusMessage =
            '${guide.title}: ${guide.instruction} Capturing automatically...';
      });
      await Future<void>.delayed(const Duration(milliseconds: 1700));
      if (!mounted || _snapshot.locked || _submitting) break;
      await _captureSample();
      await Future<void>.delayed(const Duration(milliseconds: 600));
    }
    if (mounted) {
      setState(() => _autoCaptureRunning = false);
    }
  }

  Future<void> _captureSample() async {
    if (_snapshot.locked ||
        _capturing ||
        _snapshot.isComplete ||
        _submitting ||
        _syncing) {
      return;
    }
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      setState(
        () =>
            _cameraError = 'Open the camera before Face ID setup can continue.',
      );
      return;
    }
    final guide = _currentGuide;
    setState(() => _capturing = true);
    String imagePath;
    var quality = 0.0;
    try {
      final file = await controller.takePicture();
      imagePath = file.path;
      final embeddingResult = await _embeddingPipeline.processEncodedImage(
        await File(imagePath).readAsBytes(),
      );
      if (embeddingResult == null || embeddingResult.quality < 0.65) {
        if (!mounted) return;
        setState(() {
          _capturing = false;
          _statusMessage =
              'No reliable aligned face was detected. Improve the lighting, '
              'keep both eyes visible, and hold still while we retry.';
        });
        return;
      }
      quality = embeddingResult.quality;
      _capturedEmbeddings.add(Float32List.fromList(embeddingResult.embedding));
    } catch (e) {
      setState(() {
        _capturing = false;
        _cameraError = 'Identity image capture failed: $e';
      });
      return;
    }

    _capturedImages.add(
      FaceIdentityEnrollmentImage(
        fieldName: 'identity_image_${_capturedImages.length + 1}',
        poseCode: guide.code,
        title: guide.title,
        instruction: guide.instruction,
        path: imagePath,
        qualityScore: quality,
      ),
    );

    final next = await _service.addSample(qualityScore: quality);
    if (!mounted) return;
    setState(() {
      _snapshot = next;
      _capturing = false;
      _statusMessage = next.capturedSamples >= next.requiredSamples
          ? 'All images captured. Saving your Face ID securely...'
          : 'Image ${next.capturedSamples} of ${next.requiredSamples} captured.';
    });
    if (next.capturedSamples >= next.requiredSamples) {
      await _submitIdentityGallery();
    }
  }

  Future<void> _submitIdentityGallery() async {
    if (_submitting ||
        _capturedImages.length < _guides.length ||
        _snapshot.locked) {
      return;
    }
    setState(() {
      _submitting = true;
      _statusMessage = 'Saving your Face ID securely...';
    });
    try {
      if (_capturedEmbeddings.length != _guides.length) {
        throw StateError('Reliable embeddings are missing from enrollment');
      }
      final localEnrollmentId =
          'local-${DateTime.now().toUtc().millisecondsSinceEpoch}';
      await _buildAndProtectTemplate(localEnrollmentId);
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _statusMessage =
            'Enrollment is protected locally. Test it now with a new live '
            'camera capture; backend synchronization will follow.';
      });
      await _askToVerifyEnrollment();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _statusMessage =
            'Face ID could not be saved. Check connection and try again.';
      });
    }
  }

  Future<void> _buildAndProtectTemplate(String enrollmentId) async {
    final now = DateTime.now().toUtc();
    _portableTemplateJson = buildPortableFaceTemplate(
      studentId: _snapshot.studentId,
      enrollmentId: enrollmentId,
      modelId: NativeFaceEmbeddingRuntime.modelId,
      modelSha256: NativeFaceEmbeddingRuntime.modelSha256,
      preprocessingVersion: NativeFaceEmbeddingRuntime.preprocessingVersion,
      embeddings: List<Float32List>.unmodifiable(_capturedEmbeddings),
      qualityScore:
          _capturedImages
              .map((image) => image.qualityScore)
              .reduce((a, b) => a + b) /
          _capturedImages.length,
      createdAtMs: now.millisecondsSinceEpoch,
      expiresAtMs: now.add(const Duration(days: 365)).millisecondsSinceEpoch,
    );
    final protected = await NativeFaceEmbeddingRuntime().storeProtectedTemplate(
      studentId: _snapshot.studentId,
      templateJson: _portableTemplateJson!,
    );
    if (!protected) {
      throw StateError(
        'The identity template could not be protected by Windows DPAPI',
      );
    }
  }

  Future<void> _askToVerifyEnrollment() async {
    if (!mounted || _portableTemplateJson == null) return;
    final testNow = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Test your Face ID'),
        content: const Text(
          'Enrollment has been stored. We will take one new live image and '
          'check whether it matches your enrolled identity. A weak or '
          'mismatched sample simply asks you to try again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Test later'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(context).pop(true),
            icon: const Icon(Icons.verified_user_outlined),
            label: const Text('Test now'),
          ),
        ],
      ),
    );
    if (testNow == true) {
      await _verifyFreshIdentitySample();
    } else {
      await _finishEnrollmentWithoutTest();
    }
  }

  Future<void> _verifyFreshIdentitySample() async {
    if (_verificationRunning || _portableTemplateJson == null) return;
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      setState(() {
        _statusMessage =
            'The camera is unavailable. Reopen Face ID to test it.';
      });
      return;
    }
    setState(() {
      _verificationRunning = true;
      _statusMessage =
          'Look straight at the camera. Capturing a fresh identity sample...';
    });
    await Future<void>.delayed(const Duration(milliseconds: 900));
    try {
      final file = await controller.takePicture();
      final sample = await _embeddingPipeline.processEncodedImage(
        await File(file.path).readAsBytes(),
      );
      if (sample == null || sample.quality < 0.65) {
        if (!mounted) return;
        setState(() {
          _verificationRunning = false;
          _statusMessage =
              'The verification image was not reliable. Improve the lighting '
              'and keep your full face visible.';
        });
        await _showVerificationResult(
          verified: false,
          title: 'Please try again',
          message: 'We could not obtain a reliable live face sample.',
        );
        return;
      }
      final verification = verifyFaceEmbedding1To1(
        templateJson: _portableTemplateJson!,
        probeEmbedding: sample.embedding,
        signalQuality: sample.quality,
        // Development threshold only. Production uses a threshold calibrated
        // against the institution's held-out validation population.
        matchThreshold: 0.363,
        nowMs: DateTime.now().toUtc().millisecondsSinceEpoch,
      );
      if (!mounted) return;
      final verified = verification.state == 'identity_verified';
      setState(() {
        _verificationRunning = false;
        _statusMessage = verified
            ? 'Face ID test passed. Similarity ${(verification.similarity * 100).toStringAsFixed(1)}%.'
            : 'This sample did not verify. It is not a misconduct decision; try another live sample.';
      });
      await _showVerificationResult(
        verified: verified,
        title: verified ? 'Identity verified' : 'Identity not confirmed',
        message: verified
            ? 'The new live sample matches the stored enrollment.'
            : 'The sample did not meet the development threshold. Please try again with even lighting and a straight pose.',
      );
      if (verified) {
        await _finishEnrollmentWithoutTest();
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _verificationRunning = false;
        _statusMessage = 'Face ID test could not run: $error';
      });
    }
  }

  Future<void> _showVerificationResult({
    required bool verified,
    required String title,
    required String message,
  }) async {
    if (!mounted) return;
    final retry = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: Icon(
          verified ? Icons.verified_user : Icons.face_retouching_natural,
          color: verified ? Colors.green : Colors.orange,
          size: 42,
        ),
        title: Text(title),
        content: Text(message),
        actions: [
          if (!verified)
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Later'),
            ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(!verified),
            child: Text(verified ? 'Continue' : 'Try again'),
          ),
        ],
      ),
    );
    if (!verified && retry == true) {
      await _verifyFreshIdentitySample();
    }
  }

  Future<void> _finishEnrollmentWithoutTest() async {
    if (_testingExistingTemplate) {
      await _controller?.dispose();
      if (!mounted) return;
      setState(() {
        _controller = null;
        _testingExistingTemplate = false;
        _statusMessage = 'Stored Face ID test completed.';
      });
      widget.onComplete?.call();
      return;
    }
    setState(() {
      _submitting = true;
      _statusMessage = 'Face ID is stored locally. Synchronizing enrollment...';
    });
    try {
      final enrollment = await _identityApi.submit(
        studentId: _snapshot.studentId,
        images: List<FaceIdentityEnrollmentImage>.from(_capturedImages),
      );
      await _buildAndProtectTemplate(enrollment.enrollmentId);
      final synced = await _service.applyBackendEnrollment(enrollment);
      if (!mounted) return;
      await _controller?.dispose();
      setState(() {
        _snapshot = synced;
        _controller = null;
        _submitting = false;
        _statusMessage = 'Face ID enrollment is stored and active.';
      });
      if (synced.isComplete) widget.onComplete?.call();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _statusMessage =
            'Face ID is protected on this device and the test is complete. '
            'Backend synchronization is pending.';
      });
    }
  }

  Future<void> _testOrEnrollOnThisDevice() async {
    final protectedTemplate = await NativeFaceEmbeddingRuntime()
        .loadProtectedTemplate(studentId: _snapshot.studentId);
    if (protectedTemplate != null && protectedTemplate.isNotEmpty) {
      final status = validatePortableFaceTemplate(
        templateJson: protectedTemplate,
        expectedStudentId: _snapshot.studentId,
        expectedModelId: NativeFaceEmbeddingRuntime.modelId,
        expectedModelSha256: NativeFaceEmbeddingRuntime.modelSha256,
        nowMs: DateTime.now().toUtc().millisecondsSinceEpoch,
      );
      if (status.valid) {
        setState(() {
          _portableTemplateJson = protectedTemplate;
          _testingExistingTemplate = true;
          _statusMessage = 'Protected Face ID loaded. Opening a live test...';
        });
        await _openCamera(forVerification: true);
        await _askToVerifyEnrollment();
        return;
      }
    }

    if (!mounted) return;
    final startEnrollment = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Set up Face ID on this device'),
        content: const Text(
          'The previous record contains enrollment status but no protected '
          'embedding template that this device can test. Capture six new '
          'samples to create and verify one locally. This does not delete the '
          'institution\'s backend record.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Start capture'),
          ),
        ],
      ),
    );
    if (startEnrollment != true) return;
    final draft = await _service.beginDeviceEnrollment();
    if (!mounted) return;
    setState(() {
      _snapshot = draft;
      _capturedImages.clear();
      _capturedEmbeddings.clear();
      _portableTemplateJson = null;
      _autoCaptureStarted = false;
      _autoCaptureRunning = false;
      _statusMessage = 'Starting secure Face ID capture on this device...';
    });
    await _openCamera();
  }

  Future<void> _reset() async {
    if (_snapshot.locked) {
      setState(
        () => _statusMessage =
            'Face ID is protected. It can only be reset by an authorized officer.',
      );
      return;
    }
    final next = await _service.resetLocalDraftOnly();
    if (!mounted) return;
    setState(() {
      _snapshot = next;
      _capturedImages.clear();
      _capturedEmbeddings.clear();
      _portableTemplateJson = null;
      _testingExistingTemplate = false;
      _autoCaptureStarted = false;
      _autoCaptureRunning = false;
      _statusMessage = 'Local draft cleared. Automatic capture will restart.';
    });
    await _openCamera();
  }

  @override
  Widget build(BuildContext context) {
    final progress = _snapshot.capturedSamples / _snapshot.requiredSamples;
    final compact = MediaQuery.sizeOf(context).width < 640;
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      appBar: AppBar(
        title: const Text('Face ID setup'),
        actions: [
          if (_snapshot.locked)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: FilledButton.icon(
                onPressed: _testOrEnrollOnThisDevice,
                icon: const Icon(Icons.face_retouching_natural),
                label: const Text('Test Face ID'),
              ),
            ),
        ],
      ),
      bottomNavigationBar: compact && !_snapshot.locked
          ? _MobileCaptureBar(
              snapshot: _snapshot,
              guide: _currentGuide,
              capturing: _capturing || _syncing || _autoCaptureRunning,
              submitting: _submitting,
              onCapture: _startAutomaticCapture,
              onReset: _reset,
            )
          : null,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(18, 14, 18, compact ? 104 : 18),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1040),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Header(
                    snapshot: _snapshot,
                    progress: progress,
                    compact: compact,
                  ),
                  const SizedBox(height: 14),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final wide = constraints.maxWidth >= 760;
                      final preview = _CameraPreviewPanel(
                        controller: _controller,
                        openingCamera: _openingCamera || _syncing,
                        cameraError: _cameraError,
                        guide: _currentGuide,
                        complete: _snapshot.isComplete,
                        compact: !wide,
                      );
                      final status = _StatusPanel(
                        snapshot: _snapshot,
                        progress: progress,
                        guides: _guides,
                        statusMessage: _statusMessage,
                        compact: !wide,
                      );
                      if (!wide) {
                        return Column(
                          children: [
                            preview,
                            const SizedBox(height: 14),
                            status,
                          ],
                        );
                      }
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(flex: 6, child: preview),
                          const SizedBox(width: 16),
                          Expanded(flex: 5, child: status),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 14),
                  if (!_snapshot.locked)
                    _ActionBar(
                      snapshot: _snapshot,
                      guide: _currentGuide,
                      capturing: _capturing || _syncing || _autoCaptureRunning,
                      submitting: _submitting,
                      onCapture: _startAutomaticCapture,
                      onReset: _reset,
                      onBack: () =>
                          Navigator.of(context).pop(_snapshot.isComplete),
                    )
                  else
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: _testOrEnrollOnThisDevice,
                            icon: const Icon(Icons.face_retouching_natural),
                            label: const Text('Test Face ID on this device'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        OutlinedButton.icon(
                          onPressed: () => Navigator.of(context).pop(true),
                          icon: const Icon(Icons.arrow_back),
                          label: const Text('Return'),
                        ),
                      ],
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

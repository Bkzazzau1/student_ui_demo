import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import 'demo_face_id_service.dart';
import 'face_identity_enrollment_api.dart';

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
      instruction: 'Look straight at the camera and keep your face inside the guide.',
      icon: Icons.face_retouching_natural,
    ),
    _IdentityGuide(
      code: 'left_angle',
      title: 'Left angle',
      instruction: 'Turn your face slightly to the left. Keep both eyes visible.',
      icon: Icons.keyboard_arrow_left,
    ),
    _IdentityGuide(
      code: 'right_angle',
      title: 'Right angle',
      instruction: 'Turn your face slightly to the right. Keep your chin level.',
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
  );
  final List<FaceIdentityEnrollmentImage> _capturedImages = <FaceIdentityEnrollmentImage>[];

  late DemoFaceIdSnapshot _snapshot;
  CameraController? _controller;
  bool _openingCamera = false;
  bool _capturing = false;
  bool _submitting = false;
  bool _syncing = false;
  bool _autoCaptureRunning = false;
  bool _autoCaptureStarted = false;
  String? _cameraError;
  String? _statusMessage;

  _IdentityGuide get _currentGuide => _guides[math.min(_snapshot.capturedSamples, _guides.length - 1)];

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
      final latest = await _identityApi.fetchLatest(studentId: DemoFaceIdService.studentId);
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
            : latest.message.replaceAll('Backend ', '').replaceAll('backend ', '');
      });
      await _openCamera();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _syncing = false;
        _statusMessage = 'We could not check your saved Face ID. Capture will continue and save when connection is available.';
      });
      await _openCamera();
    }
  }

  Future<void> _openCamera() async {
    if (_snapshot.locked) return;
    setState(() {
      _openingCamera = true;
      _cameraError = null;
    });
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        setState(() {
          _openingCamera = false;
          _cameraError = 'No camera found. Face ID setup requires camera access.';
        });
        return;
      }
      final selected = cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );
      final controller = CameraController(selected, ResolutionPreset.medium, enableAudio: false);
      await _controller?.dispose();
      await controller.initialize();
      if (!mounted) return;
      setState(() {
        _controller = controller;
        _openingCamera = false;
        _statusMessage = 'Automatic capture will start. Follow the guide on screen.';
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
    if (_autoCaptureRunning || _autoCaptureStarted || _snapshot.locked || _snapshot.isComplete) return;
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    _autoCaptureStarted = true;
    _autoCaptureRunning = true;
    while (mounted && !_snapshot.locked && _snapshot.capturedSamples < _snapshot.requiredSamples) {
      final guide = _currentGuide;
      setState(() {
        _statusMessage = '${guide.title}: ${guide.instruction} Capturing automatically...';
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
    if (_snapshot.locked || _capturing || _snapshot.isComplete || _submitting || _syncing) return;
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      setState(() => _cameraError = 'Open the camera before Face ID setup can continue.');
      return;
    }
    final guide = _currentGuide;
    setState(() => _capturing = true);
    String imagePath;
    var quality = 0.72 + math.Random().nextDouble() * 0.22;
    try {
      final file = await controller.takePicture();
      imagePath = file.path;
      final size = await file.length();
      quality = (0.68 + math.min(size / 900000, 0.25)).clamp(0.0, 1.0);
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
    if (_submitting || _capturedImages.length < _guides.length || _snapshot.locked) return;
    setState(() {
      _submitting = true;
      _statusMessage = 'Saving your Face ID securely...';
    });
    try {
      final response = await _identityApi.submit(
        studentId: _snapshot.studentId,
        images: List<FaceIdentityEnrollmentImage>.from(_capturedImages),
      );
      final synced = await _service.applyBackendEnrollment(response);
      if (!mounted) return;
      await _controller?.dispose();
      setState(() {
        _snapshot = synced;
        _controller = null;
        _submitting = false;
        _statusMessage = response.message
            .replaceAll('Backend ', '')
            .replaceAll('backend ', '')
            .replaceAll('locked', 'protected');
      });
      if (synced.isComplete) {
        widget.onComplete?.call();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _statusMessage = 'Face ID could not be saved. Check connection and try again.';
      });
    }
  }

  Future<void> _reset() async {
    if (_snapshot.locked) {
      setState(() => _statusMessage = 'Face ID is protected. It can only be reset by an authorized officer.');
      return;
    }
    final next = await _service.resetLocalDraftOnly();
    if (!mounted) return;
    setState(() {
      _snapshot = next;
      _capturedImages.clear();
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
      appBar: AppBar(title: const Text('Face ID setup')),
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
                  _Header(snapshot: _snapshot, progress: progress, compact: compact),
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
                        return Column(children: [preview, const SizedBox(height: 14), status]);
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
                      onBack: () => Navigator.of(context).pop(_snapshot.isComplete),
                    )
                  else
                    FilledButton.icon(
                      onPressed: () => Navigator.of(context).pop(true),
                      icon: const Icon(Icons.verified_user_outlined),
                      label: const Text('Face ID active - return'),
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

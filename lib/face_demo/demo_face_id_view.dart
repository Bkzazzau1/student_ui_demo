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
      instruction:
          'Look straight at the camera. Keep your full face inside the oval.',
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
      instruction: 'Raise your face slightly upward without leaving the oval.',
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
      instruction:
          'Close your eyes for this final liveness image, then capture.',
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
  final List<FaceIdentityEnrollmentImage> _capturedImages =
      <FaceIdentityEnrollmentImage>[];

  late DemoFaceIdSnapshot _snapshot;
  CameraController? _controller;
  bool _openingCamera = false;
  bool _capturing = false;
  bool _submitting = false;
  bool _syncing = false;
  String? _cameraError;
  String? _backendMessage;

  _IdentityGuide get _currentGuide =>
      _guides[math.min(_snapshot.capturedSamples, _guides.length - 1)];

  @override
  void initState() {
    super.initState();
    _snapshot = _service.load();
    _syncBackendEnrollment();
    if (!_snapshot.locked) {
      _openCamera();
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    _identityApi.dispose();
    super.dispose();
  }

  Future<void> _syncBackendEnrollment() async {
    if (_syncing) return;
    setState(() {
      _syncing = true;
      _backendMessage = 'Checking backend Face ID enrollment...';
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
          _backendMessage = 'Backend Face ID downloaded and locked on this device.';
        });
        widget.onComplete?.call();
        return;
      }
      setState(() {
        _syncing = false;
        _backendMessage = latest == null
            ? 'No backend Face ID found. Capture and upload identity images once.'
            : latest.message;
      });
      if (!_snapshot.locked && _controller == null) {
        await _openCamera();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _syncing = false;
        _backendMessage = 'Backend Face ID sync failed: $e';
      });
      if (!_snapshot.locked && _controller == null) {
        await _openCamera();
      }
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
          _cameraError =
              'No camera found. Identity image capture requires camera access.';
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
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _openingCamera = false;
        _cameraError = 'Camera could not open for identity image capture: $e';
      });
    }
  }

  Future<void> _captureSample() async {
    if (_snapshot.locked) {
      setState(() => _backendMessage = 'Face ID is already locked by backend and cannot be changed here.');
      return;
    }
    if (_capturing || _snapshot.isComplete || _submitting || _syncing) return;
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      setState(
        () => _cameraError =
            'Open the camera before capturing this identity image.',
      );
      return;
    }
    final guide = _currentGuide;
    setState(() => _capturing = true);
    var quality = 0.72 + math.Random().nextDouble() * 0.22;
    String? imagePath;
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
      _backendMessage = next.capturedSamples >= next.requiredSamples
          ? 'All images captured. Uploading and locking Face ID on backend...'
          : null;
    });
    if (next.capturedSamples >= next.requiredSamples) {
      await _submitIdentityGallery();
    }
  }

  Future<void> _submitIdentityGallery() async {
    if (_submitting || _capturedImages.length < _guides.length || _snapshot.locked) return;
    setState(() => _submitting = true);
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
        _backendMessage = response.message;
      });
      if (synced.isComplete) {
        widget.onComplete?.call();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _backendMessage =
            'Backend enrollment failed. Face ID is not active yet and cannot be used for exam startup: $e';
      });
    }
  }

  Future<void> _reset() async {
    if (_snapshot.locked) {
      setState(() {
        _backendMessage = 'Face ID is locked by backend. It can only be reset by an authorized officer.';
      });
      return;
    }
    final next = await _service.resetLocalDraftOnly();
    if (!mounted) return;
    setState(() {
      _snapshot = next;
      _capturedImages.clear();
      _backendMessage = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final progress = _snapshot.capturedSamples / _snapshot.requiredSamples;
    final compact = MediaQuery.sizeOf(context).width < 640;
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      appBar: AppBar(title: const Text('Identity setup')),
      bottomNavigationBar: compact && !_snapshot.locked
          ? _MobileCaptureBar(
              snapshot: _snapshot,
              guide: _currentGuide,
              capturing: _capturing || _syncing,
              submitting: _submitting,
              onCapture: _captureSample,
              onReset: _reset,
            )
          : null,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(18, 14, 18, compact ? 104 : 18),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 980),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Header(
                    snapshot: _snapshot,
                    progress: progress,
                    compact: compact,
                  ),
                  const SizedBox(height: 12),
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
                        backendMessage: _backendMessage,
                        compact: !wide,
                      );
                      if (!wide) {
                        return Column(
                          children: [
                            preview,
                            if (!compact && !_snapshot.locked) ...[
                              const SizedBox(height: 14),
                              _ActionBar(
                                snapshot: _snapshot,
                                guide: _currentGuide,
                                capturing: _capturing || _syncing,
                                submitting: _submitting,
                                onCapture: _captureSample,
                                onReset: _reset,
                                onBack: () => Navigator.of(
                                  context,
                                ).pop(_snapshot.isComplete),
                              ),
                            ],
                            const SizedBox(height: 14),
                            status,
                          ],
                        );
                      }
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: preview),
                          const SizedBox(width: 14),
                          Expanded(child: status),
                        ],
                      );
                    },
                  ),
                  if (compact)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: () =>
                            Navigator.of(context).pop(_snapshot.isComplete),
                        icon: const Icon(Icons.arrow_back),
                        label: const Text('Back'),
                      ),
                    )
                  else ...[
                    const SizedBox(height: 14),
                    if (!_snapshot.locked)
                      _ActionBar(
                        snapshot: _snapshot,
                        guide: _currentGuide,
                        capturing: _capturing || _syncing,
                        submitting: _submitting,
                        onCapture: _captureSample,
                        onReset: _reset,
                        onBack: () =>
                            Navigator.of(context).pop(_snapshot.isComplete),
                      )
                    else
                      FilledButton.icon(
                        onPressed: () => Navigator.of(context).pop(true),
                        icon: const Icon(Icons.lock_outline),
                        label: const Text('Face ID active - return'),
                      ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

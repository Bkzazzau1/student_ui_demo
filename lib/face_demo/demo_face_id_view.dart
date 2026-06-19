import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import 'demo_face_id_service.dart';
import 'face_identity_enrollment_api.dart';

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
  String? _cameraError;
  String? _backendMessage;

  _IdentityGuide get _currentGuide =>
      _guides[math.min(_snapshot.capturedSamples, _guides.length - 1)];

  @override
  void initState() {
    super.initState();
    _snapshot = _service.load();
    _openCamera();
  }

  @override
  void dispose() {
    _controller?.dispose();
    _identityApi.dispose();
    super.dispose();
  }

  Future<void> _openCamera() async {
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
    if (_capturing || _snapshot.isComplete || _submitting) return;
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
      _backendMessage = next.isComplete
          ? 'All images captured. Submitting identity gallery to backend...'
          : null;
    });
    if (next.isComplete) {
      await _submitIdentityGallery();
    }
  }

  Future<void> _submitIdentityGallery() async {
    if (_submitting || _capturedImages.length < _guides.length) return;
    setState(() => _submitting = true);
    try {
      final response = await _identityApi.submit(
        studentId: _snapshot.studentId,
        images: List<FaceIdentityEnrollmentImage>.from(_capturedImages),
      );
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _backendMessage = response.message;
      });
      widget.onComplete?.call();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _backendMessage =
            'Identity images captured locally, but backend submission failed: $e';
      });
      widget.onComplete?.call();
    }
  }

  Future<void> _reset() async {
    final next = await _service.reset();
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
      bottomNavigationBar: compact
          ? _MobileCaptureBar(
              snapshot: _snapshot,
              guide: _currentGuide,
              capturing: _capturing,
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
                        openingCamera: _openingCamera,
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
                            if (!compact) ...[
                              const SizedBox(height: 14),
                              _ActionBar(
                                snapshot: _snapshot,
                                guide: _currentGuide,
                                capturing: _capturing,
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
                    _ActionBar(
                      snapshot: _snapshot,
                      guide: _currentGuide,
                      capturing: _capturing,
                      submitting: _submitting,
                      onCapture: _captureSample,
                      onReset: _reset,
                      onBack: () =>
                          Navigator.of(context).pop(_snapshot.isComplete),
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

class _Header extends StatelessWidget {
  const _Header({
    required this.snapshot,
    required this.progress,
    required this.compact,
  });

  final DemoFaceIdSnapshot snapshot;
  final double progress;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(compact ? 14 : 18),
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                snapshot.isComplete
                    ? Icons.verified_user_rounded
                    : Icons.face_retouching_natural,
                color: Colors.white,
                size: compact ? 30 : 44,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  snapshot.isComplete
                      ? 'Identity enrollment active'
                      : compact
                      ? 'Register identity'
                      : 'Register identity images for secure exams',
                  style:
                      (compact
                              ? Theme.of(context).textTheme.titleLarge
                              : Theme.of(context).textTheme.headlineSmall)
                          ?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                          ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '${snapshot.capturedSamples}/${snapshot.requiredSamples}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            snapshot.statusText,
            style: TextStyle(
              color: const Color(0xFFCBD5E1),
              fontSize: compact ? 13 : null,
            ),
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: progress.clamp(0.0, 1.0),
              minHeight: 6,
              backgroundColor: Colors.white.withValues(alpha: 0.16),
              valueColor: const AlwaysStoppedAnimation<Color>(
                Color(0xFF22C55E),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CameraPreviewPanel extends StatelessWidget {
  const _CameraPreviewPanel({
    required this.controller,
    required this.openingCamera,
    required this.cameraError,
    required this.guide,
    required this.complete,
    required this.compact,
  });

  final CameraController? controller;
  final bool openingCamera;
  final String? cameraError;
  final _IdentityGuide guide;
  final bool complete;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final ready = controller?.value.isInitialized ?? false;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: const Color(0xFF101828),
        borderRadius: BorderRadius.circular(8),
      ),
      child: AspectRatio(
        aspectRatio: compact ? 3 / 4 : 4 / 3,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (ready) CameraPreview(controller!),
            if (!ready)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Text(
                    openingCamera
                        ? 'Opening camera...'
                        : cameraError ?? 'Camera preview',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
              ),
            Center(
              child: Container(
                width: 190,
                height: 244,
                decoration: BoxDecoration(
                  border: Border.all(color: const Color(0xFF22C55E), width: 2),
                  borderRadius: BorderRadius.circular(110),
                ),
              ),
            ),
            Align(
              alignment: Alignment.topCenter,
              child: Container(
                margin: const EdgeInsets.all(12),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.68),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  complete
                      ? 'Identity images complete'
                      : '${guide.title}: ${guide.instruction}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusPanel extends StatelessWidget {
  const _StatusPanel({
    required this.snapshot,
    required this.progress,
    required this.guides,
    required this.backendMessage,
    required this.compact,
  });

  final DemoFaceIdSnapshot snapshot;
  final double progress;
  final List<_IdentityGuide> guides;
  final String? backendMessage;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Enrollment status',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 12),
          _Row(label: 'Student ID', value: snapshot.studentId),
          _Row(label: 'Required images', value: '${snapshot.requiredSamples}'),
          _Row(label: 'Captured images', value: '${snapshot.capturedSamples}'),
          _Row(
            label: 'Status',
            value: snapshot.isComplete ? 'Active' : 'Pending',
          ),
          if (snapshot.lastQualityScore != null)
            _Row(
              label: 'Last quality',
              value: '${(snapshot.lastQualityScore! * 100).round()}%',
            ),
          if (backendMessage != null)
            _Row(label: 'Backend', value: backendMessage!),
          const SizedBox(height: 12),
          LinearProgressIndicator(value: progress.clamp(0.0, 1.0)),
          const SizedBox(height: 14),
          ...guides.asMap().entries.map((entry) {
            final done = entry.key < snapshot.capturedSamples;
            final active =
                entry.key == snapshot.capturedSamples && !snapshot.isComplete;
            return _GuideStepTile(
              guide: entry.value,
              done: done,
              active: active,
              compact: compact,
            );
          }),
        ],
      ),
    );
  }
}

class _GuideStepTile extends StatelessWidget {
  const _GuideStepTile({
    required this.guide,
    required this.done,
    required this.active,
    required this.compact,
  });

  final _IdentityGuide guide;
  final bool done;
  final bool active;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      minLeadingWidth: 28,
      leading: Icon(
        done
            ? Icons.check_circle
            : active
            ? guide.icon
            : Icons.radio_button_unchecked,
        color: done
            ? const Color(0xFF16A34A)
            : active
            ? const Color(0xFF0F4C81)
            : const Color(0xFF64748B),
      ),
      title: Text(
        guide.title,
        style: const TextStyle(fontWeight: FontWeight.w800),
      ),
      subtitle: compact && !active ? null : Text(guide.instruction),
    );
  }
}

class _ActionBar extends StatelessWidget {
  const _ActionBar({
    required this.snapshot,
    required this.guide,
    required this.capturing,
    required this.submitting,
    required this.onCapture,
    required this.onReset,
    required this.onBack,
  });

  final DemoFaceIdSnapshot snapshot;
  final _IdentityGuide guide;
  final bool capturing;
  final bool submitting;
  final VoidCallback onCapture;
  final VoidCallback onReset;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        FilledButton.icon(
          onPressed: snapshot.isComplete || capturing || submitting
              ? null
              : onCapture,
          icon: capturing || submitting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(guide.icon),
          label: Text(_captureText(snapshot, guide, submitting)),
        ),
        OutlinedButton.icon(
          onPressed: onReset,
          icon: const Icon(Icons.refresh),
          label: const Text('Reset'),
        ),
        TextButton.icon(
          onPressed: onBack,
          icon: const Icon(Icons.arrow_back),
          label: const Text('Back'),
        ),
      ],
    );
  }
}

class _MobileCaptureBar extends StatelessWidget {
  const _MobileCaptureBar({
    required this.snapshot,
    required this.guide,
    required this.capturing,
    required this.submitting,
    required this.onCapture,
    required this.onReset,
  });

  final DemoFaceIdSnapshot snapshot;
  final _IdentityGuide guide;
  final bool capturing;
  final bool submitting;
  final VoidCallback onCapture;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: Color(0xFFE2E8F0))),
        ),
        child: Row(
          children: [
            IconButton.filledTonal(
              onPressed: onReset,
              icon: const Icon(Icons.refresh),
              tooltip: 'Reset identity images',
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton.icon(
                onPressed: snapshot.isComplete || capturing || submitting
                    ? null
                    : onCapture,
                icon: capturing || submitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(guide.icon),
                label: Text(
                  _captureText(snapshot, guide, submitting),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _captureText(
  DemoFaceIdSnapshot snapshot,
  _IdentityGuide guide,
  bool submitting,
) {
  if (submitting) return 'Submitting...';
  if (snapshot.isComplete) return 'Enrollment active';
  return 'Capture ${guide.title}';
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          SizedBox(
            width: 150,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

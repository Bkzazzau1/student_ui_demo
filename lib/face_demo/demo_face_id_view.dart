import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import 'demo_face_id_service.dart';

class DemoFaceIdView extends StatefulWidget {
  const DemoFaceIdView({super.key, this.onComplete});

  final VoidCallback? onComplete;

  @override
  State<DemoFaceIdView> createState() => _DemoFaceIdViewState();
}

class _DemoFaceIdViewState extends State<DemoFaceIdView> {
  final DemoFaceIdService _service = DemoFaceIdService();
  late DemoFaceIdSnapshot _snapshot;
  CameraController? _controller;
  bool _openingCamera = false;
  bool _capturing = false;
  String? _cameraError;

  @override
  void initState() {
    super.initState();
    _snapshot = _service.load();
    _openCamera();
  }

  @override
  void dispose() {
    _controller?.dispose();
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
          _cameraError = 'No camera found. A fallback quality sample is available.';
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
        _cameraError =
            'Camera could not open. A fallback quality sample is available: $e';
      });
    }
  }

  Future<void> _captureSample() async {
    if (_capturing || _snapshot.isComplete) return;
    setState(() => _capturing = true);
    var quality = 0.72 + math.Random().nextDouble() * 0.22;
    try {
      final controller = _controller;
      if (controller != null && controller.value.isInitialized) {
        final file = await controller.takePicture();
        final size = await file.length();
        quality = (0.68 + math.min(size / 900000, 0.25)).clamp(0.0, 1.0);
      }
    } catch (e) {
      _cameraError =
          'Camera sample failed, so a fallback quality sample was used: $e';
    }
    final next = await _service.addSample(qualityScore: quality);
    if (!mounted) return;
    setState(() {
      _snapshot = next;
      _capturing = false;
    });
    if (next.isComplete && widget.onComplete != null) {
      widget.onComplete!();
    }
  }

  Future<void> _reset() async {
    final next = await _service.reset();
    if (!mounted) return;
    setState(() => _snapshot = next);
  }

  @override
  Widget build(BuildContext context) {
    final progress = _snapshot.capturedSamples / _snapshot.requiredSamples;
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      appBar: AppBar(title: const Text('Face ID setup')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(18),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 920),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Header(snapshot: _snapshot),
                  const SizedBox(height: 14),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final wide = constraints.maxWidth >= 760;
                      final preview = _CameraPreviewPanel(
                        controller: _controller,
                        openingCamera: _openingCamera,
                        cameraError: _cameraError,
                      );
                      final status = _StatusPanel(
                        snapshot: _snapshot,
                        progress: progress,
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
                          Expanded(child: preview),
                          const SizedBox(width: 14),
                          Expanded(child: status),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      FilledButton.icon(
                        onPressed: _snapshot.isComplete || _capturing
                            ? null
                            : _captureSample,
                        icon: _capturing
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.camera_alt_outlined),
                        label: Text(
                          _snapshot.isComplete
                              ? 'Face ID active'
                              : 'Capture face sample',
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: _reset,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Reset Face ID'),
                      ),
                      TextButton.icon(
                        onPressed: () =>
                            Navigator.of(context).pop(_snapshot.isComplete),
                        icon: const Icon(Icons.arrow_back),
                        label: const Text('Back'),
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

class _Header extends StatelessWidget {
  const _Header({required this.snapshot});

  final DemoFaceIdSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(
            snapshot.isComplete
                ? Icons.verified_user_rounded
                : Icons.face_retouching_natural,
            color: Colors.white,
            size: 44,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  snapshot.isComplete
                      ? 'Face ID enrollment active'
                      : 'Register Face ID for secure exams',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  snapshot.statusText,
                  style: const TextStyle(color: Color(0xFFCBD5E1)),
                ),
              ],
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
  });

  final CameraController? controller;
  final bool openingCamera;
  final String? cameraError;

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
        aspectRatio: 4 / 3,
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
                width: 210,
                height: 250,
                decoration: BoxDecoration(
                  border: Border.all(color: const Color(0xFF22C55E), width: 2),
                  borderRadius: BorderRadius.circular(110),
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
  const _StatusPanel({required this.snapshot, required this.progress});

  final DemoFaceIdSnapshot snapshot;
  final double progress;

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
          _Row(label: 'Required samples', value: '${snapshot.requiredSamples}'),
          _Row(label: 'Captured samples', value: '${snapshot.capturedSamples}'),
          _Row(
            label: 'Status',
            value: snapshot.isComplete ? 'Active' : 'Pending',
          ),
          if (snapshot.lastQualityScore != null)
            _Row(
              label: 'Last quality',
              value: '${(snapshot.lastQualityScore! * 100).round()}%',
            ),
          const SizedBox(height: 12),
          LinearProgressIndicator(value: progress.clamp(0.0, 1.0)),
        ],
      ),
    );
  }
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

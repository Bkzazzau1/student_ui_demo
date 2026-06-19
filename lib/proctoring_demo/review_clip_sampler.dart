import 'dart:async';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import 'live_proctoring_event_service.dart';

class ReviewClipSampler extends StatefulWidget {
  const ReviewClipSampler({
    super.key,
    required this.studentId,
    required this.examId,
    required this.attemptId,
    required this.examDurationSeconds,
  });

  final String studentId;
  final String examId;
  final String attemptId;
  final int examDurationSeconds;

  @override
  State<ReviewClipSampler> createState() => _ReviewClipSamplerState();
}

class _ReviewClipSamplerState extends State<ReviewClipSampler> {
  static const int _sampleCount = 5;
  static const int _clipSeconds = 10;

  final LiveProctoringEventService _events = LiveProctoringEventService(
    baseUrl: const String.fromEnvironment(
      'KSLAS_API_BASE_URL',
      defaultValue: 'http://127.0.0.1:8080',
    ),
  );
  final List<Timer> _timers = <Timer>[];
  final List<String> _captured = <String>[];
  final math.Random _random = math.Random();

  CameraController? _camera;
  bool _ready = false;
  bool _recording = false;
  String _status = 'Scheduling quality review clips...';

  @override
  void initState() {
    super.initState();
    unawaited(_prepareCameraAndSchedule());
  }

  @override
  void dispose() {
    for (final timer in _timers) {
      timer.cancel();
    }
    _camera?.dispose();
    _events.dispose();
    super.dispose();
  }

  Future<void> _prepareCameraAndSchedule() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        await _sendEvent(
          eventType: 'review_clip_camera_unavailable',
          severity: 'warning',
          message: 'Camera was unavailable for random review clip capture.',
        );
        if (!mounted) return;
        setState(() => _status = 'Review clip camera unavailable');
        return;
      }
      final camera = cameras.firstWhere(
        (item) => item.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        camera,
        ResolutionPreset.low,
        enableAudio: false,
      );
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _camera = controller;
        _ready = true;
        _status = 'Five random 10-second review clips scheduled';
      });
      _scheduleSamples();
    } catch (e) {
      await _sendEvent(
        eventType: 'review_clip_setup_failed',
        severity: 'warning',
        message: 'Random review clip setup failed.',
        metadata: <String, Object?>{'error': e.toString()},
      );
      if (!mounted) return;
      setState(() => _status = 'Review clip setup unavailable');
    }
  }

  void _scheduleSamples() {
    final duration = math.max(widget.examDurationSeconds, _sampleCount * 20);
    final latestStart = math.max(20, duration - _clipSeconds - 10);
    final segment = latestStart / _sampleCount;

    for (var i = 0; i < _sampleCount; i++) {
      final startMin = (i * segment).round() + 5;
      final startMax = math.max(startMin + 1, ((i + 1) * segment).round());
      final second = startMin + _random.nextInt(math.max(1, startMax - startMin));
      _timers.add(
        Timer(Duration(seconds: second), () {
          unawaited(_captureSample(i + 1));
        }),
      );
    }
  }

  Future<void> _captureSample(int sampleNumber) async {
    final controller = _camera;
    if (controller == null || !controller.value.isInitialized || _recording) return;
    setState(() {
      _recording = true;
      _status = 'Capturing review clip $sampleNumber of $_sampleCount';
    });

    try {
      await controller.startVideoRecording();
      await Future<void>.delayed(const Duration(seconds: _clipSeconds));
      final file = await controller.stopVideoRecording();
      _captured.add(file.path);
      await _sendEvent(
        eventType: 'review_clip_captured',
        severity: 'info',
        message: 'A 10-second review clip was captured for invigilator review.',
        metadata: <String, Object?>{
          'sample_number': sampleNumber,
          'total_samples': _sampleCount,
          'duration_seconds': _clipSeconds,
          'local_path': file.path,
          'review_timing': 'during_or_after_exam',
        },
      );
      if (!mounted) return;
      setState(() => _status = 'Review clips captured: ${_captured.length}/$_sampleCount');
    } catch (e) {
      try {
        if (controller.value.isRecordingVideo) {
          await controller.stopVideoRecording();
        }
      } catch (_) {}
      await _sendEvent(
        eventType: 'review_clip_capture_failed',
        severity: 'warning',
        message: 'A scheduled review clip could not be captured.',
        metadata: <String, Object?>{
          'sample_number': sampleNumber,
          'error': e.toString(),
        },
      );
      if (!mounted) return;
      setState(() => _status = 'Review clip capture failed');
    } finally {
      if (mounted) setState(() => _recording = false);
    }
  }

  Future<void> _sendEvent({
    required String eventType,
    required String severity,
    required String message,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) {
    return _events.send(
      LiveProctoringEvent(
        studentId: widget.studentId,
        examId: widget.examId,
        attemptId: widget.attemptId,
        eventType: eventType,
        severity: severity,
        message: message,
        createdAt: DateTime.now(),
        metadata: metadata,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(
              _recording
                  ? Icons.fiber_manual_record
                  : _ready
                  ? Icons.video_camera_front_outlined
                  : Icons.schedule,
              color: _recording
                  ? const Color(0xFFDC2626)
                  : _ready
                  ? const Color(0xFF16A34A)
                  : const Color(0xFFF59E0B),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _status,
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import 'audio_fingerprint_isolation_service.dart';
import 'landmark_gaze_runtime_selector.dart';
import 'live_proctoring_event_service.dart';
import 'microphone_stream_recording_service.dart';

class LiveExamMonitor extends StatefulWidget {
  const LiveExamMonitor({
    super.key,
    required this.studentId,
    required this.examId,
    required this.attemptId,
    required this.onCriticalEvent,
  });

  final String studentId;
  final String examId;
  final String attemptId;
  final ValueChanged<String> onCriticalEvent;

  @override
  State<LiveExamMonitor> createState() => _LiveExamMonitorState();
}

class _LiveExamMonitorState extends State<LiveExamMonitor> {
  final LiveProctoringEventService _events = LiveProctoringEventService(
    baseUrl: const String.fromEnvironment(
      'KSLAS_API_BASE_URL',
      defaultValue: 'http://127.0.0.1:8080',
    ),
  );
  final MicrophoneStreamRecordingService _microphone =
      MicrophoneStreamRecordingService();
  final LandmarkGazeRuntimeSelector _gazeEstimator =
      LandmarkGazeRuntimeSelector();
  final AudioFingerprintIsolationService _audioIsolation =
      AudioFingerprintIsolationService();

  CameraController? _camera;
  Timer? _heartbeat;
  StreamSubscription<dynamic>? _placeholder;

  final Map<String, DateTime> _lastEventAt = <String, DateTime>{};
  final List<String> _eventsSent = <String>[];

  String _cameraStatus = 'Opening camera...';
  String _audioStatus = 'Starting sound monitor...';
  String _systemStatus = 'Checking system...';
  String _gazeStatus = 'Starting gaze and head pose monitor...';
  bool _cameraReady = false;
  bool _audioReady = false;
  bool _systemReady = false;
  bool _gazeReady = false;
  bool _openingCamera = false;
  bool _analysingGazeFrame = false;
  int _secondsLive = 0;
  int _gazeRiskStreak = 0;
  int _voiceRiskStreak = 0;
  DateTime? _lastGazeFrameAt;

  @override
  void initState() {
    super.initState();
    unawaited(_startCamera());
    unawaited(_startAudio());
    _startHeartbeat();
  }

  @override
  void dispose() {
    _heartbeat?.cancel();
    _placeholder?.cancel();
    final camera = _camera;
    if (camera != null && camera.value.isStreamingImages) {
      unawaited(camera.stopImageStream());
    }
    camera?.dispose();
    _microphone.dispose();
    _events.dispose();
    super.dispose();
  }

  Future<void> _startCamera() async {
    if (_openingCamera) return;
    setState(() {
      _openingCamera = true;
      _cameraStatus = 'Opening camera...';
      _gazeStatus = 'Starting gaze and head pose monitor...';
    });
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        await _raiseEvent(
          eventType: 'camera_unavailable',
          severity: 'critical',
          message: 'Camera was not found during the exam.',
        );
        if (!mounted) return;
        setState(() {
          _openingCamera = false;
          _cameraReady = false;
          _gazeReady = false;
          _cameraStatus = 'Camera not found';
          _gazeStatus = 'Gaze and head pose monitor unavailable';
        });
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
      var gazeStreamReady = false;
      try {
        await controller.startImageStream(_handleCameraImage);
        gazeStreamReady = true;
      } catch (e) {
        await _raiseEvent(
          eventType: 'gaze_head_pose_monitor_unavailable',
          severity: 'warning',
          message: 'Gaze and head pose monitoring stream could not start.',
          metadata: <String, Object?>{'error': e.toString()},
        );
      }
      if (!mounted) {
        if (controller.value.isStreamingImages) {
          await controller.stopImageStream();
        }
        await controller.dispose();
        return;
      }
      setState(() {
        _camera = controller;
        _openingCamera = false;
        _cameraReady = true;
        _gazeReady = gazeStreamReady;
        _cameraStatus = 'Camera monitoring active';
        _gazeStatus = gazeStreamReady
            ? 'Gaze vector and head pose monitoring active'
            : 'Gaze stream unavailable on this device';
      });
    } catch (e) {
      await _raiseEvent(
        eventType: 'camera_unavailable',
        severity: 'critical',
        message: 'Camera monitoring stopped during the exam.',
        metadata: <String, Object?>{'error': e.toString()},
      );
      if (!mounted) return;
      setState(() {
        _openingCamera = false;
        _cameraReady = false;
        _gazeReady = false;
        _cameraStatus = 'Camera monitoring unavailable';
        _gazeStatus = 'Gaze and head pose monitor unavailable';
      });
    }
  }

  void _handleCameraImage(CameraImage image) {
    if (_analysingGazeFrame) return;
    _analysingGazeFrame = true;
    unawaited(_analyseCameraImage(image));
  }

  Future<void> _analyseCameraImage(CameraImage image) async {
    try {
      final result = await _gazeEstimator.analyse(image);
      if (result == null) return;
      _lastGazeFrameAt = DateTime.now();

      if (result.lookingAway && result.confidence >= 0.55) {
        _gazeRiskStreak++;
      } else {
        _gazeRiskStreak = math.max(0, _gazeRiskStreak - 1);
      }

      if (mounted) {
        setState(() {
          _gazeReady = true;
          _gazeStatus = result.lookingAway
              ? 'Possible looking away detected ($_gazeRiskStreak/3)'
              : 'Focused forward • gaze/head pose stable';
        });
      }

      if (_gazeRiskStreak >= 3) {
        _gazeRiskStreak = 0;
        unawaited(
          _raiseEvent(
            eventType: 'gaze_head_pose_deviation',
            severity: 'high',
            message:
                'Sustained looking-away or head-pose deviation was detected during the exam.',
            metadata: result.toJson(),
          ),
        );
      }
    } catch (_) {
      return;
    } finally {
      _analysingGazeFrame = false;
    }
  }

  Future<void> _startAudio() async {
    try {
      final permission = await _microphone.hasPermission();
      if (!permission) {
        await _raiseEvent(
          eventType: 'microphone_unavailable',
          severity: 'critical',
          message: 'Microphone permission was not available during the exam.',
        );
        if (!mounted) return;
        setState(() {
          _audioReady = false;
          _audioStatus = 'Microphone unavailable';
        });
        return;
      }

      await _microphone.start(
        sampleRate: 44100,
        maxBufferSeconds: 20,
        onPcmChunk: _handleAudioChunk,
      );
      if (!mounted) return;
      setState(() {
        _audioReady = true;
        _audioStatus = 'Audio fingerprinting and voice isolation active';
      });
    } catch (e) {
      await _raiseEvent(
        eventType: 'microphone_unavailable',
        severity: 'critical',
        message: 'Microphone monitoring stopped during the exam.',
        metadata: <String, Object?>{'error': e.toString()},
      );
      if (!mounted) return;
      setState(() {
        _audioReady = false;
        _audioStatus = 'Sound monitoring unavailable';
      });
    }
  }

  void _handleAudioChunk(Uint8List chunk) {
    final result = _audioIsolation.analysePcm16(chunk);
    if (result == null) return;

    if (mounted) {
      setState(() {
        _audioStatus = result.humanVoiceLikely
            ? 'Human voice likely detected (${_voiceRiskStreak + 1}/3)'
            : result.allowedAmbientLikely
                ? 'Allowed ambient audio fingerprint: ${result.label}'
                : 'Unclear environment sound fingerprinted';
      });
    }

    if (result.humanVoiceLikely) {
      _voiceRiskStreak++;
    } else {
      _voiceRiskStreak = math.max(0, _voiceRiskStreak - 1);
    }

    if (_voiceRiskStreak >= 3) {
      _voiceRiskStreak = 0;
      unawaited(
        _raiseEvent(
          eventType: 'audio_voice_isolation_alert',
          severity: 'high',
          message: 'Human voice was isolated from the exam audio environment.',
          metadata: result.toJson(),
        ),
      );
    } else if (result.repeatedFingerprint && !result.allowedAmbientLikely) {
      unawaited(
        _raiseEvent(
          eventType: 'audio_repeated_fingerprint_detected',
          severity: 'warning',
          message: 'A repeated non-ambient audio fingerprint was detected.',
          metadata: result.toJson(),
        ),
      );
    }
  }

  void _startHeartbeat() {
    _heartbeat?.cancel();
    _heartbeat = Timer.periodic(const Duration(seconds: 5), (_) async {
      if (!mounted) return;
      final cameraStillReady = _camera?.value.isInitialized ?? false;
      final platformOk =
          Platform.isWindows || Platform.isLinux || Platform.isMacOS;
      final gazeFresh =
          _lastGazeFrameAt != null &&
          DateTime.now().difference(_lastGazeFrameAt!).inSeconds <= 12;
      setState(() {
        _secondsLive += 5;
        _cameraReady = cameraStillReady;
        _systemReady = platformOk;
        _gazeReady = _gazeReady && gazeFresh;
        _systemStatus = platformOk
            ? 'System monitoring active'
            : 'Unsupported system environment';
        if (cameraStillReady && !_gazeReady) {
          _gazeStatus = 'Gaze and head pose monitor not receiving frames';
        }
      });

      if (!cameraStillReady) {
        await _raiseEvent(
          eventType: 'camera_unavailable',
          severity: 'critical',
          message: 'Camera heartbeat failed during the exam.',
        );
      }
      if (!_microphone.isRunning) {
        setState(() {
          _audioReady = false;
          _audioStatus = 'Sound monitoring unavailable';
        });
        await _raiseEvent(
          eventType: 'microphone_unavailable',
          severity: 'critical',
          message: 'Microphone heartbeat failed during the exam.',
        );
      }
      if (!platformOk) {
        await _raiseEvent(
          eventType: 'system_monitoring_unavailable',
          severity: 'critical',
          message: 'System monitoring is not available on this device.',
        );
      }
      if (cameraStillReady && !gazeFresh) {
        await _raiseEvent(
          eventType: 'gaze_head_pose_monitor_unavailable',
          severity: 'warning',
          message: 'Gaze and head pose monitor is not receiving camera frames.',
        );
      }
    });
  }

  Future<void> _raiseEvent({
    required String eventType,
    required String severity,
    required String message,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) async {
    if (!_shouldEmit(eventType)) return;
    final event = LiveProctoringEvent(
      studentId: widget.studentId,
      examId: widget.examId,
      attemptId: widget.attemptId,
      eventType: eventType,
      severity: severity,
      message: message,
      createdAt: DateTime.now(),
      metadata: metadata,
    );
    final synced = await _events.send(event);
    if (!mounted) return;
    setState(() {
      _eventsSent.insert(
        0,
        synced ? '$eventType sent' : '$eventType queued locally',
      );
      if (_eventsSent.length > 5) _eventsSent.removeLast();
    });
    if (severity == 'critical' || severity == 'high') {
      widget.onCriticalEvent(
        synced
            ? message
            : '$message Monitoring event could not be confirmed by the backend.',
      );
    }
  }

  bool _shouldEmit(String eventType) {
    final now = DateTime.now();
    final last = _lastEventAt[eventType];
    if (last != null && now.difference(last).inSeconds < 15) {
      return false;
    }
    _lastEventAt[eventType] = now;
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final ready = _camera?.value.isInitialized ?? false;
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _StatusRow(
              label: _cameraStatus,
              ready: _cameraReady,
              icon: Icons.videocam,
            ),
            const SizedBox(height: 10),
            AspectRatio(
              aspectRatio: 16 / 9,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: ready
                    ? CameraPreview(_camera!)
                    : Container(
                        color: const Color(0xFF101828),
                        alignment: Alignment.center,
                        child: Text(
                          _cameraStatus,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white),
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 10),
            _StatusRow(
              label: _audioStatus,
              ready: _audioReady,
              icon: Icons.mic,
            ),
            const SizedBox(height: 8),
            _StatusRow(
              label: _gazeStatus,
              ready: _gazeReady,
              icon: Icons.visibility_outlined,
            ),
            const SizedBox(height: 8),
            _StatusRow(
              label: _systemStatus,
              ready: _systemReady,
              icon: Icons.desktop_windows,
            ),
            const SizedBox(height: 8),
            Text('Live duration: ${_secondsLive}s'),
            if (_eventsSent.isNotEmpty) ...[
              const SizedBox(height: 8),
              ..._eventsSent.map(
                (event) =>
                    Text(event, style: Theme.of(context).textTheme.bodySmall),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({
    required this.label,
    required this.ready,
    required this.icon,
  });

  final String label;
  final bool ready;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(
          icon,
          color: ready ? const Color(0xFF16A34A) : const Color(0xFFDC2626),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
        ),
      ],
    );
  }
}

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import 'audio_fingerprint_isolation_service.dart';
import 'continuous_biometric_liveness_service.dart';
import 'landmark_gaze_runtime_selector.dart';
import 'live_proctoring_event_service.dart';
import 'microphone_stream_recording_service.dart';
import 'optimized_vision_runtime_bridge.dart';
import 'snapshot_gaze_fallback_service.dart';
import 'visual_reflection_shadow_service.dart';
import 'vision_compute_budget_service.dart';

class LiveExamMonitor extends StatefulWidget {
  const LiveExamMonitor({
    super.key,
    required this.studentId,
    required this.examId,
    required this.attemptId,
    required this.onCriticalEvent,
    this.assessmentType = 'exam',
    this.reviewAudience = 'invigilator',
  });

  final String studentId;
  final String examId;
  final String attemptId;
  final ValueChanged<String> onCriticalEvent;
  final String assessmentType;
  final String reviewAudience;

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
  final ContinuousBiometricLivenessService _continuousLiveness =
      ContinuousBiometricLivenessService();
  final VisualReflectionShadowService _visualIntegrity =
      VisualReflectionShadowService();
  final OptimizedVisionRuntimeBridge _optimizedVision =
      OptimizedVisionRuntimeBridge();
  final SnapshotGazeFallbackService _snapshotGazeFallback =
      SnapshotGazeFallbackService();
  final VisionComputeBudgetService _visionBudget = VisionComputeBudgetService();

  CameraController? _camera;
  Timer? _heartbeat;
  Timer? _snapshotFallbackTimer;

  final Map<String, DateTime> _lastEventAt = <String, DateTime>{};
  final List<String> _eventsSent = <String>[];

  String _cameraStatus = 'Opening camera...';
  String _audioStatus = 'Starting sound monitor...';
  String _systemStatus = 'Checking system...';
  String _gazeStatus = 'Starting 1-second gaze/head check...';
  String _livenessStatus = 'Starting presence check...';
  String _visualStatus = 'Starting object/person check...';
  bool _cameraReady = false;
  bool _audioReady = false;
  bool _systemReady = false;
  bool _gazeReady = false;
  bool _livenessReady = false;
  bool _visualReady = false;
  bool _openingCamera = false;
  bool _analysingFrame = false;
  bool _imageStreamAvailable = false;
  bool _snapshotFallbackBusy = false;
  int _secondsLive = 0;
  int _gazeRiskStreak = 0;
  int _voiceRiskStreak = 0;
  int _spoofRiskStreak = 0;
  int _visualRiskStreak = 0;
  int _multiplePeopleRiskStreak = 0;

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
    _snapshotFallbackTimer?.cancel();
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
      _gazeStatus = 'Starting 1-second gaze/head check...';
      _livenessStatus = 'Starting presence check...';
      _visualStatus = 'Starting object/person check...';
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
          _livenessReady = false;
          _visualReady = false;
          _cameraStatus = 'Camera not found';
          _gazeStatus = 'Gaze/head check unavailable';
          _livenessStatus = 'Presence check unavailable';
          _visualStatus = 'Object/person check unavailable';
        });
        return;
      }
      final selected = cameras.firstWhere(
        (item) => item.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        selected,
        ResolutionPreset.low,
        enableAudio: false,
      );
      await controller.initialize();
      var streamReady = false;
      try {
        await controller.startImageStream(_handleCameraImage);
        streamReady = true;
      } catch (_) {
        streamReady = false;
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
        _imageStreamAvailable = streamReady;
        _gazeReady = true;
        _livenessReady = true;
        _visualReady = true;
        _cameraStatus = 'Camera preview active';
        if (streamReady) {
          _snapshotFallbackTimer?.cancel();
          _gazeStatus = 'Gaze vector and head pose monitoring active';
          _livenessStatus = 'Continuous liveness anti-spoofing active';
          _visualStatus = 'Object/reflection/person scan active';
        } else {
          _gazeStatus = '1-second snapshot gaze/head check active';
          _livenessStatus = 'Snapshot presence check active';
          _visualStatus = 'Snapshot object/person check active';
        }
      });
      if (!streamReady) {
        _startSnapshotCameraChecks(controller);
      }
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
        _livenessReady = false;
        _visualReady = false;
        _imageStreamAvailable = false;
        _cameraStatus = 'Camera monitoring unavailable';
        _gazeStatus = 'Gaze/head check unavailable';
        _livenessStatus = 'Presence check unavailable';
        _visualStatus = 'Object/person check unavailable';
      });
    }
  }

  void _startSnapshotCameraChecks(CameraController controller) {
    _snapshotFallbackTimer?.cancel();
    _snapshotFallbackTimer = Timer.periodic(const Duration(seconds: 1), (_) async {
      if (!mounted) return;
      if (_imageStreamAvailable || controller.value.isStreamingImages) return;
      if (!controller.value.isInitialized || controller.value.isTakingPicture) return;
      if (_snapshotFallbackBusy) return;
      _snapshotFallbackBusy = true;
      try {
        final picture = await controller.takePicture();
        final bytes = await picture.readAsBytes();
        final result = _snapshotGazeFallback.analyseJpeg(bytes);
        if (result == null) return;

        if (result.ready && result.headPoseShiftLikely) {
          _gazeRiskStreak++;
        } else {
          _gazeRiskStreak = math.max(0, _gazeRiskStreak - 1);
        }

        if (result.ready && result.multiplePeopleLikely) {
          _multiplePeopleRiskStreak++;
        } else {
          _multiplePeopleRiskStreak = math.max(0, _multiplePeopleRiskStreak - 1);
        }

        if (mounted) {
          setState(() {
            _gazeReady = true;
            _visualReady = true;
            _livenessReady = true;
            _gazeStatus = !result.ready
                ? '1-second gaze/head check learning normal position'
                : result.headPoseShiftLikely
                    ? 'Focus reminder shown ($_gazeRiskStreak/3)'
                    : '1-second gaze/head check stable';
            _visualStatus = result.multiplePeopleLikely
                ? 'Possible second person detected ($_multiplePeopleRiskStreak/2)'
                : 'Snapshot object/person check clear';
            _livenessStatus = 'Snapshot presence check active';
          });
        }

        if (_multiplePeopleRiskStreak >= 2) {
          _multiplePeopleRiskStreak = 0;
          unawaited(
            _raiseEvent(
              eventType: 'multiple_people_detected',
              severity: 'high',
              message: 'More than one person may be visible in the exam camera view.',
              metadata: result.toJson(),
            ),
          );
        }

        if (_gazeRiskStreak >= 3) {
          _gazeRiskStreak = 0;
          unawaited(
            _raiseEvent(
              eventType: 'gaze_head_pose_deviation',
              severity: 'warning',
              message: 'Please keep your face visible and focus on the screen.',
              metadata: result.toJson(),
            ),
          );
        }
      } catch (_) {
        if (mounted) {
          setState(() {
            _gazeStatus = '1-second snapshot gaze/head check waiting';
            _visualStatus = 'Snapshot object/person check waiting';
          });
        }
      } finally {
        _snapshotFallbackBusy = false;
      }
    });
  }

  void _handleCameraImage(CameraImage image) {
    _imageStreamAvailable = true;
    if (_analysingFrame) return;
    if (!_visionBudget.shouldProcessFrame()) return;
    final started = DateTime.now();
    _analysingFrame = true;
    unawaited(_analyseCameraImage(image, started));
  }

  Future<void> _analyseCameraImage(CameraImage image, DateTime started) async {
    try {
      final visual = _visualIntegrity.analyse(image);
      if (visual != null) _handleVisualIntegrityResult(visual);

      final optimized = await _optimizedVision.runFrame(
        image: image,
        tasks: const <String>[
          'person_detector',
          'object_reflection_shadow_detector',
        ],
      );
      if (optimized != null && optimized.available) {
        _handleOptimizedVisionResult(optimized);
      }

      final liveness = _continuousLiveness.analyse(image);
      if (liveness != null) _handleLivenessResult(liveness);

      final gaze = await _gazeEstimator.analyse(image);
      if (gaze == null) return;
      if (gaze.lookingAway && gaze.confidence >= 0.55) {
        _gazeRiskStreak++;
      } else {
        _gazeRiskStreak = math.max(0, _gazeRiskStreak - 1);
      }
      if (mounted) {
        setState(() {
          _gazeReady = true;
          _gazeStatus = gaze.lookingAway
              ? 'Focus reminder shown ($_gazeRiskStreak/3)'
              : 'Focused forward • gaze/head pose stable';
        });
      }
      if (_gazeRiskStreak >= 3) {
        _gazeRiskStreak = 0;
        unawaited(
          _raiseEvent(
            eventType: 'gaze_head_pose_deviation',
            severity: 'warning',
            message: 'Please keep your face visible and focus on the screen.',
            metadata: gaze.toJson(),
          ),
        );
      }
    } finally {
      _visionBudget.recordWork(DateTime.now().difference(started));
      _analysingFrame = false;
    }
  }

  void _handleOptimizedVisionResult(OptimizedVisionRuntimeResult result) {
    final objects = (result.outputs['objects'] as List? ?? const <Object?>[])
        .whereType<Map>()
        .map((item) => Map<String, Object?>.from(item))
        .toList();
    final personObjects = objects.where((object) {
      final label = '${object['label'] ?? object['class'] ?? object['name'] ?? ''}'.toLowerCase();
      return label.contains('person') || label.contains('human') || label.contains('face');
    }).toList();
    final nativePersonCount = int.tryParse('${result.outputs['person_count'] ?? ''}') ?? 0;
    final nativeMultiplePeople = result.outputs['multiple_people_likely'] == true;
    final multiplePeople = nativeMultiplePeople || nativePersonCount >= 2 || personObjects.length >= 2;
    if (multiplePeople) {
      _multiplePeopleRiskStreak++;
    } else {
      _multiplePeopleRiskStreak = math.max(0, _multiplePeopleRiskStreak - 1);
    }
    if (mounted) {
      setState(() {
        _visualReady = true;
        _visualStatus = multiplePeople
            ? 'Possible second person detected ($_multiplePeopleRiskStreak/2)'
            : 'Object/person scan active (${result.inferenceMs.toStringAsFixed(1)} ms)';
      });
    }
    if (_multiplePeopleRiskStreak >= 2) {
      _multiplePeopleRiskStreak = 0;
      unawaited(
        _raiseEvent(
          eventType: 'multiple_people_detected',
          severity: 'high',
          message: 'More than one person may be visible in the exam camera view.',
          metadata: result.toJson(),
        ),
      );
    }
  }

  void _handleVisualIntegrityResult(VisualReflectionShadowResult result) {
    if (result.visualRiskScore >= 0.58 ||
        result.screenGlowLikely ||
        result.mirrorOrGlassLikely ||
        result.offscreenInteractionLikely) {
      _visualRiskStreak++;
    } else {
      _visualRiskStreak = math.max(0, _visualRiskStreak - 1);
    }
    if (mounted && _multiplePeopleRiskStreak == 0) {
      setState(() {
        _visualReady = true;
        _visualStatus = result.visualRiskScore >= 0.58
            ? 'Possible object/reflection risk ($_visualRiskStreak/3)'
            : 'Object/reflection check clear';
      });
    }
    if (_visualRiskStreak >= 3) {
      _visualRiskStreak = 0;
      unawaited(
        _raiseEvent(
          eventType: 'object_reflection_shadow_risk',
          severity: 'high',
          message: 'Suspicious reflection, screen glow, shadow shift, or off-screen interaction pattern was detected.',
          metadata: result.toJson(),
        ),
      );
    }
  }

  void _handleLivenessResult(ContinuousLivenessResult result) {
    if (result.spoofRiskScore >= 0.70 || result.replayOrFreezeLikely) {
      _spoofRiskStreak++;
    } else {
      _spoofRiskStreak = math.max(0, _spoofRiskStreak - 1);
    }
    if (mounted) {
      setState(() {
        _livenessReady = true;
        _livenessStatus = result.replayOrFreezeLikely
            ? 'Possible spoof/replay risk ($_spoofRiskStreak/3)'
            : 'Presence check active';
      });
    }
    if (_spoofRiskStreak >= 3) {
      _spoofRiskStreak = 0;
      unawaited(
        _raiseEvent(
          eventType: 'continuous_liveness_spoof_risk',
          severity: 'high',
          message: 'Continuous liveness check detected possible photo, screen, replay, or frozen-frame behaviour.',
          metadata: result.toJson(),
        ),
      );
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
        _audioStatus = 'Sound check active';
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
            ? 'Voice noticed (${_voiceRiskStreak + 1}/3)'
            : result.allowedAmbientLikely
                ? 'Allowed ambient sound: ${result.label}'
                : 'Unclear environment sound noticed';
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
          message: 'Voice was noticed in the exam audio environment.',
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
      final platformOk = Platform.isWindows || Platform.isLinux || Platform.isMacOS;
      setState(() {
        _secondsLive += 5;
        _cameraReady = cameraStillReady;
        _systemReady = platformOk;
        _systemStatus = platformOk ? 'System monitoring active' : 'Unsupported system environment';
        if (cameraStillReady) {
          _gazeReady = true;
          _livenessReady = true;
          _visualReady = true;
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
      assessmentType: widget.assessmentType,
      reviewAudience: widget.reviewAudience,
    );
    final synced = await _events.send(event);
    if (!mounted) return;
    setState(() {
      _eventsSent.insert(0, synced ? '$eventType sent' : '$eventType queued locally');
      if (_eventsSent.length > 5) _eventsSent.removeLast();
    });
    if (_shouldPauseAttempt(eventType: eventType, severity: severity)) {
      widget.onCriticalEvent(
        synced ? message : '$message Monitoring event could not be confirmed by the system.',
      );
    }
  }

  bool _shouldPauseAttempt({required String eventType, required String severity}) {
    if (severity == 'critical') return true;
    const hardPauseEvents = <String>{
      'multiple_people_detected',
      'object_reflection_shadow_risk',
      'continuous_liveness_spoof_risk',
      'audio_voice_isolation_alert',
    };
    return hardPauseEvents.contains(eventType);
  }

  bool _shouldEmit(String eventType) {
    final now = DateTime.now();
    final last = _lastEventAt[eventType];
    if (last != null && now.difference(last).inSeconds < 15) return false;
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
            _StatusRow(label: _cameraStatus, ready: _cameraReady, icon: Icons.videocam),
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
            _StatusRow(label: _audioStatus, ready: _audioReady, icon: Icons.mic),
            const SizedBox(height: 8),
            _StatusRow(label: _visualStatus, ready: _visualReady, icon: Icons.light_mode_outlined),
            const SizedBox(height: 8),
            _StatusRow(label: _livenessStatus, ready: _livenessReady, icon: Icons.verified_user_outlined),
            const SizedBox(height: 8),
            _StatusRow(label: _gazeStatus, ready: _gazeReady, icon: Icons.visibility_outlined),
            const SizedBox(height: 8),
            _StatusRow(label: _systemStatus, ready: _systemReady, icon: Icons.desktop_windows),
            const SizedBox(height: 8),
            Text('Live duration: ${_secondsLive}s'),
            if (_eventsSent.isNotEmpty) ...[
              const SizedBox(height: 8),
              ..._eventsSent.map(
                (event) => Text(event, style: Theme.of(context).textTheme.bodySmall),
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
    final color = ready ? const Color(0xFF16A34A) : const Color(0xFFDC2626);
    return Row(
      children: [
        Icon(icon, color: color),
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

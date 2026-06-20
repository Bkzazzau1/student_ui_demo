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
  StreamSubscription<dynamic>? _placeholder;

  final Map<String, DateTime> _lastEventAt = <String, DateTime>{};
  final List<String> _eventsSent = <String>[];

  String _cameraStatus = 'Opening camera...';
  String _audioStatus = 'Starting sound monitor...';
  String _systemStatus = 'Checking system...';
  String _gazeStatus = 'Starting gaze and head pose monitor...';
  String _livenessStatus = 'Starting continuous liveness anti-spoofing...';
  String _visualStatus = 'Starting reflection, shadow, and object integrity scan...';
  bool _cameraReady = false;
  bool _audioReady = false;
  bool _systemReady = false;
  bool _gazeReady = false;
  bool _livenessReady = false;
  bool _visualReady = false;
  bool _openingCamera = false;
  bool _analysingGazeFrame = false;
  bool _imageStreamAvailable = false;
  bool _advancedStreamNoticeSent = false;
  bool _snapshotFallbackBusy = false;
  int _secondsLive = 0;
  int _gazeRiskStreak = 0;
  int _voiceRiskStreak = 0;
  int _spoofRiskStreak = 0;
  int _visualRiskStreak = 0;
  DateTime? _lastGazeFrameAt;
  DateTime? _lastLivenessFrameAt;
  DateTime? _lastVisualFrameAt;

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
      _livenessStatus = 'Starting continuous liveness anti-spoofing...';
      _visualStatus = 'Starting reflection, shadow, and object integrity scan...';
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
          _gazeStatus = 'Gaze and head pose monitor unavailable';
          _livenessStatus = 'Continuous liveness anti-spoofing unavailable';
          _visualStatus = 'Reflection and object integrity scan unavailable';
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
      var streamReady = false;
      try {
        await controller.startImageStream(_handleCameraImage);
        streamReady = true;
      } catch (e) {
        streamReady = false;
        if (!_advancedStreamNoticeSent) {
          _advancedStreamNoticeSent = true;
          unawaited(
            _raiseEvent(
              eventType: 'snapshot_camera_analysis_active',
              severity: 'info',
              message:
                  'Camera preview is active. Snapshot camera checks are running on this device.',
              metadata: <String, Object?>{'error': e.toString()},
            ),
          );
        }
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
          _livenessStatus = 'Continuous local liveness anti-spoofing active';
          _visualStatus = 'Reflection, shadow, and object integrity scan active';
        } else {
          _gazeStatus = '1-second snapshot gaze/head check active';
          _livenessStatus = 'Presence check active';
          _visualStatus = 'Short camera checks active';
        }
      });
      if (!streamReady) {
        _startSnapshotGazeFallback(controller);
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
        _gazeStatus = 'Gaze and head pose monitor unavailable';
        _livenessStatus = 'Continuous liveness anti-spoofing unavailable';
        _visualStatus = 'Reflection and object integrity scan unavailable';
      });
    }
  }

  void _startSnapshotGazeFallback(CameraController controller) {
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
        _lastGazeFrameAt = DateTime.now();
        if (result.ready && result.headPoseShiftLikely) {
          _gazeRiskStreak++;
        } else {
          _gazeRiskStreak = math.max(0, _gazeRiskStreak - 1);
        }
        if (mounted) {
          setState(() {
            _gazeReady = true;
            _gazeStatus = !result.ready
                ? 'Snapshot gaze/head check learning normal position'
                : result.headPoseShiftLikely
                    ? 'Possible head/gaze movement detected ($_gazeRiskStreak/3)'
                    : 'Snapshot gaze/head check stable';
          });
        }
        if (_gazeRiskStreak >= 3) {
          _gazeRiskStreak = 0;
          unawaited(
            _raiseEvent(
              eventType: 'gaze_head_pose_deviation',
              severity: 'high',
              message:
                  'Sustained head or gaze movement was detected for at least 3 seconds.',
              metadata: result.toJson(),
            ),
          );
        }
      } catch (_) {
        if (mounted) {
          setState(() {
            _gazeStatus = 'Camera preview active; snapshot gaze/head check waiting';
          });
        }
      } finally {
        _snapshotFallbackBusy = false;
      }
    });
  }

  void _handleCameraImage(CameraImage image) {
    _imageStreamAvailable = true;
    if (_analysingGazeFrame) return;
    if (!_visionBudget.shouldProcessFrame()) return;
    final started = DateTime.now();
    _analysingGazeFrame = true;
    unawaited(_analyseCameraImage(image, started));
  }

  Future<void> _analyseCameraImage(CameraImage image, DateTime started) async {
    try {
      final visual = _visualIntegrity.analyse(image);
      if (visual != null) {
        _handleVisualIntegrityResult(visual);
      }

      final optimized = await _optimizedVision.runFrame(
        image: image,
        tasks: const <String>['object_reflection_shadow_detector'],
      );
      if (optimized != null && optimized.available) {
        _handleOptimizedVisionSmokeResult(optimized);
      }

      final liveness = _continuousLiveness.analyse(image);
      if (liveness != null) {
        _handleLivenessResult(liveness);
      }

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
      _visionBudget.recordWork(DateTime.now().difference(started));
      _analysingGazeFrame = false;
    }
  }

  void _handleOptimizedVisionSmokeResult(OptimizedVisionRuntimeResult result) {
    _lastVisualFrameAt = DateTime.now();
    final objects = (result.outputs['objects'] as List? ?? const <Object?>[])
        .whereType<Map>()
        .map((item) => Map<String, Object?>.from(item))
        .toList();
    final screenGlow = result.outputs['screen_glow'] == true;
    final mirrorReflection = result.outputs['mirror_reflection'] == true;
    final offscreenInteraction = result.outputs['offscreen_interaction'] == true;
    final maxConfidence = objects.fold<double>(
      0,
      (best, object) => math.max(
        best,
        double.tryParse(object['confidence']?.toString() ?? '') ?? 0,
      ),
    );
    final visualRiskScore =
        (maxConfidence +
                (screenGlow ? 0.18 : 0.0) +
                (mirrorReflection ? 0.18 : 0.0) +
                (offscreenInteraction ? 0.18 : 0.0))
            .clamp(0.0, 1.0);
    final detectedRisk = objects.isNotEmpty &&
        (screenGlow ||
            mirrorReflection ||
            offscreenInteraction ||
            maxConfidence >= 0.50);

    if (detectedRisk && visualRiskScore >= 0.58) {
      _visualRiskStreak++;
    } else {
      _visualRiskStreak = math.max(0, _visualRiskStreak - 1);
    }

    if (mounted) {
      setState(() {
        _visualReady = true;
        _visualStatus = detectedRisk
            ? '${objects.length} optimized vision object signal(s) ($_visualRiskStreak/3)'
            : '${result.backend} optimized vision active (${result.inferenceMs.toStringAsFixed(1)} ms)';
      });
    }

    if (_visualRiskStreak >= 3) {
      _visualRiskStreak = 0;
      unawaited(
        _raiseEvent(
          eventType: 'object_reflection_shadow_risk',
          severity: 'high',
          message:
              'Optimized vision detected a sustained object, reflection, screen-glow, or off-screen interaction risk.',
          metadata: result.toJson(),
        ),
      );
    } else if (detectedRisk && visualRiskScore >= 0.40) {
      unawaited(
        _raiseEvent(
          eventType: 'object_reflection_shadow_warning',
          severity: 'warning',
          message:
              'Optimized vision detected a possible object, reflection, screen-glow, or off-screen interaction signal.',
          metadata: result.toJson(),
        ),
      );
    } else {
      unawaited(
        _raiseEvent(
          eventType: 'optimized_vision_runtime_smoke',
          severity: 'info',
          message: 'Optimized vision runtime inference completed.',
          metadata: result.toJson(),
        ),
      );
    }
  }

  void _handleVisualIntegrityResult(VisualReflectionShadowResult result) {
    _lastVisualFrameAt = DateTime.now();
    if (result.visualRiskScore >= 0.58 ||
        result.screenGlowLikely ||
        result.mirrorOrGlassLikely ||
        result.offscreenInteractionLikely) {
      _visualRiskStreak++;
    } else {
      _visualRiskStreak = math.max(0, _visualRiskStreak - 1);
    }

    if (mounted) {
      setState(() {
        _visualReady = true;
        _visualStatus = result.visualRiskScore >= 0.58
            ? 'Possible reflection/shadow/object risk ($_visualRiskStreak/3)'
            : 'Reflection, shadow, and object integrity normal';
      });
    }

    if (_visualRiskStreak >= 3) {
      _visualRiskStreak = 0;
      unawaited(
        _raiseEvent(
          eventType: 'object_reflection_shadow_risk',
          severity: 'high',
          message:
              'Suspicious reflection, screen glow, shadow shift, or off-screen interaction pattern was detected.',
          metadata: result.toJson(),
        ),
      );
    } else if (result.visualRiskScore >= 0.40) {
      unawaited(
        _raiseEvent(
          eventType: 'object_reflection_shadow_warning',
          severity: 'warning',
          message:
              'Weak reflection, screen-glow, shadow, or lower-frame movement signal detected.',
          metadata: result.toJson(),
        ),
      );
    }
  }

  void _handleLivenessResult(ContinuousLivenessResult result) {
    _lastLivenessFrameAt = DateTime.now();
    if (result.spoofRiskScore >= 0.70 || result.replayOrFreezeLikely) {
      _spoofRiskStreak++;
    } else {
      _spoofRiskStreak = math.max(0, _spoofRiskStreak - 1);
    }

    if (mounted) {
      setState(() {
        _livenessReady = true;
        _livenessStatus = result.replayOrFreezeLikely
            ? 'Possible spoof/replay liveness risk ($_spoofRiskStreak/3)'
            : 'Continuous liveness present • anti-spoofing active';
      });
    }

    if (_spoofRiskStreak >= 3) {
      _spoofRiskStreak = 0;
      unawaited(
        _raiseEvent(
          eventType: 'continuous_liveness_spoof_risk',
          severity: 'high',
          message:
              'Continuous liveness anti-spoofing detected possible photo, screen, replay, or frozen-frame behaviour.',
          metadata: result.toJson(),
        ),
      );
    } else if (result.repeatedFrame || result.flatTexture) {
      unawaited(
        _raiseEvent(
          eventType: 'continuous_liveness_continuity_loss',
          severity: 'warning',
          message:
              'Continuous liveness signal weakened; possible frozen frame, flat image, or replay source.',
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
            ? 'Voice noticed (${_voiceRiskStreak + 1}/3)'
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
      final streamStillActive = _camera?.value.isStreamingImages ?? false;
      final platformOk =
          Platform.isWindows || Platform.isLinux || Platform.isMacOS;
      final gazeFresh = _lastGazeFrameAt != null &&
          DateTime.now().difference(_lastGazeFrameAt!).inSeconds <= 12;
      final livenessFresh = _lastLivenessFrameAt != null &&
          DateTime.now().difference(_lastLivenessFrameAt!).inSeconds <= 12;
      final visualFresh = _lastVisualFrameAt != null &&
          DateTime.now().difference(_lastVisualFrameAt!).inSeconds <= 12;
      final advancedStreamAvailable = _imageStreamAvailable && streamStillActive;

      setState(() {
        _secondsLive += 5;
        _cameraReady = cameraStillReady;
        _systemReady = platformOk;
        _systemStatus = platformOk
            ? 'System monitoring active'
            : 'Unsupported system environment';
        if (cameraStillReady && advancedStreamAvailable) {
          _gazeReady = gazeFresh;
          _livenessReady = livenessFresh;
          _visualReady = visualFresh;
          if (!_gazeReady) {
            _gazeStatus = 'Gaze/head pose analysis waiting for frames';
          }
          if (!_livenessReady) {
            _livenessStatus = 'Liveness analysis waiting for frames';
          }
          if (!_visualReady) {
            _visualStatus = 'Reflection/object scan waiting for frames';
          }
        } else if (cameraStillReady) {
          _gazeReady = true;
          _livenessReady = true;
          _visualReady = true;
          if (!(_gazeStatus.contains('Snapshot') ||
              _gazeStatus.contains('head/gaze') ||
              _gazeStatus.contains('movement'))) {
            _gazeStatus = '1-second snapshot gaze/head check active';
          }
          _livenessStatus = 'Presence check active';
          _visualStatus = 'Short camera checks active';
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
      if (cameraStillReady && advancedStreamAvailable && !gazeFresh) {
        await _raiseEvent(
          eventType: 'gaze_head_pose_monitor_unavailable',
          severity: 'info',
          message: 'Gaze and head pose analysis is waiting for camera frames.',
        );
      }
      if (cameraStillReady && advancedStreamAvailable && !livenessFresh) {
        await _raiseEvent(
          eventType: 'continuous_liveness_monitor_unavailable',
          severity: 'info',
          message: 'Continuous liveness analysis is waiting for camera frames.',
        );
      }
      if (cameraStillReady && advancedStreamAvailable && !visualFresh) {
        await _raiseEvent(
          eventType: 'object_reflection_shadow_monitor_unavailable',
          severity: 'info',
          message:
              'Reflection, shadow, and object analysis is waiting for camera frames.',
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
    final limited = label.contains('limited on this device') ||
        label.contains('waiting for frames');
    final color = ready
        ? const Color(0xFF16A34A)
        : limited
            ? const Color(0xFFF59E0B)
            : const Color(0xFFDC2626);
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

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
import 'vision_compute_budget_service.dart';
import 'visual_reflection_shadow_service.dart';

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
  static const int _secondPersonWarningStreak = 3;
  static const int _secondPersonPauseStreak = 7;
  static const int _farVoiceWarningStreak = 3;
  static const int _deviceRecoverySeconds = 30;
  static const int _deviceRetryEverySeconds = 5;
  static const int _lowLightWarningStreak = 3;

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
  Timer? _cameraRecoveryTimer;
  Timer? _microphoneRecoveryTimer;

  final Map<String, DateTime> _lastEventAt = <String, DateTime>{};
  final List<String> _eventsSent = <String>[];

  String _cameraStatus = 'Opening camera...';
  String _audioStatus = 'Starting sound monitor...';
  String _systemStatus = 'Checking system...';
  String _gazeStatus = 'Starting 1-second gaze/head check...';
  String _livenessStatus = 'Starting presence check...';
  String _visualStatus = 'Starting camera view check...';
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
  ResolutionPreset _cameraResolution = ResolutionPreset.low;
  bool _cameraQualityUpgraded = false;
  int _cameraRecoveryRemaining = 0;
  int _microphoneRecoveryRemaining = 0;
  int _lowLightStreak = 0;
  int _secondsLive = 0;
  int _gazeRiskStreak = 0;
  int _voiceRiskStreak = 0;
  int _farVoiceRiskStreak = 0;
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
    _cameraRecoveryTimer?.cancel();
    _microphoneRecoveryTimer?.cancel();
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
      _visualStatus = 'Starting camera view check...';
    });
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        _beginCameraRecovery(
          'Camera was not found. Please connect or enable your camera.',
        );
        return;
      }
      final selected = cameras.firstWhere(
        (item) => item.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );
      final previousCamera = _camera;
      if (previousCamera != null) {
        try {
          if (previousCamera.value.isStreamingImages) {
            await previousCamera.stopImageStream();
          }
        } catch (_) {}
        await previousCamera.dispose();
        if (mounted && identical(_camera, previousCamera)) {
          _camera = null;
        }
      }
      final controller = CameraController(
        selected,
        _cameraResolution,
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
        _cameraStatus =
            'Camera check active (${_cameraResolution == ResolutionPreset.medium ? 'improved' : 'standard'} quality)';
        if (streamReady) {
          _snapshotFallbackTimer?.cancel();
          _gazeStatus = 'Gaze vector and head pose monitoring active';
          _livenessStatus = 'Continuous liveness check active';
          _visualStatus = 'Camera view check active';
        } else {
          _gazeStatus = '1-second snapshot gaze/head check active';
          _livenessStatus = 'Snapshot presence check active';
          _visualStatus = 'Snapshot camera view check active';
        }
      });
      _clearCameraRecovery();
      if (!streamReady) {
        _startSnapshotCameraChecks(controller);
      }
    } catch (e) {
      _beginCameraRecovery(
        'Camera connection is unstable. Please keep your face visible while it reconnects.',
        metadata: <String, Object?>{'error': e.toString()},
      );
    }
  }

  void _beginCameraRecovery(
    String message, {
    Map<String, Object?> metadata = const <String, Object?>{},
  }) {
    if (!mounted) return;

    if (_cameraRecoveryRemaining <= 0) {
      _cameraRecoveryRemaining = _deviceRecoverySeconds;
      _cameraRecoveryTimer?.cancel();
      _cameraRecoveryTimer = Timer.periodic(const Duration(seconds: 1), (
        timer,
      ) {
        if (!mounted) return;

        _cameraRecoveryRemaining--;

        if (_cameraRecoveryRemaining > 0 &&
            _cameraRecoveryRemaining % _deviceRetryEverySeconds == 0) {
          unawaited(_startCamera());
        }

        if (_cameraRecoveryRemaining <= 0) {
          timer.cancel();
          unawaited(
            _raiseEvent(
              eventType: 'camera_reconnect_timeout',
              severity: 'critical',
              message:
                  'Camera connection could not be restored. An invigilator may review this session.',
              metadata: metadata,
            ),
          );
        }

        if (mounted) {
          setState(() {
            _cameraStatus =
                '$message Reconnecting in $_cameraRecoveryRemaining seconds.';
          });
        }
      });
    }

    setState(() {
      _openingCamera = false;
      _cameraReady = false;
      _gazeReady = false;
      _livenessReady = false;
      _visualReady = false;
      _imageStreamAvailable = false;
      _cameraStatus = '$message Reconnecting in $_cameraRecoveryRemaining seconds.';
    });
  }

  void _clearCameraRecovery() {
    _cameraRecoveryTimer?.cancel();
    _cameraRecoveryTimer = null;
    _cameraRecoveryRemaining = 0;
  }

  void _beginMicrophoneRecovery(
    String message, {
    Map<String, Object?> metadata = const <String, Object?>{},
  }) {
    if (!mounted) return;

    if (_microphoneRecoveryRemaining <= 0) {
      _microphoneRecoveryRemaining = _deviceRecoverySeconds;
      _microphoneRecoveryTimer?.cancel();
      _microphoneRecoveryTimer = Timer.periodic(const Duration(seconds: 1), (
        timer,
      ) {
        if (!mounted) return;

        _microphoneRecoveryRemaining--;

        if (_microphoneRecoveryRemaining > 0 &&
            _microphoneRecoveryRemaining % _deviceRetryEverySeconds == 0) {
          unawaited(_startAudio());
        }

        if (_microphoneRecoveryRemaining <= 0) {
          timer.cancel();
          unawaited(
            _raiseEvent(
              eventType: 'microphone_reconnect_timeout',
              severity: 'critical',
              message:
                  'Room sound check could not be restored. An invigilator may review this session.',
              metadata: metadata,
            ),
          );
        }

        if (mounted) {
          setState(() {
            _audioStatus =
                '$message Reconnecting in $_microphoneRecoveryRemaining seconds.';
          });
        }
      });
    }

    setState(() {
      _audioReady = false;
      _audioStatus =
          '$message Reconnecting in $_microphoneRecoveryRemaining seconds.';
    });
  }

  void _clearMicrophoneRecovery() {
    _microphoneRecoveryTimer?.cancel();
    _microphoneRecoveryTimer = null;
    _microphoneRecoveryRemaining = 0;
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
                ? 'Camera view needs review ($_multiplePeopleRiskStreak/$_secondPersonPauseStreak)'
                : 'Snapshot camera view check clear';
            _livenessStatus = 'Snapshot presence check active';
          });
        }

        if (_multiplePeopleRiskStreak == _secondPersonWarningStreak) {
          unawaited(
            _raiseEvent(
              eventType: 'camera_view_needs_review',
              severity: 'warning',
              message: 'Camera view may need review.',
              metadata: result.toJson(),
            ),
          );
        }

        if (_multiplePeopleRiskStreak >= _secondPersonPauseStreak) {
          _multiplePeopleRiskStreak = 0;
          unawaited(
            _raiseEvent(
              eventType: 'multiple_people_detected',
              severity: 'high',
              message: 'Camera view requires immediate review.',
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
            _visualStatus = 'Snapshot camera view check waiting';
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

  void _handleFrameQuality(CameraImage image) {
    if (image.planes.isEmpty) return;
    final plane = image.planes.first;
    final bytes = plane.bytes;
    if (bytes.isEmpty) return;

    final step = math.max(1, bytes.length ~/ 4096);
    var count = 0;
    var sum = 0.0;
    var squares = 0.0;

    for (var i = 0; i < bytes.length; i += step) {
      final value = bytes[i].toDouble();
      count++;
      sum += value;
      squares += value * value;
    }

    if (count == 0) return;

    final mean = sum / count;
    final variance = math.max(0.0, (squares / count) - (mean * mean));
    final brightness = (mean / 255.0).clamp(0.0, 1.0);
    final contrast = (math.sqrt(variance) / 255.0).clamp(0.0, 1.0);
    final lowLight = brightness < 0.18 ||
        (brightness < 0.24 && contrast < 0.09);

    if (lowLight) {
      _lowLightStreak++;
    } else {
      _lowLightStreak = math.max(0, _lowLightStreak - 1);
    }

    if (_lowLightStreak >= _lowLightWarningStreak) {
      if (mounted && _multiplePeopleRiskStreak == 0) {
        setState(() {
          _visualStatus = 'Lighting is low. Please improve your lighting.';
        });
      }

      unawaited(
        _raiseEvent(
          eventType: 'low_light_guidance',
          severity: 'warning',
          message: 'Lighting is low. Please improve your lighting.',
          metadata: <String, Object?>{
            'brightness': brightness,
            'contrast': contrast,
            'camera_resolution': _cameraResolution.name,
          },
        ),
      );

      if (!_cameraQualityUpgraded &&
          _cameraResolution == ResolutionPreset.low) {
        _cameraQualityUpgraded = true;
        _cameraResolution = ResolutionPreset.medium;
        if (mounted) {
          setState(() {
            _cameraStatus = 'Improving camera quality for better fairness...';
          });
        }
        unawaited(_startCamera());
      }
    }
  }

  Future<void> _analyseCameraImage(CameraImage image, DateTime started) async {
    try {
      _handleFrameQuality(image);

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
    final confidentPersonObjects = objects.where((object) {
      final label = '${object['label'] ?? object['class'] ?? object['name'] ?? ''}'.toLowerCase();
      final confidence = double.tryParse('${object['confidence'] ?? 0}') ?? 0.0;
      return (label.contains('person') || label.contains('human') || label.contains('face')) &&
          confidence >= 0.66;
    }).toList();
    final nativePersonCount = int.tryParse('${result.outputs['person_count'] ?? ''}') ?? 0;
    final nativeMultiplePeople = result.outputs['multiple_people_likely'] == true;
    final nativeOnlyMultiple = objects.isEmpty && nativeMultiplePeople && nativePersonCount >= 2;
    final multiplePeople = confidentPersonObjects.length >= 2 || nativeOnlyMultiple;
    if (multiplePeople) {
      _multiplePeopleRiskStreak++;
    } else {
      _multiplePeopleRiskStreak = math.max(0, _multiplePeopleRiskStreak - 1);
    }
    if (mounted) {
      setState(() {
        _visualReady = true;
        _visualStatus = multiplePeople
            ? 'Camera view needs review ($_multiplePeopleRiskStreak/$_secondPersonPauseStreak)'
            : 'Camera view check active (${result.inferenceMs.toStringAsFixed(1)} ms)';
      });
    }

    if (_multiplePeopleRiskStreak == _secondPersonWarningStreak) {
      unawaited(
        _raiseEvent(
          eventType: 'camera_view_needs_review',
          severity: 'warning',
          message: 'Camera view may need review.',
          metadata: result.toJson(),
        ),
      );
    }

    if (_multiplePeopleRiskStreak >= _secondPersonPauseStreak) {
      _multiplePeopleRiskStreak = 0;
      unawaited(
        _raiseEvent(
          eventType: 'multiple_people_detected',
          severity: 'high',
          message: 'Camera view requires immediate review.',
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
          message: 'Camera view object/reflection check needs immediate review.',
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
          message: 'Presence check needs immediate review.',
          metadata: result.toJson(),
        ),
      );
    }
  }

  Future<void> _startAudio() async {
    try {
      final permission = await _microphone.hasPermission();
      if (!permission) {
        _beginMicrophoneRecovery(
          'Room sound check is reconnecting. Please keep your exam area quiet.',
          metadata: const <String, Object?>{'reason': 'permission_unavailable'},
        );
        return;
      }
      await _microphone.start(
        sampleRate: 44100,
        maxBufferSeconds: 20,
        onPcmChunk: _handleAudioChunk,
      );
      _clearMicrophoneRecovery();
      if (!mounted) return;
      setState(() {
        _audioReady = true;
        _audioStatus = 'Sound check active';
      });
    } catch (e) {
      _beginMicrophoneRecovery(
        'Room sound check is reconnecting. Please keep your exam area quiet.',
        metadata: <String, Object?>{'error': e.toString()},
      );
    }
  }

  void _handleAudioChunk(Uint8List chunk) {
    final result = _audioIsolation.analysePcm16(chunk);
    if (result == null) return;

    if (result.nearVoiceLikely) {
      _voiceRiskStreak++;
      _farVoiceRiskStreak = math.max(0, _farVoiceRiskStreak - 1);
    } else if (result.possibleFarVoiceLikely) {
      _farVoiceRiskStreak++;
      _voiceRiskStreak = math.max(0, _voiceRiskStreak - 1);
    } else {
      _voiceRiskStreak = math.max(0, _voiceRiskStreak - 1);
      _farVoiceRiskStreak = math.max(0, _farVoiceRiskStreak - 1);
    }

    if (mounted) {
      setState(() {
        _audioStatus = result.nearVoiceLikely
            ? 'Voice close to exam area ($_voiceRiskStreak/3)'
            : result.possibleFarVoiceLikely
            ? 'Voice may be outside or far away. Improve environment ($_farVoiceRiskStreak/$_farVoiceWarningStreak)'
                : result.allowedAmbientLikely
                    ? 'Allowed ambient sound: ${result.label}'
                    : 'Unclear environment sound noticed';
      });
    }

    if (_voiceRiskStreak >= 3) {
      _voiceRiskStreak = 0;
      unawaited(
        _raiseEvent(
          eventType: 'audio_voice_isolation_alert',
          severity: 'high',
          message: 'Voice was noticed close to the exam audio environment.',
          metadata: result.toJson(),
        ),
      );
    } else if (_farVoiceRiskStreak == _farVoiceWarningStreak) {
      unawaited(
        _raiseEvent(
          eventType: 'background_voice_environment_warning',
          severity: 'warning',
          message: 'Voice may be coming from outside or far away. Please improve your environment.',
          metadata: result.toJson(),
        ),
      );
    } else if (result.repeatedFingerprint &&
        !result.allowedAmbientLikely &&
        !result.possibleFarVoiceLikely) {
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
        _beginCameraRecovery(
          'Camera connection is unstable. Please keep your face visible while it reconnects.',
        );
      }
      if (!_microphone.isRunning) {
        _beginMicrophoneRecovery(
          'Room sound check is reconnecting. Please keep your exam area quiet.',
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

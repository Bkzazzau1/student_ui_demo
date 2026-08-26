import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'demo_face_id_service.dart';
import 'face_embedding_pipeline.dart';
import 'face_identity_enrollment_api.dart';
import 'face_identity_enrollment_gate.dart';
import 'face_identity_landmark_matrix.dart';
import 'face_identity_liveness_gate.dart';
import 'face_identity_quality.dart';
import 'face_identity_verification_service.dart';
import 'face_live_capture_engine.dart';
import 'native_face_embedding_runtime.dart';
import 'windows_speech_prompt_service.dart';
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

/// What the live capture engine currently sees, surfaced to the guide-oval
/// UI so it reacts to the camera stream in real time (idle=no face found,
/// adjusting=face found but not matching the requested pose/quality yet,
/// ready=about to auto-capture) instead of sitting static the whole time.
enum _LiveGuideState { idle, adjusting, ready }

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
      code: 'look_down',
      title: 'Look down',
      instruction: 'Lower your face slightly while keeping both eyes visible.',
      icon: Icons.keyboard_arrow_down,
    ),
    _IdentityGuide(
      code: 'look_up',
      title: 'Look up',
      instruction: 'Raise your face slightly upward without leaving the guide.',
      icon: Icons.keyboard_arrow_up,
    ),
    _IdentityGuide(
      code: 'smile',
      title: 'Smile',
      instruction: 'Smile naturally while keeping your face inside the guide.',
      icon: Icons.sentiment_very_satisfied_outlined,
    ),
    _IdentityGuide(
      code: 'open_mouth',
      title: 'Open your mouth',
      instruction: 'Open your mouth naturally while facing the camera.',
      icon: Icons.record_voice_over_outlined,
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
  final WindowsSpeechPromptService _speech = WindowsSpeechPromptService();
  final FaceIdentityEnrollmentGate _enrollmentGate =
      const FaceIdentityEnrollmentGate();
  final FaceIdentityVerificationService _verificationService =
      const FaceIdentityVerificationService();
  final FaceIdentityLivenessGate _livenessGate = FaceIdentityLivenessGate();
  final FaceLiveCaptureEngine _liveCaptureEngine = FaceLiveCaptureEngine();
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
  bool _leavingPage = false;
  int _enrollmentGeneration = 0;
  String? _cameraError;
  String? _statusMessage;
  FaceEmbeddingPipelineResult? _neutralBaseline;
  String? _lastSpokenGuide;

  _IdentityGuide get _currentGuide =>
      _guides[math.min(_snapshot.capturedSamples, _guides.length - 1)];

  @override
  void initState() {
    super.initState();
    _snapshot = _service.load();
    unawaited(_speech.initialize());
    unawaited(_embeddingPipeline.initialize());
    unawaited(_initializeEnrollment());
  }

  Future<void> _initializeEnrollment() async {
    final migrated = await _service.migrateUntrustedDraft();
    if (!mounted) return;
    setState(() => _snapshot = migrated);
    // `_syncSavedFaceId` is the single authority for deciding whether this
    // student needs guided enrollment or should confirm an identity that
    // already exists. It must run before any camera is opened for capture,
    // otherwise a stale "not yet backend-locked" snapshot can start a new
    // enrollment even though a valid protected template already exists on
    // this device.
    await _syncSavedFaceId();
  }

  @override
  void dispose() {
    unawaited(_liveCaptureEngine.stop());
    _controller?.dispose();
    _speech.dispose();
    _identityApi.dispose();
    super.dispose();
  }

  Future<void> _releaseCameraAndSpeech() async {
    await _liveCaptureEngine.stop();
    final controller = _controller;
    if (mounted && controller != null) {
      setState(() => _controller = null);
      await WidgetsBinding.instance.endOfFrame;
    }
    await _speech.dispose();
    try {
      await controller?.dispose();
    } catch (_) {
      // The camera may already have been released by the Windows plugin.
    }
  }

  Future<void> _returnToPreviousPage({required bool approved}) async {
    if (_leavingPage || !mounted) return;
    _leavingPage = true;
    _autoCaptureRunning = false;
    await _releaseCameraAndSpeech();
    if (!mounted) return;
    if (approved) widget.onComplete?.call();
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop(approved);
    } else {
      setState(() {
        _leavingPage = false;
        _statusMessage =
            'Return navigation is unavailable. Use the portal navigation menu.';
      });
    }
  }

  Future<void> _speakGuide(_IdentityGuide guide, {bool retry = false}) async {
    final key = '${guide.code}:$retry';
    if (!retry && _lastSpokenGuide == key) return;
    _lastSpokenGuide = key;
    final prompt = switch (guide.code) {
      'front_face' => 'Look straight',
      'left_angle' => 'Turn left',
      'right_angle' => 'Turn right',
      'look_down' => 'Look down',
      'smile' => 'Smile',
      'look_up' => 'Look up',
      'open_mouth' => 'Open your mouth',
      _ => guide.title,
    };
    unawaited(_speech.speak(retry ? '$prompt, please' : prompt));
  }

  Future<void> _syncSavedFaceId() async {
    if (_syncing) return;
    final generation = _enrollmentGeneration;
    setState(() {
      _syncing = true;
      _statusMessage = 'Checking your saved Face ID...';
    });
    try {
      final protectedTemplate = await NativeFaceEmbeddingRuntime()
          .loadProtectedTemplate(studentId: _snapshot.studentId);
      if (!mounted || generation != _enrollmentGeneration) return;
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
          return;
        }
      }
      final latest = await _identityApi.fetchLatest(
        studentId: DemoFaceIdService.studentId,
      );
      if (!mounted || generation != _enrollmentGeneration) return;
      if (latest != null && latest.activeLocked) {
        final synced = await _service.applyBackendEnrollment(latest);
        setState(() {
          _snapshot = synced;
          _capturedImages.clear();
          _syncing = false;
          _openingCamera = false;
          _statusMessage = 'Face ID is active and protected on this device.';
        });
        await _returnToPreviousPage(approved: true);
        return;
      }
      if (!_enrollmentGate.requiresEnrollment(
        snapshot: _snapshot,
        hasValidLocalTemplate: false,
      )) {
        // The snapshot says this identity is locked, but no valid protected
        // template could be loaded on this device. This needs an explicit
        // device re-setup, not a silent new auto-capture session.
        setState(() {
          _syncing = false;
          _statusMessage =
              'Face ID is locked but no protected template was found on this '
              'device. Use "Test Face ID" to set it up again on this device.';
        });
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
      final canEnroll = _enrollmentGate.requiresEnrollment(
        snapshot: _snapshot,
        hasValidLocalTemplate: false,
      );
      setState(() {
        _syncing = false;
        _statusMessage = canEnroll
            ? 'We could not check your saved Face ID. Capture will continue '
                  'and save when connection is available.'
            : 'Face ID is locked but the saved status could not be checked. '
                  'Use "Test Face ID" once connectivity is restored.';
      });
      if (canEnroll) await _openCamera();
    }
  }

  Future<void> _openCamera({bool forVerification = false}) async {
    if (_snapshot.locked && !forVerification) return;
    if (_openingCamera || (_controller?.value.isInitialized ?? false)) return;
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
        // Apply the limit inside CameraX so Android never allocates and sends
        // thirty YUV frames per second just for Dart to discard most of them.
        // Five analyzed frames per second remains responsive for enrollment
        // and matches FaceLiveCaptureEngine's 200 ms sampling interval.
        fps: Platform.isWindows ? null : 5,
        imageFormatGroup: Platform.isWindows ? null : ImageFormatGroup.yuv420,
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

  // Consecutive live-stream frames that must all pass the quality/pose check
  // before the engine actually takes a photo. At the fast lane's effective
  // rate this is on the order of a couple hundred milliseconds, and it
  // exists purely to avoid triggering on one lucky frame mid-motion.
  static const int _liveCaptureStabilityFrames = 3;

  int _liveConsecutiveGoodFrames = 0;
  bool _liveCaptureTriggered = false;
  _LiveGuideState _liveGuideState = _LiveGuideState.idle;
  DateTime? _lastLiveGuidanceAt;

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
    final generation = _enrollmentGeneration;

    final guide = _currentGuide;
    setState(() {
      _statusMessage = '${guide.title}: ${guide.instruction} Hold steady...';
    });
    final liveStarted = await _startLiveCapture(generation);
    if (liveStarted) {
      await _speakGuide(guide);
      return;
    }
    await _runPolledAutomaticCapture(generation);
  }

  /// Live-stream capture path: analyzes the camera preview continuously and
  /// only takes an actual photo once several consecutive frames already
  /// look right, instead of blindly capturing on a fixed timer and checking
  /// quality afterward. Returns false when streaming isn't supported here
  /// (e.g. `camera_windows`), so the caller can fall back to polling.
  Future<bool> _startLiveCapture(int generation) async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return false;
    _liveConsecutiveGoodFrames = 0;
    _liveCaptureTriggered = false;
    if (_liveGuideState != _LiveGuideState.idle) {
      setState(() => _liveGuideState = _LiveGuideState.idle);
    }
    return _liveCaptureEngine.start(
      controller: controller,
      onFrame: (landmarks, grade) => _onLiveFrame(
        generation: generation,
        landmarks: landmarks,
        grade: grade,
      ),
    );
  }

  void _onLiveFrame({
    required int generation,
    required FaceLandmarkMatrix landmarks,
    required FaceIdentityQualityGrade grade,
  }) {
    if (!mounted ||
        generation != _enrollmentGeneration ||
        _snapshot.locked ||
        _submitting ||
        _capturing ||
        _liveCaptureTriggered) {
      return;
    }
    final matches =
        grade.accepted && _matchesGuideLive(_currentGuide, landmarks);
    final hasFace =
        landmarks.eyesVisible &&
        landmarks.noseVisible &&
        landmarks.mouthVisible;
    final nextState = matches
        ? _LiveGuideState.ready
        : hasFace
        ? _LiveGuideState.adjusting
        : _LiveGuideState.idle;
    if (!matches) {
      _liveConsecutiveGoodFrames = 0;
      final now = DateTime.now();
      final stateChanged = nextState != _liveGuideState;
      if (stateChanged ||
          _lastLiveGuidanceAt == null ||
          now.difference(_lastLiveGuidanceAt!) >=
              const Duration(milliseconds: 800)) {
        _lastLiveGuidanceAt = now;
        final message = grade.failureReasons.isNotEmpty
            ? grade.failureReasons.first
            : '${_currentGuide.title}: follow the direction and hold still.';
        setState(() {
          _statusMessage = message;
          _liveGuideState = nextState;
        });
      }
      return;
    }
    if (nextState != _liveGuideState) {
      setState(() => _liveGuideState = nextState);
    }
    _liveConsecutiveGoodFrames++;
    if (_liveConsecutiveGoodFrames < _liveCaptureStabilityFrames) return;
    _liveConsecutiveGoodFrames = 0;
    _liveCaptureTriggered = true;
    unawaited(_captureFromLiveStream(generation));
  }

  Future<void> _captureFromLiveStream(int generation) async {
    await _liveCaptureEngine.stop();
    try {
      if (!mounted ||
          generation != _enrollmentGeneration ||
          _snapshot.locked ||
          _submitting) {
        return;
      }
      await _captureSample();
      if (!mounted ||
          generation != _enrollmentGeneration ||
          _snapshot.locked ||
          _snapshot.isComplete ||
          _submitting) {
        return;
      }
      final guide = _currentGuide;
      setState(() {
        _statusMessage = '${guide.title}: ${guide.instruction} Hold steady...';
      });
      await _speakGuide(guide);
      final resumed = await _startLiveCapture(generation);
      if (!resumed) {
        await _runPolledAutomaticCapture(generation);
        return;
      }
    } finally {
      _liveCaptureTriggered = false;
      if (mounted &&
          (generation != _enrollmentGeneration ||
              _snapshot.locked ||
              _snapshot.isComplete)) {
        setState(() => _autoCaptureRunning = false);
      }
    }
  }

  /// Fallback capture loop for platforms the live stream doesn't support
  /// (Windows today, via `camera_windows`, which doesn't implement
  /// `startImageStream`). Unchanged from the original polling behavior.
  Future<void> _runPolledAutomaticCapture(int generation) async {
    if (_liveGuideState != _LiveGuideState.idle) {
      setState(() => _liveGuideState = _LiveGuideState.idle);
    }
    while (mounted &&
        generation == _enrollmentGeneration &&
        !_snapshot.locked &&
        _snapshot.capturedSamples < _snapshot.requiredSamples) {
      final guide = _currentGuide;
      setState(() {
        _statusMessage =
            '${guide.title}: ${guide.instruction} Capturing automatically...';
      });
      await _speakGuide(guide);
      await Future<void>.delayed(const Duration(milliseconds: 550));
      if (!mounted ||
          generation != _enrollmentGeneration ||
          _snapshot.locked ||
          _submitting) {
        break;
      }
      await _captureSample();
      await Future<void>.delayed(const Duration(milliseconds: 400));
    }
    if (mounted) {
      setState(() => _autoCaptureRunning = false);
    }
  }

  // Landmark-only pose/expression pre-check used by the live capture engine
  // to decide which frames are worth turning into an actual capture
  // attempt. This intentionally omits `_matchesGuide`'s SFace cosine-
  // similarity anti-swap check (computing an embedding on every live frame
  // would defeat the point of a fast lane): that check still runs, exactly
  // as before, on the captured photo inside `_captureSample`.
  bool _matchesGuideLive(_IdentityGuide guide, FaceLandmarkMatrix landmarks) {
    if (!landmarks.isGeometryUsable) return false;
    if (guide.code == 'front_face') {
      return landmarks.yaw.abs() <= 0.20 && landmarks.eyeOpenness >= 0.028;
    }
    final baseline = _neutralBaseline;
    if (baseline == null) return false;
    return switch (guide.code) {
      'left_angle' => landmarks.yaw - baseline.yaw >= 0.07,
      'right_angle' => landmarks.yaw - baseline.yaw <= -0.07,
      'look_down' => landmarks.pitch - baseline.pitch >= 0.04,
      'look_up' => landmarks.pitch - baseline.pitch <= -0.04,
      'smile' => landmarks.smileWidth - baseline.smileWidth >= 0.04,
      'open_mouth' =>
        landmarks.mouthOpenness >= 0.04 &&
            landmarks.mouthOpenness >= baseline.mouthOpenness * 1.4,
      _ => false,
    };
  }

  Future<void> _captureSample() async {
    if (_snapshot.locked || _capturing || _snapshot.isComplete || _submitting) {
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
          _statusMessage = _embeddingPipeline.lastFailureReason.isEmpty
              ? 'No reliable face was detected. Keep your full face inside the guide.'
              : _embeddingPipeline.lastFailureReason;
        });
        // Without this, the voice guide speaks each instruction only once
        // per step (see `_speakGuide`'s dedup guard) and then falls silent
        // on every subsequent failed attempt, which reads as "the voice
        // guide stopped working" during a long retry stretch.
        await _speakGuide(guide, retry: true);
        return;
      }
      if (!_matchesGuide(guide, embeddingResult)) {
        if (!mounted) return;
        setState(() {
          _capturing = false;
          _statusMessage =
              '${guide.title} was not detected yet. Follow the arrow and hold the pose.';
        });
        await _speakGuide(guide, retry: true);
        return;
      }
      if (guide.code == 'front_face') {
        _neutralBaseline = embeddingResult;
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
    unawaited(_speech.speak('Good'));
    if (next.capturedSamples >= next.requiredSamples) {
      await _submitIdentityGallery();
    }
  }

  // These deltas intentionally accept a natural, moderate pose change
  // rather than requiring an exaggerated turn: requiring a bigger delta
  // just means more failed attempts (and a longer wait) before a normal
  // "turn slightly left/right" pose happens to clear the bar.
  bool _matchesGuide(_IdentityGuide guide, FaceEmbeddingPipelineResult sample) {
    if (guide.code == 'front_face') {
      return sample.yaw.abs() <= 0.20 && sample.eyeOpenness >= 0.028;
    }
    final baseline = _neutralBaseline;
    if (baseline == null) return false;
    // Every enrollment pose must remain strongly tied to the first frontal
    // face. This prevents another person from replacing the enrollee midway
    // through the seven-step capture.
    if (_cosineSimilarity(baseline.embedding, sample.embedding) < 0.50) {
      return false;
    }
    return switch (guide.code) {
      'left_angle' => sample.yaw - baseline.yaw >= 0.07,
      'right_angle' => sample.yaw - baseline.yaw <= -0.07,
      'look_down' => sample.pitch - baseline.pitch >= 0.04,
      'look_up' => sample.pitch - baseline.pitch <= -0.04,
      'smile' => sample.smileWidth - baseline.smileWidth >= 0.04,
      'open_mouth' =>
        sample.mouthOpenness >= 0.04 &&
            sample.mouthOpenness >= baseline.mouthOpenness * 1.4,
      _ => false,
    };
  }

  double _cosineSimilarity(List<double> first, List<double> second) {
    if (first.length != second.length || first.isEmpty) return -1;
    var dot = 0.0;
    var firstNorm = 0.0;
    var secondNorm = 0.0;
    for (var index = 0; index < first.length; index++) {
      dot += first[index] * second[index];
      firstNorm += first[index] * first[index];
      secondNorm += second[index] * second[index];
    }
    if (firstNorm <= 0 || secondNorm <= 0) return -1;
    return dot / (math.sqrt(firstNorm) * math.sqrt(secondNorm));
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
      final averageQuality =
          _capturedImages
              .map((image) => image.qualityScore)
              .reduce((a, b) => a + b) /
          _capturedImages.length;
      // Development-only: there is no backend to approve this enrollment
      // yet, so a successfully protected local template is treated as
      // approved and locked immediately. This is what makes "enroll once,
      // then always confirm" hold true even fully offline; it is not the
      // institution's approval policy.
      final approved = await _service.approveLocalDevelopmentEnrollment(
        enrollmentId: localEnrollmentId,
        qualityScore: averageQuality,
      );
      if (!mounted) return;
      setState(() {
        _snapshot = approved;
        _submitting = false;
        _statusMessage =
            'Enrollment is protected and locked locally for development '
            'testing. Test it now with a new live camera capture; backend '
            'synchronization will follow when available.';
      });
      await _finishEnrollmentWithoutTest();
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
    await _verifyFreshIdentitySample();
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
      _statusMessage = 'Get ready to confirm liveness...';
    });
    try {
      // 1:1 verification only: YOLO person gate + face landmark matrix +
      // quality grade run inside the pipeline below; liveness runs a short
      // randomized-challenge burst before the sample is even considered.
      final liveness = await _livenessGate.runBurst(
        controller: controller,
        onChallengeStarted: (session) {
          if (!mounted) return;
          setState(() => _statusMessage = session.instruction);
          unawaited(_speech.speak(session.instruction));
        },
      );
      if (!mounted) return;
      if (liveness.state != 'live_challenge_passed') {
        setState(() {
          _verificationRunning = false;
          _statusMessage =
              'Liveness could not be confirmed: ${liveness.reason}';
        });
        return;
      }
      final aiAvailable = await _embeddingPipeline.initialize();
      setState(
        () => _statusMessage =
            'Look straight at the camera. Capturing a fresh identity sample...',
      );
      final file = await controller.takePicture();
      final sample = aiAvailable
          ? await _embeddingPipeline.processEncodedImage(
              await File(file.path).readAsBytes(),
            )
          : null;
      final outcome = _verificationService.evaluateSample(
        aiAvailable: aiAvailable,
        sample: sample,
        pipelineFailureReason: _embeddingPipeline.lastFailureReason,
        templateJson: _portableTemplateJson!,
        liveness: liveness,
      );
      if (!mounted) return;
      setState(() {
        _verificationRunning = false;
        _statusMessage = switch (outcome.state) {
          FaceIdentityCheckState.verified =>
            'Face ID test passed. Similarity ${(outcome.similarity * 100).toStringAsFixed(1)}%.',
          FaceIdentityCheckState.mismatch =>
            'This sample did not verify. It is not a misconduct decision; try another live sample.',
          FaceIdentityCheckState.uncertain =>
            'The result was uncertain: ${outcome.reason}',
          FaceIdentityCheckState.aiUnavailable =>
            'Face identity AI is unavailable on this device. The test cannot run.',
          FaceIdentityCheckState.qualityRetry => outcome.reason,
          FaceIdentityCheckState.livenessFailed =>
            'Liveness could not be confirmed: ${outcome.reason}',
        };
      });
      if (outcome.verified) {
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

  Future<void> _finishEnrollmentWithoutTest() async {
    if (_testingExistingTemplate) {
      if (mounted) {
        setState(() {
          _testingExistingTemplate = false;
          _statusMessage = 'Face ID verified successfully.';
        });
        await _speech.speak('Face ID verified successfully.');
        await Future<void>.delayed(const Duration(seconds: 2));
      }
      if (!mounted) return;
      await _returnToPreviousPage(approved: true);
      return;
    }
    // The local development approval already locked this identity in
    // `_submitIdentityGallery`. Backend synchronization below is best-effort
    // metadata enrichment only: its failure or absence must never unlock or
    // reset the identity that is already active on this device.
    setState(() {
      _submitting = true;
      _statusMessage = 'Face ID is stored locally. Synchronizing enrollment...';
    });
    try {
      final enrollment = await _identityApi.submit(
        studentId: _snapshot.studentId,
        images: List<FaceIdentityEnrollmentImage>.from(_capturedImages),
      );
      if (enrollment.activeLocked) {
        await _buildAndProtectTemplate(enrollment.enrollmentId);
        final synced = await _service.applyBackendEnrollment(enrollment);
        if (!mounted) return;
        setState(() {
          _snapshot = synced;
          _submitting = false;
          _statusMessage = 'Face ID enrollment is stored and active.';
        });
      } else {
        if (!mounted) return;
        setState(() {
          _submitting = false;
          _statusMessage =
              'Face ID is protected and locked on this device for '
              'development testing. Backend approval is still pending.';
        });
      }
      await Future<void>.delayed(const Duration(seconds: 2));
      if (!mounted) return;
      await _returnToPreviousPage(approved: true);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _statusMessage =
            'Face ID is protected on this device and the test is complete. '
            'Backend synchronization is pending.';
      });
      await Future<void>.delayed(const Duration(seconds: 2));
      if (!mounted) return;
      await _returnToPreviousPage(approved: true);
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
    _enrollmentGeneration++;
    final draft = await _service.beginDeviceEnrollment();
    if (!mounted) return;
    setState(() {
      _snapshot = draft;
      _capturedImages.clear();
      _capturedEmbeddings.clear();
      _portableTemplateJson = null;
      _neutralBaseline = null;
      _lastSpokenGuide = null;
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
      _neutralBaseline = null;
      _lastSpokenGuide = null;
      _testingExistingTemplate = false;
      _autoCaptureStarted = false;
      _autoCaptureRunning = false;
      _statusMessage = 'Local draft cleared. Automatic capture will restart.';
    });
    await _openCamera();
  }

  Future<void> _clearEnrollment() async {
    if (!kDebugMode) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.delete_outline, color: Colors.red),
        title: const Text('Clear Face ID enrollment?'),
        content: const Text(
          'This development action removes the protected Face ID template and '
          'local enrollment state from this device. You must complete all live '
          'face challenges again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Clear and re-enroll'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    _enrollmentGeneration++;
    await _speech.stop();
    await _controller?.dispose();
    final protectedCleared = await NativeFaceEmbeddingRuntime()
        .clearProtectedTemplate(studentId: _snapshot.studentId);
    final next = await _service.beginDeviceEnrollment();
    if (!mounted) return;
    setState(() {
      _snapshot = next;
      _controller = null;
      _capturedImages.clear();
      _capturedEmbeddings.clear();
      _portableTemplateJson = null;
      _neutralBaseline = null;
      _lastSpokenGuide = null;
      _testingExistingTemplate = false;
      _autoCaptureStarted = false;
      _autoCaptureRunning = false;
      _statusMessage = protectedCleared
          ? 'Face ID cleared. Starting a completely new guided enrollment.'
          : 'Local enrollment cleared, but protected template removal needs review.';
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
        automaticallyImplyLeading: false,
        leading: IconButton(
          tooltip: 'Back to previous page',
          onPressed: _leavingPage
              ? null
              : () => _returnToPreviousPage(approved: false),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: const Text('Face ID setup'),
        actions: [
          // Students must never get a normal "change my identity" control.
          // This exists only to let developers repeatedly test enrollment
          // locally, so it is compiled out of release builds entirely.
          if (kDebugMode)
            TextButton.icon(
              onPressed: _submitting || _capturing ? null : _clearEnrollment,
              icon: const Icon(Icons.restart_alt_rounded),
              label: const Text('Reset local test identity'),
            ),
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
      body: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop && !_leavingPage) {
            _returnToPreviousPage(approved: false);
          }
        },
        child: SafeArea(
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
                          statusMessage: _statusMessage,
                          liveGuideState: _liveGuideState,
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
                        capturing:
                            _capturing || _syncing || _autoCaptureRunning,
                        submitting: _submitting,
                        onCapture: _startAutomaticCapture,
                        onReset: _reset,
                        onBack: () => _returnToPreviousPage(
                          approved: _snapshot.isComplete,
                        ),
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
                            onPressed: () =>
                                _returnToPreviousPage(approved: true),
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
      ),
    );
  }
}

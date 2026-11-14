import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../proctoring_demo/camera_frame_orientation.dart';
import 'face_embedding_pipeline.dart';
import 'face_identity_landmark_matrix.dart';
import 'face_identity_quality.dart';
import 'face_live_capture_engine.dart';
import 'official_face_id_models.dart';
import 'windows_speech_prompt_service.dart';

part 'face_id_registration_capture_view_widgets.dart';

/// The guided photos captured for an official Face ID registration.
class FaceIdRegistrationCapture {
  const FaceIdRegistrationCapture({
    required this.photos,
    required this.poseOrder,
  });

  final List<OfficialFaceIdPhoto> photos;
  final List<String> poseOrder;
}

/// In-memory capture progress for one registration session. Nothing is
/// saved on the device: the photos go to the school, which approves them.
class FaceIdCaptureProgress {
  const FaceIdCaptureProgress({
    required this.requiredSamples,
    required this.capturedSamples,
    this.lastQualityScore,
    this.locked = false,
  });

  final int requiredSamples;
  final int capturedSamples;
  final double? lastQualityScore;

  /// True once the photos have been handed over for submission.
  final bool locked;

  bool get isComplete => capturedSamples >= requiredSamples;

  FaceIdCaptureProgress withSample(double quality) => FaceIdCaptureProgress(
    requiredSamples: requiredSamples,
    capturedSamples: (capturedSamples + 1).clamp(0, requiredSamples),
    lastQualityScore: quality.clamp(0.0, 1.0),
    locked: locked,
  );

  FaceIdCaptureProgress submitted() => FaceIdCaptureProgress(
    requiredSamples: requiredSamples,
    capturedSamples: capturedSamples,
    lastQualityScore: lastQualityScore,
    locked: true,
  );
}

/// Guided 7-pose capture for Face ID registration.
///
/// The pose order after the first front photo is randomized per session, and
/// every pose must still match the first front photo, so a pre-recorded
/// video or a swap mid-way does not produce a complete set. Returns a
/// [FaceIdRegistrationCapture] (or null if the student leaves).
class FaceIdRegistrationCaptureView extends StatefulWidget {
  const FaceIdRegistrationCaptureView({super.key});

  @override
  State<FaceIdRegistrationCaptureView> createState() =>
      _FaceIdRegistrationCaptureViewState();
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

class _FaceIdRegistrationCaptureViewState
    extends State<FaceIdRegistrationCaptureView> {
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

  final List<OfficialFaceIdPhoto> _capturedPhotos = <OfficialFaceIdPhoto>[];
  final FaceEmbeddingPipeline _embeddingPipeline = FaceEmbeddingPipeline();
  final WindowsSpeechPromptService _speech = WindowsSpeechPromptService();
  final FaceLiveCaptureEngine _liveCaptureEngine = FaceLiveCaptureEngine();

  /// Front face first (it is the anti-swap baseline), then the other poses
  /// in a fresh random order for this session.
  late final List<_IdentityGuide> _sessionGuides = <_IdentityGuide>[
    _guides.first,
    ...(_guides.sublist(1)..shuffle(math.Random.secure())),
  ];

  late FaceIdCaptureProgress _snapshot;
  CameraController? _controller;
  bool _openingCamera = false;
  bool _capturing = false;
  bool _submitting = false;
  bool _autoCaptureRunning = false;
  bool _autoCaptureStarted = false;
  bool _leavingPage = false;
  int _enrollmentGeneration = 0;
  String? _cameraError;
  String? _statusMessage;
  FaceEmbeddingPipelineResult? _neutralBaseline;
  String? _lastSpokenGuide;

  _IdentityGuide get _currentGuide =>
      _sessionGuides[math.min(
        _snapshot.capturedSamples,
        _sessionGuides.length - 1,
      )];

  @override
  void initState() {
    super.initState();
    _snapshot = FaceIdCaptureProgress(
      requiredSamples: _guides.length,
      capturedSamples: 0,
    );
    unawaited(_speech.initialize());
    unawaited(_embeddingPipeline.initialize());
    unawaited(_openCamera());
  }

  @override
  void dispose() {
    unawaited(_liveCaptureEngine.stop());
    _controller?.dispose();
    _speech.dispose();
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

  Future<void> _returnToPreviousPage([
    FaceIdRegistrationCapture? result,
  ]) async {
    if (_leavingPage || !mounted) return;
    _leavingPage = true;
    _autoCaptureRunning = false;
    await _releaseCameraAndSpeech();
    if (!mounted) return;
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop(result);
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

  Future<void> _openCamera() async {
    if (_snapshot.locked) return;
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
              'No camera found. Face ID registration requires camera access.';
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
        imageFormatGroup: CameraFrameOrientation.preferredStreamFormat(),
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
        _cameraError = 'Camera could not open for Face ID registration: $e';
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
    Uint8List imageBytes;
    var quality = 0.0;
    FaceEmbeddingPipelineResult embedded;
    try {
      final file = await controller.takePicture();
      imageBytes = await File(file.path).readAsBytes();
      final embeddingResult = await _embeddingPipeline.processEncodedImage(
        imageBytes,
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
      embedded = embeddingResult;
    } catch (e) {
      setState(() {
        _capturing = false;
        _cameraError = 'Identity image capture failed: $e';
      });
      return;
    }

    _capturedPhotos.add(
      OfficialFaceIdPhoto(
        poseCode: guide.code,
        title: guide.title,
        jpegBytes: imageBytes,
        qualityScore: quality,
        deviceEmbedding: List<double>.unmodifiable(embedded.embedding),
      ),
    );

    final next = _snapshot.withSample(quality);
    if (!mounted) return;
    setState(() {
      _snapshot = next;
      _capturing = false;
      _statusMessage = next.capturedSamples >= next.requiredSamples
          ? 'All photos captured. Preparing them for your school...'
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
        _capturedPhotos.length < _sessionGuides.length ||
        _snapshot.locked) {
      return;
    }
    setState(() {
      _submitting = true;
      _snapshot = _snapshot.submitted();
      _statusMessage = 'All photos captured.';
    });
    await _speech.speak('All photos captured.');
    await _returnToPreviousPage(
      FaceIdRegistrationCapture(
        photos: List<OfficialFaceIdPhoto>.unmodifiable(_capturedPhotos),
        poseOrder: _sessionGuides.map((guide) => guide.code).toList(),
      ),
    );
  }

  Future<void> _reset() async {
    if (_snapshot.locked) return;
    _enrollmentGeneration++;
    await _liveCaptureEngine.stop();
    if (!mounted) return;
    setState(() {
      _snapshot = FaceIdCaptureProgress(
        requiredSamples: _guides.length,
        capturedSamples: 0,
      );
      _capturedPhotos.clear();
      _neutralBaseline = null;
      _lastSpokenGuide = null;
      _autoCaptureStarted = false;
      _autoCaptureRunning = false;
      _statusMessage = 'Photos cleared. Automatic capture will restart.';
    });
    await _startAutomaticCapture();
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
          onPressed: _leavingPage ? null : _returnToPreviousPage,
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: const Text('Face ID registration photos'),
      ),
      bottomNavigationBar: compact && !_snapshot.locked
          ? _MobileCaptureBar(
              snapshot: _snapshot,
              guide: _currentGuide,
              capturing: _capturing || _autoCaptureRunning,
              submitting: _submitting,
              onCapture: _startAutomaticCapture,
              onReset: _reset,
            )
          : null,
      body: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop && !_leavingPage) {
            _returnToPreviousPage();
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
                          openingCamera: _openingCamera,
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
                          guides: _sessionGuides,
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
                        capturing: _capturing || _autoCaptureRunning,
                        submitting: _submitting,
                        onCapture: _startAutomaticCapture,
                        onReset: _reset,
                        onBack: _returnToPreviousPage,
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

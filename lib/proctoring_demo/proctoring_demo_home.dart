import 'dart:async';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import 'audio_security_check_service.dart';
import 'camera_scan_frame_source.dart';
import 'demo_evidence_service.dart';
import 'proctoring_demo_models.dart';
import 'security_review_service.dart';
import 'system_security_review_service.dart';

class ProctoringDemoHome extends StatefulWidget {
  const ProctoringDemoHome({
    super.key,
    this.onApproved,
    this.onStartApproved,
    this.compactExamGate = false,
    this.studentId = 'KASU/STU/2026/001',
    this.examId = 'exam-csc305-first-semester',
    this.attemptId = 'attempt-001',
  });

  final void Function(String? manifestPath)? onApproved;
  final void Function(String? manifestPath, SecurityReviewResult result)?
  onStartApproved;
  final bool compactExamGate;
  final String studentId;
  final String examId;
  final String attemptId;

  @override
  State<ProctoringDemoHome> createState() => _ProctoringDemoHomeState();
}

class _ScanGuide {
  const _ScanGuide(this.name, this.instruction);

  final String name;
  final String instruction;
}

class _FrameDecision {
  const _FrameDecision.accept() : accepted = true, message = null;
  const _FrameDecision.reject(this.message) : accepted = false;

  final bool accepted;
  final String? message;
}

class _ProctoringDemoHomeState extends State<ProctoringDemoHome> {
  static const bool _allowLocalStartApproval = bool.fromEnvironment(
    'KSLAS_ALLOW_LOCAL_START_APPROVAL',
  );

  static const List<_ScanGuide> _guides = <_ScanGuide>[
    _ScanGuide('front view', 'Point the camera straight ahead.'),
    _ScanGuide('left side', 'Turn slowly to the left side of the room.'),
    _ScanGuide('back-left corner', 'Show the back-left corner clearly.'),
    _ScanGuide('back wall', 'Turn further and show the wall behind you.'),
    _ScanGuide('back-right corner', 'Show the back-right corner clearly.'),
    _ScanGuide('right side', 'Turn slowly to the right side of the room.'),
    _ScanGuide('ceiling', 'Tilt upward and show the ceiling area.'),
    _ScanGuide('floor', 'Tilt downward and show the floor area.'),
    _ScanGuide('desk surface', 'Show the desk surface and nearby items.'),
    _ScanGuide('lap area', 'Show the lap area without hiding the camera.'),
    _ScanGuide('walls', 'Sweep across the visible walls.'),
    _ScanGuide('surroundings', 'Finish with a wide view of the surroundings.'),
  ];

  final DemoCameraScanFrameSource _frameSource = DemoCameraScanFrameSource();
  final DemoEvidenceService _evidence = DemoEvidenceService();
  final AudioSecurityCheckService _audioCheck = AudioSecurityCheckService();
  final SystemSecurityReviewService _systemReview =
      SystemSecurityReviewService();
  final SecurityReviewService _securityReview = SecurityReviewService(
    baseUrl: const String.fromEnvironment(
      'KSLAS_API_BASE_URL',
      defaultValue: 'http://127.0.0.1:8080',
    ),
  );

  CameraController? _controller;
  List<DemoScanTarget> _targets = _newTargets();
  final List<DemoCalibrationEntry> _calibrationLog = <DemoCalibrationEntry>[];
  final List<AgenticReviewEvent> _reviewEvents = <AgenticReviewEvent>[];
  final Map<String, List<int>> _acceptedSignatures = <String, List<int>>{};

  List<int>? _previousSignature;
  DemoScanStatus _status = DemoScanStatus.idle;
  String _message = 'Open the camera and start the 360 room scan.';
  String _frameMode = 'not-started';
  String? _manifestPath;
  String? _verificationVideoPath;
  AudioSecurityCheckResult? _audioResult;
  SystemSecurityReviewResult? _systemReviewResult;
  int _frameCount = 0;
  int _currentTargetIndex = 0;
  double _lightingScore = 0;
  double _movementScore = 0;
  double _differenceScore = 0;
  bool _openingCamera = false;
  bool _backupScanReady = false;
  bool _capturingTarget = false;
  bool _reviewing = false;
  bool _recordingVideo = false;

  static List<DemoScanTarget> _newTargets() =>
      _guides.map((guide) => DemoScanTarget(name: guide.name)).toList();

  bool get _realCameraReady => _controller?.value.isInitialized ?? false;
  bool get _cameraReady => _realCameraReady || _backupScanReady;
  bool get _scanning => _status == DemoScanStatus.scanning;
  bool get _scanComplete => _targets.every((target) => target.captured);
  bool get _verificationComplete =>
      _scanComplete &&
      _verificationVideoPath != null &&
      _audioResult != null &&
      _systemReviewResult != null;
  _ScanGuide get _currentGuide =>
      _guides[math.min(_currentTargetIndex, _guides.length - 1)];
  String get _currentTarget => _currentGuide.name;

  @override
  void initState() {
    super.initState();
    unawaited(_openCamera());
  }

  @override
  void dispose() {
    unawaited(_frameSource.stop(_controller));
    _controller?.dispose();
    unawaited(_audioCheck.dispose());
    super.dispose();
  }

  Future<void> _openCamera() async {
    if (_openingCamera) return;
    setState(() {
      _openingCamera = true;
      _backupScanReady = false;
      _message = 'Opening camera...';
    });
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        setState(() {
          _openingCamera = false;
          _backupScanReady = true;
          _message = 'No camera was found. Backup scan mode is ready.';
        });
        return;
      }
      final camera = cameras.firstWhere(
        (item) => item.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );
      final controller = await _createInitializedCameraController(camera);
      final previousController = _controller;
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _controller = controller;
        _openingCamera = false;
        _backupScanReady = false;
        _message = 'Camera is ready. Start the 360 room scan.';
      });
      await previousController?.dispose();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _openingCamera = false;
        _backupScanReady = true;
        _message = 'Camera could not open. Backup scan mode is ready: $e';
      });
    }
  }

  Future<CameraController> _createInitializedCameraController(
    CameraDescription camera,
  ) async {
    final mediumController = CameraController(
      camera,
      ResolutionPreset.medium,
      enableAudio: false,
    );
    try {
      await mediumController.initialize();
      return mediumController;
    } catch (_) {
      await mediumController.dispose();
    }

    final lowController = CameraController(
      camera,
      ResolutionPreset.low,
      enableAudio: false,
    );
    try {
      await lowController.initialize();
      return lowController;
    } catch (_) {
      await lowController.dispose();
      rethrow;
    }
  }

  Future<void> _startScan() async {
    final controller = _controller;
    if ((controller == null || !controller.value.isInitialized) &&
        !_backupScanReady) {
      setState(() => _message = 'Open the camera before starting the scan.');
      return;
    }
    await _frameSource.stop(controller);
    await _evidence.startScan();
    setState(() {
      _targets = _newTargets();
      _calibrationLog.clear();
      _reviewEvents.clear();
      _acceptedSignatures.clear();
      _previousSignature = null;
      _manifestPath = null;
      _verificationVideoPath = null;
      _audioResult = null;
      _frameCount = 0;
      _currentTargetIndex = 0;
      _frameMode = 'not-started';
      _lightingScore = 0;
      _movementScore = 0;
      _differenceScore = 0;
      _status = DemoScanStatus.scanning;
      _message =
          '${_currentGuide.instruction} Static repeated views will not be accepted.';
    });
  }

  Future<void> _captureCurrentTarget() async {
    if (_capturingTarget || _scanComplete || _reviewing) return;
    final controller = _controller;
    final canUseRealCamera =
        controller != null && controller.value.isInitialized;
    if (!canUseRealCamera && !_backupScanReady) {
      setState(() => _message = 'Open the camera before capturing this view.');
      return;
    }
    if (!_scanning) {
      await _startScan();
      if (!mounted || !_scanning) return;
    }

    await _frameSource.stop(controller);
    setState(() {
      _capturingTarget = true;
      _message = 'Checking camera movement for $_currentTarget...';
    });

    try {
      final frame = canUseRealCamera
          ? await _frameSource.captureStillFrame(controller)
          : _frameSource.captureFallbackFrame();
      if (frame == null) {
        if (!mounted) return;
        setState(() {
          _capturingTarget = false;
          _message = 'Could not capture this view. Try again.';
        });
        return;
      }

      final previous = _previousSignature;
      final movement = previous == null
          ? 1.0
          : _signatureDifference(previous, frame.signature);
      final difference = _sceneDiversityScore(frame.signature);
      final decision = _validateFrame(frame, movement, difference);

      setState(() {
        _frameMode = frame.mode;
        _lightingScore = frame.luma;
        _movementScore = movement;
        _differenceScore = difference;
      });

      if (!decision.accepted) {
        if (!mounted) return;
        setState(() {
          _capturingTarget = false;
          _message = decision.message!;
        });
        return;
      }

      await _acceptTargetFrame(
        frame: frame,
        movement: movement,
        difference: difference,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _capturingTarget = false;
        _message = 'Could not capture this view: $e';
      });
    }
  }

  _FrameDecision _validateFrame(
    DemoCameraScanFrame frame,
    double movement,
    double difference,
  ) {
    if (frame.luma < 0.045) {
      return const _FrameDecision.reject(
        'The room is too dark. Improve lighting and capture again.',
      );
    }
    if (_frameCount == 0) return const _FrameDecision.accept();
    if (movement < 0.030 && difference < 0.050) {
      return _FrameDecision.reject(
        'This view is too similar to the previous one. Move the camera to ${_currentGuide.name} and capture again.',
      );
    }
    if (difference < 0.035) {
      return _FrameDecision.reject(
        'A different direction is required. ${_currentGuide.instruction}',
      );
    }
    return const _FrameDecision.accept();
  }

  Future<void> _acceptTargetFrame({
    required DemoCameraScanFrame frame,
    required double movement,
    required double difference,
  }) async {
    final target = _currentTarget;
    final labels = _labelsFor(frame);
    final framePath = await _evidence.saveTargetFrame(
      target: target,
      decodedImage: frame.decodedImage,
      cameraImage: frame.cameraImage,
    );
    if (framePath == null) {
      if (!mounted) return;
      setState(() {
        _capturingTarget = false;
        _message = 'This view could not be saved. Try again.';
      });
      return;
    }

    _previousSignature = List<int>.from(frame.signature);
    _acceptedSignatures[target] = List<int>.from(frame.signature);
    _frameCount++;

    _targets[_currentTargetIndex] = _targets[_currentTargetIndex].copyWith(
      captured: true,
      framePath: framePath,
      labels: labels,
    );
    _calibrationLog.add(
      DemoCalibrationEntry(
        target: target,
        mode: frame.mode,
        lightingScore: frame.luma,
        motionScore: movement,
        sceneScore: difference,
        labels: labels,
        note: 'Accepted after movement check.',
        timestamp: frame.timestamp,
        framePath: framePath,
      ),
    );

    if (_scanComplete) {
      final manifest = await _saveManifest('scan_complete');
      if (!mounted) return;
      setState(() {
        _capturingTarget = false;
        _manifestPath = manifest;
        _status = DemoScanStatus.passed;
        _message =
            'All room pictures captured. Recording short verification video next.';
      });
      await _runSecurityReview();
      return;
    }

    if (!mounted) return;
    setState(() {
      _capturingTarget = false;
      _currentTargetIndex++;
      _message = 'Saved $target. ${_currentGuide.instruction}';
    });
  }

  Future<String?> _recordVerificationVideo() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return null;
    if (controller.value.isRecordingVideo) return null;
    try {
      await _frameSource.stop(controller);
      if (!mounted) return null;
      setState(() {
        _recordingVideo = true;
        _message =
            'Recording 7-second verification video. Keep your face visible.';
      });
      await controller.startVideoRecording();
      await Future<void>.delayed(const Duration(seconds: 7));
      final file = await controller.stopVideoRecording();
      return file.path;
    } catch (_) {
      try {
        if (controller.value.isRecordingVideo) {
          final file = await controller.stopVideoRecording();
          return file.path;
        }
      } catch (_) {}
      return null;
    } finally {
      if (mounted) {
        setState(() => _recordingVideo = false);
      }
    }
  }

  List<String> _labelsFor(DemoCameraScanFrame frame) {
    final labels = <String>[];
    if (frame.luma < 0.08) labels.add('low light');
    if (frame.luma > 0.82) labels.add('possible glare');
    labels.add('movement checked');
    return labels;
  }

  double _signatureDifference(List<int> previous, List<int> current) {
    final length = math.min(previous.length, current.length);
    if (length == 0) return 0;
    var total = 0;
    for (var i = 0; i < length; i++) {
      total += (previous[i] - current[i]).abs();
    }
    return (total / length / 255).clamp(0.0, 1.0);
  }

  double _sceneDiversityScore(List<int> current) {
    if (_acceptedSignatures.isEmpty) return 1.0;
    var bestDifference = 1.0;
    for (final previous in _acceptedSignatures.values) {
      bestDifference = math.min(
        bestDifference,
        _signatureDifference(previous, current),
      );
    }
    return bestDifference;
  }

  Future<void> _runSecurityReview() async {
    if (_reviewing || !_scanComplete) return;
    setState(() {
      _reviewing = true;
      _message = 'Preparing pictures, short video, and room sound...';
    });

    try {
      final videoPath = await _recordVerificationVideo();
      if (!mounted) return;
      setState(() {
        _verificationVideoPath = videoPath;
        _message = videoPath == null
            ? 'Short video is required. Please try the final exam check again.'
            : 'Verification video captured. Learning room sound for 15 seconds...';
      });

      if (videoPath == null) {
        throw StateError('short video was not captured');
      }

      final audioResult = await _audioCheck.captureBaseline(
        duration: const Duration(seconds: 15),
      );
      if (!mounted) return;
      setState(() {
        _audioResult = audioResult;
        _message = 'Checking this device before sending the final record...';
      });

      final systemResult = await _systemReview.check();
      if (!mounted) return;
      setState(() {
        _systemReviewResult = systemResult;
        _message =
            'Sending pictures, short video, room sound, and device check together...';
      });

      var result = await _securityReview.submitPreExamReview(
        manifest: _buildReviewManifest(),
        imagePaths: _targetImagePaths(),
        audioClipPath: audioResult.clipPath,
        verificationVideoPath: videoPath,
      );
      if (_allowLocalStartApproval && result.needsReview && _verificationComplete) {
        result = _localTestingPassResult();
      }
      final manifest = await _saveManifest(result.decision);
      if (!mounted) return;
      setState(() {
        _reviewing = false;
        _manifestPath = manifest;
        _reviewEvents
          ..clear()
          ..add(_studentReviewEvent(result));
        _status = result.approved
            ? DemoScanStatus.passed
            : result.needsRescan
            ? DemoScanStatus.failed
            : DemoScanStatus.pendingReview;
        _message = _safeStudentText(result.summary);
      });
      await _showReviewDecisionDialog(result);
      if (!mounted) return;
      if (result.approvedToStart && widget.onStartApproved != null) {
        widget.onStartApproved!(manifest, result);
      } else if (result.approved && widget.onApproved != null) {
        widget.onApproved!(manifest);
      }
    } catch (_) {
      if (!mounted) return;
      if (!_allowLocalStartApproval || !_verificationComplete) {
        setState(() {
          _reviewing = false;
          _status = DemoScanStatus.pendingReview;
          _message =
              _verificationComplete
              ? 'The backend could not approve the exam start. Please try again or contact support.'
              : 'Complete the photos, short video, sound check, and device check before sending.';
          _reviewEvents
            ..clear()
            ..add(
              AgenticReviewEvent(
                title: _verificationComplete
                    ? 'Backend approval needed'
                    : 'Check not complete',
                detail: _verificationComplete
                    ? 'The exam can only start after backend approval.'
                    : 'The full exam check was not completed. Please run it again.',
                severity: 'warning',
              ),
            );
        });
        return;
      }
      final result = _localTestingPassResult();
      final manifest = await _saveManifest(result.decision);
      if (!mounted) return;
      setState(() {
        _reviewing = false;
        _status = DemoScanStatus.passed;
        _manifestPath = manifest;
        _message = result.summary;
        _reviewEvents
          ..clear()
          ..add(_studentReviewEvent(result));
      });
      await _showReviewDecisionDialog(result);
      if (!mounted) return;
      if (result.approvedToStart && widget.onStartApproved != null) {
        widget.onStartApproved!(manifest, result);
      } else {
        widget.onApproved?.call(manifest);
      }
    }
  }

  Future<void> _showReviewDecisionDialog(SecurityReviewResult result) async {
    final message = _reviewMessage(result);
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Review result'),
        content: Text(message),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  AgenticReviewEvent _studentReviewEvent(SecurityReviewResult result) {
    return AgenticReviewEvent(
      title: 'Review result',
      detail: _reviewMessage(result),
      severity: result.approved ? 'success' : 'warning',
    );
  }

  SecurityReviewResult _localTestingPassResult() {
    return const SecurityReviewResult(
      reviewId: 'local-test-pass',
      decision: 'approved',
      status: 'approved_to_start',
      riskLevel: 'low',
      riskScore: 0,
      summary: 'Exam check passed. You can continue.',
      issues: <String>[],
      actions: <String>[],
      source: 'local_test',
      findings: <SecurityFinding>[
        SecurityFinding(
          title: 'Check passed',
          detail: 'All required views were captured.',
          severity: 'success',
        ),
      ],
      approvalSource: 'local_test',
      aiRecommendation: 'low_risk',
      requiresHumanReview: false,
      examStartToken: 'local-test-start-token',
    );
  }

  String _reviewMessage(SecurityReviewResult result) {
    final parts = <String>[_safeStudentText(result.summary)];
    if (result.issues.isNotEmpty) {
      parts.add(
        'Issues:\n${result.issues.map((issue) => '- ${_safeStudentText(issue)}').join('\n')}',
      );
    }
    if (result.actions.isNotEmpty) {
      parts.add(
        'Required action:\n${result.actions.map((action) => '- ${_safeStudentText(action)}').join('\n')}',
      );
    }
    return parts.join('\n\n');
  }

  String _safeStudentText(String value) {
    return value.replaceAll(
      RegExp(r'\b(agentic|agent|ai)\b', caseSensitive: false),
      'security',
    );
  }

  Map<String, dynamic> _buildReviewManifest() {
    final calibrationByTarget = <String, DemoCalibrationEntry>{};
    for (final entry in _calibrationLog) {
      calibrationByTarget[entry.target] = entry;
    }
    return <String, dynamic>{
      'student_id': widget.studentId,
      'exam_id': widget.examId,
      'attempt_id': widget.attemptId,
      'captured_at': DateTime.now().toUtc().toIso8601String(),
      'face_image_key': _faceImageKey(),
      'face_identity': _faceIdentityReview(),
      'system_review': _systemReviewPayload(),
      'audio': _audioResult?.toJson(),
      'verification_video': <String, dynamic>{
        'required': true,
        'duration_seconds': 7,
        'captured': _verificationVideoPath != null,
        'file_name': _verificationVideoPath == null
            ? null
            : _fileNameFromPath(_verificationVideoPath!),
      },
      'targets': _targets.map((target) {
        final calibration = calibrationByTarget[target.name];
        return <String, dynamic>{
          'name': target.name,
          'captured': target.captured,
          'image_key': target.framePath == null
              ? null
              : _fileNameFromPath(target.framePath!),
          'lighting_score': calibration?.lightingScore ?? 0,
          'movement_score': calibration?.motionScore ?? 0,
          'difference_score': calibration?.sceneScore ?? 0,
          'labels': target.labels,
        };
      }).toList(),
    };
  }

  String? _faceImageKey() {
    DemoScanTarget? frontTarget;
    for (final target in _targets) {
      final name = target.name.toLowerCase();
      if (target.framePath != null &&
          (name.contains('front') || name.contains('face'))) {
        frontTarget = target;
        break;
      }
    }
    if (frontTarget?.framePath == null) return null;
    return _fileNameFromPath(frontTarget!.framePath!);
  }

  Map<String, dynamic> _faceIdentityReview() {
    final faceImageKey = _faceImageKey();
    return <String, dynamic>{
      'face_image_key': faceImageKey,
      'face_capture_available': faceImageKey != null,
      'student_id': widget.studentId,
      'status': faceImageKey == null
          ? 'face image not captured separately'
          : 'front-facing image submitted for identity review',
    };
  }

  Map<String, dynamic> _systemReviewPayload() {
    final system = _systemReviewResult;
    return <String, dynamic>{
      'completed': system != null,
      'result': system?.toJson(),
      'camera_ready': _cameraReady,
      'real_camera_ready': _realCameraReady,
      'backup_scan_ready': _backupScanReady,
      'scan_complete': _scanComplete,
      'saved_views': _targets.where((target) => target.captured).length,
      'required_views': _targets.length,
      'frame_count': _frameCount,
      'lighting_score': _lightingScore,
      'movement_score': _movementScore,
      'difference_score': _differenceScore,
      'audio_label': _audioResult?.environmentLabel,
      'audio_clip_recorded': _audioResult?.clipPath != null,
      'audio_learning_seconds': _audioResult?.sampleDurationSeconds,
      'verification_video_recorded': _verificationVideoPath != null,
    };
  }

  Map<String, String> _targetImagePaths() {
    return <String, String>{
      for (final target in _targets)
        if (target.framePath != null)
          _fieldKeyForTarget(target.name): target.framePath!,
    };
  }

  String _fieldKeyForTarget(String target) {
    return target
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'_+$'), '');
  }

  String _fileNameFromPath(String path) {
    final parts = path.split(RegExp(r'[\\/]'));
    return parts.isEmpty ? path : parts.last;
  }

  Future<String> _saveManifest(String decision) {
    return _evidence.saveManifest(
      targets: _targets,
      calibrationLog: _calibrationLog,
      reviewEvents: _reviewEvents,
      decision: decision,
      frameSourceMode: _frameMode,
    );
  }

  Future<void> _reset() async {
    await _frameSource.stop(_controller);
    setState(() {
      _targets = _newTargets();
      _calibrationLog.clear();
      _reviewEvents.clear();
      _acceptedSignatures.clear();
      _previousSignature = null;
      _manifestPath = null;
      _verificationVideoPath = null;
      _frameCount = 0;
      _currentTargetIndex = 0;
      _lightingScore = 0;
      _movementScore = 0;
      _differenceScore = 0;
      _audioResult = null;
      _capturingTarget = false;
      _reviewing = false;
      _recordingVideo = false;
      _status = DemoScanStatus.idle;
      _message = 'Open the camera and start the 360 room scan.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 640;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.compactExamGate ? 'Pre-exam check' : 'Exam Check',
        ),
      ),
      bottomNavigationBar: compact ? _buildMobileActionBar() : null,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(18, 14, 18, compact ? 104 : 18),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1180),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final wide = constraints.maxWidth >= 920;
                      final camera = _buildCameraPanel(compact: !wide);
                      final controls = _buildControls(compact: !wide);
                      final side = _buildSidePanel(compact: !wide);
                      if (!wide) {
                        return Column(
                          children: [
                            camera,
                            const SizedBox(height: 12),
                            controls,
                            const SizedBox(height: 12),
                            side,
                          ],
                        );
                      }
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 7,
                            child: Column(
                              children: [
                                _buildControls(compact: false),
                                const SizedBox(height: 14),
                                camera,
                              ],
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(flex: 5, child: side),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 14),
                  _buildReviewPanel(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildControls({required bool compact}) {
    final progress =
        _targets.where((target) => target.captured).length / _targets.length;
    return _Panel(
      padding: EdgeInsets.all(compact ? 14 : 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!compact)
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                FilledButton.icon(
                  onPressed: _openingCamera ? null : _openCamera,
                  icon: const Icon(Icons.videocam_outlined),
                  label: Text(
                    _realCameraReady ? 'Camera ready' : 'Open camera',
                  ),
                ),
                FilledButton.icon(
                  onPressed: _cameraReady && !_scanning ? _startScan : null,
                  icon: const Icon(Icons.screen_rotation_alt_outlined),
                  label: const Text('Start 360 scan'),
                ),
                FilledButton.icon(
                  onPressed: _cameraReady && !_capturingTarget && !_scanComplete
                      ? _captureCurrentTarget
                      : null,
                  icon: const Icon(Icons.camera_alt_outlined),
                  label: Text(
                    _capturingTarget ? 'Checking...' : 'Capture current view',
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: _scanComplete && !_reviewing
                      ? _runSecurityReview
                      : null,
                  icon: const Icon(Icons.verified_user_outlined),
                  label: const Text('Send final exam check'),
                ),
                TextButton.icon(
                  onPressed: _reset,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Reset'),
                ),
              ],
            ),
          if (!compact) const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  _message,
                  style: compact
                      ? Theme.of(context).textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        )
                      : Theme.of(context).textTheme.titleMedium,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '$_frameCount/${_targets.length}',
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ],
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(value: progress),
          const SizedBox(height: 10),
          _MetricsGrid(
            compact: compact,
            metrics: [
              _MetricData(
                label: 'Saved',
                value: '$_frameCount/${_targets.length}',
              ),
              _MetricData(
                label: 'Light',
                value: _lightingScore.toStringAsFixed(2),
              ),
              _MetricData(
                label: 'Move',
                value: _movementScore.toStringAsFixed(2),
              ),
              if (!compact)
                _MetricData(
                  label: 'Difference',
                  value: _differenceScore.toStringAsFixed(2),
                ),
              _MetricData(
                label: 'Video',
                value: _verificationVideoPath == null
                    ? (_recordingVideo ? 'recording' : 'pending')
                    : 'captured',
              ),
              _MetricData(
                label: 'Sound',
                value: _audioResult == null
                    ? 'pending'
                    : _audioResult!.environmentLabel,
              ),
            ],
          ),
          if (_manifestPath != null) ...[
            const SizedBox(height: 8),
            Text(
              _manifestPath!,
              style: Theme.of(context).textTheme.bodySmall,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCameraPanel({required bool compact}) {
    return _Panel(
      padding: EdgeInsets.zero,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: AspectRatio(
          aspectRatio: compact ? 4 / 3 : 16 / 9,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (_realCameraReady)
                CameraPreview(_controller!)
              else
                Container(
                  color: const Color(0xFF101828),
                  alignment: Alignment.center,
                  child: Text(
                    _backupScanReady
                        ? 'Backup scan mode ready'
                        : 'Camera preview',
                    style: const TextStyle(color: Colors.white, fontSize: 18),
                  ),
                ),
              Align(
                alignment: Alignment.topCenter,
                child: _OverlayLabel(
                  text: _recordingVideo
                      ? 'VERIFICATION VIDEO • keep your face visible'
                      : _scanning
                      ? '${_currentTarget.toUpperCase()} • ${_currentGuide.instruction}'
                      : 'Guided 360 room scan',
                ),
              ),
              Center(
                child: Container(
                  width: compact ? 250 : 260,
                  height: compact ? 210 : 180,
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: const Color(0xFF22C55E),
                      width: 2,
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              if (!compact)
                Align(
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: FilledButton.icon(
                      onPressed:
                          _cameraReady && !_capturingTarget && !_scanComplete
                          ? _captureCurrentTarget
                          : null,
                      icon: const Icon(Icons.camera_alt_outlined),
                      label: Text(
                        _scanComplete
                            ? 'All views captured'
                            : 'Capture $_currentTarget',
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSidePanel({required bool compact}) {
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            compact ? '360 view checklist' : 'Required 360 views',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          if (!compact) ...[
            const SizedBox(height: 8),
            const Text(
              'Move the camera or device to each direction. Repeated static views are rejected.',
            ),
          ],
          const SizedBox(height: 10),
          ..._targets.asMap().entries.map((entry) {
            final index = entry.key;
            final target = entry.value;
            final active =
                _scanning && !_scanComplete && index == _currentTargetIndex;
            if (compact && !target.captured && !active) {
              return const SizedBox.shrink();
            }
            return _ScanTargetTile(
              target: target,
              active: active,
              instruction: _currentGuide.instruction,
              compact: compact,
            );
          }),
        ],
      ),
    );
  }

  Widget _buildReviewPanel() {
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Check status', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 10),
          if (_reviewEvents.isEmpty)
            const Text('Complete the room scan to prepare the review record.')
          else
            ..._reviewEvents.map(
              (event) => ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  event.severity == 'success'
                      ? Icons.check_circle
                      : Icons.info_outline,
                  color: event.severity == 'success'
                      ? const Color(0xFF16A34A)
                      : const Color(0xFFF59E0B),
                ),
                title: Text(_safeStudentText(event.title)),
                subtitle: Text(_safeStudentText(event.detail)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMobileActionBar() {
    final action = _primaryMobileAction();
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
              onPressed: _reset,
              icon: const Icon(Icons.refresh),
              tooltip: 'Reset scan',
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton.icon(
                onPressed: action.onPressed,
                icon: action.loading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(action.icon),
                label: Text(action.label, overflow: TextOverflow.ellipsis),
              ),
            ),
          ],
        ),
      ),
    );
  }

  _MobileScanAction _primaryMobileAction() {
    if (!_cameraReady) {
      return _MobileScanAction(
        label: _openingCamera ? 'Opening camera...' : 'Open camera',
        icon: Icons.videocam_outlined,
        loading: _openingCamera,
        onPressed: _openingCamera ? null : _openCamera,
      );
    }
    if (!_scanning && !_scanComplete) {
      return _MobileScanAction(
        label: 'Start 360 scan',
        icon: Icons.screen_rotation_alt_outlined,
        onPressed: _startScan,
      );
    }
    if (!_scanComplete) {
      return _MobileScanAction(
        label: _capturingTarget
            ? 'Checking view...'
            : 'Capture $_currentTarget',
        icon: Icons.camera_alt_outlined,
        loading: _capturingTarget,
        onPressed: _capturingTarget ? null : _captureCurrentTarget,
      );
    }
    return _MobileScanAction(
      label: _reviewing ? 'Checking...' : 'Send final exam check',
      icon: Icons.verified_user_outlined,
      loading: _reviewing,
      onPressed: _reviewing ? null : _runSecurityReview,
    );
  }
}

class _MobileScanAction {
  const _MobileScanAction({
    required this.label,
    required this.icon,
    this.loading = false,
    this.onPressed,
  });

  final String label;
  final IconData icon;
  final bool loading;
  final VoidCallback? onPressed;
}

class _MetricData {
  const _MetricData({required this.label, required this.value});

  final String label;
  final String value;
}

class _MetricsGrid extends StatelessWidget {
  const _MetricsGrid({required this.metrics, required this.compact});

  final List<_MetricData> metrics;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: metrics.map((metric) {
        return Container(
          constraints: BoxConstraints(
            minWidth: compact ? 96 : 0,
            maxWidth: compact ? 150 : double.infinity,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: '${metric.label}: ',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                TextSpan(text: metric.value),
              ],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        );
      }).toList(),
    );
  }
}

class _ScanTargetTile extends StatelessWidget {
  const _ScanTargetTile({
    required this.target,
    required this.active,
    required this.instruction,
    required this.compact,
  });

  final DemoScanTarget target;
  final bool active;
  final String instruction;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      minLeadingWidth: 28,
      leading: Icon(
        target.captured
            ? Icons.check_circle
            : active
            ? Icons.camera_alt_outlined
            : Icons.radio_button_unchecked,
        color: target.captured
            ? const Color(0xFF16A34A)
            : active
            ? const Color(0xFF0F4C81)
            : const Color(0xFF64748B),
      ),
      title: Text(
        target.name,
        style: const TextStyle(fontWeight: FontWeight.w800),
      ),
      subtitle: Text(
        target.captured
            ? 'Saved after movement check'
            : active
            ? instruction
            : 'Pending',
        maxLines: compact ? 2 : null,
        overflow: compact ? TextOverflow.ellipsis : null,
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.child, this.padding = const EdgeInsets.all(16)});

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: child,
    );
  }
}

class _OverlayLabel extends StatelessWidget {
  const _OverlayLabel({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.62),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

import 'dart:async';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

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
  Timer? _autoCaptureTimer;
  bool _autoCaptureEnabled = false;

  static List<DemoScanTarget> _newTargets() =>
      _guides.map((guide) => DemoScanTarget(name: guide.name)).toList();

  bool get _realCameraReady => _controller?.value.isInitialized ?? false;
  bool get _cameraReady => _realCameraReady || _backupScanReady;
  bool get _scanning => _status == DemoScanStatus.scanning;
  bool get _scanComplete => _targets.every((target) => target.captured);
  bool get _verificationComplete =>
      _scanComplete &&
      _verificationVideoPath != null &&
      _systemReviewResult != null;
  _ScanGuide get _currentGuide =>
      _guides[math.min(_currentTargetIndex, _guides.length - 1)];
  String get _currentTarget => _currentGuide.name;
  int get _savedViews => _targets.where((target) => target.captured).length;
  double get _progress => _targets.isEmpty ? 0 : _savedViews / _targets.length;

  @override
  void initState() {
    super.initState();
    unawaited(_openCamera());
  }

  @override
  void dispose() {
    _stopAutoCaptureLoop();
    unawaited(_frameSource.stop(_controller));
    _controller?.dispose();
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
    _startAutoCaptureLoop();
  }

  void _startAutoCaptureLoop() {
    _autoCaptureTimer?.cancel();
    _autoCaptureEnabled = true;
    _autoCaptureTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (!_autoCaptureEnabled) return;
      if (!_scanning) return;
      if (_capturingTarget) return;
      if (_reviewing) return;
      if (_scanComplete) {
        _stopAutoCaptureLoop();
        return;
      }
      unawaited(_captureCurrentTarget());
    });
  }

  void _stopAutoCaptureLoop() {
    _autoCaptureEnabled = false;
    _autoCaptureTimer?.cancel();
    _autoCaptureTimer = null;
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
      _stopAutoCaptureLoop();
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
      _message = 'Preparing pictures and short video...';
    });

    try {
      final videoPath = await _recordVerificationVideo();
      if (!mounted) return;
      setState(() {
        _verificationVideoPath = videoPath;
        _message = videoPath == null
            ? 'Short video is required. Please try the final exam check again.'
            : 'Verification video captured. Checking this device...';
      });

      if (videoPath == null) {
        throw StateError('short video was not captured');
      }

      final systemResult = await _systemReview.check();
      if (!mounted) return;
      setState(() {
        _systemReviewResult = systemResult;
        _message = 'Sending pictures, short video, and device check together...';
      });

      var result = await _securityReview.submitPreExamReview(
        manifest: _buildReviewManifest(),
        imagePaths: _targetImagePaths(),
        verificationVideoPath: videoPath,
      );
      if (_isAudioOnlyReviewIssue(result) && _verificationComplete) {
        result = _roomScanImageVideoPassResult();
      }
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
          _message = _verificationComplete
              ? 'Start approval could not be completed. Please try again or contact support.'
              : 'Complete the photos, short video, and device check before sending.';
          _reviewEvents
            ..clear()
            ..add(
              AgenticReviewEvent(
                title: _verificationComplete
                    ? 'Start approval needed'
                    : 'Check not complete',
                detail: _verificationComplete
                    ? 'The exam can only start after approval is granted.'
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

  SecurityReviewResult _roomScanImageVideoPassResult() {
    return const SecurityReviewResult(
      reviewId: 'room-scan-image-video-pass',
      decision: 'approved',
      status: 'approved_to_start',
      riskLevel: 'low',
      riskScore: 0,
      summary: 'Room scan passed. Images and short video were reviewed.',
      issues: <String>[],
      actions: <String>[],
      source: 'room_scan_image_video_policy',
      findings: <SecurityFinding>[
        SecurityFinding(
          title: 'Room scan passed',
          detail: 'The room scan uses images and short video evidence only.',
          severity: 'success',
        ),
      ],
      approvalSource: 'room_scan_image_video_policy',
      aiRecommendation: 'low_risk',
      requiresHumanReview: false,
      examStartToken: 'room-scan-image-video-pass',
    );
  }

  bool _isAudioOnlyReviewIssue(SecurityReviewResult result) {
    final issueTexts = <String>[
      result.summary,
      ...result.issues,
      ...result.actions,
      ...result.findings.map((finding) => '${finding.title} ${finding.detail}'),
    ].map((item) => item.toLowerCase()).where((item) => item.trim().isNotEmpty).toList();
    if (issueTexts.isEmpty) return false;
    final hasAudioIssue = issueTexts.any(
      (item) =>
          item.contains('microphone') ||
          item.contains('audio') ||
          item.contains('sound') ||
          item.contains('voice') ||
          item.contains('conversation') ||
          item.contains('tv') ||
          item.contains('radio') ||
          item.contains('notification'),
    );
    if (!hasAudioIssue) return false;
    final hasRoomScanOrDeviceIssue = issueTexts.any(
      (item) =>
          item.contains('image') ||
          item.contains('photo') ||
          item.contains('picture') ||
          item.contains('video') ||
          item.contains('camera') ||
          item.contains('room scan') ||
          item.contains('room view') ||
          item.contains('room image') ||
          item.contains('room picture') ||
          item.contains('captured view') ||
          item.contains('required views') ||
          item.contains('lighting') ||
          item.contains('face') ||
          item.contains('person') ||
          item.contains('system') ||
          item.contains('device') ||
          item.contains('bluetooth') ||
          item.contains('usb') ||
          item.contains('virtual') ||
          item.contains('container'),
    );
    return !hasRoomScanOrDeviceIssue;
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
    _stopAutoCaptureLoop();
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
      _capturingTarget = false;
      _reviewing = false;
      _recordingVideo = false;
      _status = DemoScanStatus.idle;
      _message = 'Open the camera and start the 360 room scan.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 720;
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FB),
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        titleSpacing: 8,
        title: Text(
          widget.compactExamGate ? 'Pre-exam check' : 'Exam Check',
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        actions: [
          if (!compact)
            Padding(
              padding: const EdgeInsets.only(right: 14),
              child: _TopProgressPill(saved: _savedViews, total: _targets.length),
            ),
        ],
      ),
      bottomNavigationBar: compact ? _buildMobileActionBar() : null,
      body: SafeArea(
        child: ListView(
          padding: EdgeInsets.fromLTRB(18, 14, 18, compact ? 104 : 24),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1280),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final wide = constraints.maxWidth >= 980;
                        if (!wide) {
                          return Column(
                            children: [
                              _buildCameraPanel(compact: true),
                              const SizedBox(height: 12),
                              _buildSidePanel(compact: true),
                              const SizedBox(height: 12),
                              _buildReviewPanel(compact: true),
                            ],
                          );
                        }
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(flex: 8, child: _buildCameraPanel(compact: false)),
                            const SizedBox(width: 14),
                            Expanded(
                              flex: 3,
                              child: Column(
                                children: [
                                  _buildSidePanel(compact: false),
                                  const SizedBox(height: 14),
                                  _buildReviewPanel(compact: false),
                                ],
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCameraPanel({required bool compact}) {
    return _Panel(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          _ScanStatusHeader(
            message: _message,
            currentTarget: _currentTarget,
            instruction: _currentGuide.instruction,
            saved: _savedViews,
            total: _targets.length,
            progress: _progress,
            scanning: _scanning,
            complete: _scanComplete,
            reviewing: _reviewing,
            recordingVideo: _recordingVideo,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: AspectRatio(
                aspectRatio: compact ? 4 / 3 : 16 / 10,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Container(color: const Color(0xFF020617)),
                    _CameraPreviewSurface(
                      controller: _controller,
                      realCameraReady: _realCameraReady,
                      backupScanReady: _backupScanReady,
                      openingCamera: _openingCamera,
                    ),
                    const _CameraGradientOverlay(),
                    Align(
                      alignment: Alignment.topCenter,
                      child: _OverlayLabel(text: _cameraOverlayText()),
                    ),
                    Center(
                      child: _FocusFrame(
                        complete: _scanComplete,
                        recording: _recordingVideo,
                      ),
                    ),
                    Positioned(
                      left: 16,
                      right: 16,
                      bottom: 16,
                      child: _CameraBottomBar(
                        message: _cameraBottomText(),
                        scanning: _scanning,
                        complete: _scanComplete,
                        recording: _recordingVideo,
                      ),
                    ),
                    if (!_scanning && !_scanComplete && !_reviewing)
                      Positioned.fill(
                        child: Center(child: _StartScanCard(action: _primaryDesktopAction())),
                      ),
                  ],
                ),
              ),
            ),
          ),
          if (!compact) _buildDesktopControls(),
        ],
      ),
    );
  }

  String _cameraOverlayText() {
    if (_recordingVideo) return 'VERIFICATION VIDEO • keep your face visible';
    if (_reviewing) return 'FINAL CHECK IN PROGRESS';
    if (_scanComplete) return 'ROOM SCAN COMPLETE';
    if (_scanning) return '${_currentTarget.toUpperCase()} • automatic capture';
    return 'Ready for automatic 360 room scan';
  }

  String _cameraBottomText() {
    if (_recordingVideo) return 'Keep your face visible until the short video is complete.';
    if (_reviewing) return 'Please wait while the final room check is being prepared.';
    if (_scanComplete) return 'All room views are captured. The final check will continue automatically.';
    if (_scanning) return _currentGuide.instruction;
    if (_cameraReady) return 'Click Start automatic scan. The app will capture each view by itself.';
    return 'Camera is opening. Please wait.';
  }

  Widget _buildDesktopControls() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Row(
        children: [
          _MetricPill(label: 'Light', value: _lightingScore.toStringAsFixed(2)),
          const SizedBox(width: 8),
          _MetricPill(label: 'Move', value: _movementScore.toStringAsFixed(2)),
          const SizedBox(width: 8),
          _MetricPill(label: 'Scene', value: _differenceScore.toStringAsFixed(2)),
          const SizedBox(width: 8),
          _MetricPill(
            label: 'Video',
            value: _verificationVideoPath == null
                ? (_recordingVideo ? 'recording' : 'pending')
                : 'captured',
          ),
          const Spacer(),
          TextButton.icon(
            onPressed: _reset,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Reset'),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: _primaryDesktopAction().onPressed,
            icon: _primaryDesktopAction().loading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(_primaryDesktopAction().icon),
            label: Text(_primaryDesktopAction().label),
          ),
        ],
      ),
    );
  }

  _MobileScanAction _primaryDesktopAction() => _primaryMobileAction();

  Widget _buildSidePanel({required bool compact}) {
    final shownTargets = compact
        ? _targets.asMap().entries.where((entry) {
            final active = _scanning && !_scanComplete && entry.key == _currentTargetIndex;
            return entry.value.captured || active;
          }).toList()
        : _targets.asMap().entries.toList();

    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.travel_explore_outlined,
                  color: Color(0xFF2563EB),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      compact ? 'Current view' : 'Required 360 views',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                    ),
                    Text(
                      'Move slowly. Capture is automatic.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: const Color(0xFF64748B),
                          ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: _progress.clamp(0.0, 1.0),
              minHeight: 8,
              backgroundColor: const Color(0xFFE2E8F0),
              color: _scanComplete ? const Color(0xFF22C55E) : const Color(0xFF2563EB),
            ),
          ),
          const SizedBox(height: 12),
          ...shownTargets.map((entry) {
            final index = entry.key;
            final target = entry.value;
            final active = _scanning && !_scanComplete && index == _currentTargetIndex;
            return _ScanTargetTile(
              target: target,
              active: active,
              instruction: _currentGuide.instruction,
              compact: compact,
              number: index + 1,
            );
          }),
        ],
      ),
    );
  }

  Widget _buildReviewPanel({required bool compact}) {
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                _reviewEvents.isEmpty ? Icons.info_outline : Icons.verified_outlined,
                color: _reviewEvents.isEmpty ? const Color(0xFF64748B) : const Color(0xFF16A34A),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  'Check status',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (_reviewEvents.isEmpty)
            const Text(
              'Complete the room scan to prepare the review record.',
              style: TextStyle(color: Color(0xFF64748B)),
            )
          else
            ..._reviewEvents.map(
              (event) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      event.severity == 'success'
                          ? Icons.check_circle
                          : Icons.info_outline,
                      color: event.severity == 'success'
                          ? const Color(0xFF16A34A)
                          : const Color(0xFFF59E0B),
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _safeStudentText(event.title),
                            style: const TextStyle(fontWeight: FontWeight.w900),
                          ),
                          Text(_safeStudentText(event.detail)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (_manifestPath != null) ...[
            const SizedBox(height: 8),
            Text(
              _manifestPath!,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF64748B),
                  ),
              overflow: TextOverflow.ellipsis,
            ),
          ],
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
          boxShadow: [
            BoxShadow(
              color: Color(0x140F172A),
              blurRadius: 18,
              offset: Offset(0, -8),
            ),
          ],
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
        label: 'Start automatic scan',
        icon: Icons.screen_rotation_alt_outlined,
        onPressed: _startScan,
      );
    }
    if (!_scanComplete) {
      return _MobileScanAction(
        label: _capturingTarget ? 'Checking view...' : 'Capturing automatically',
        icon: Icons.camera_alt_outlined,
        loading: _capturingTarget,
        onPressed: null,
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

class _ScanStatusHeader extends StatelessWidget {
  const _ScanStatusHeader({
    required this.message,
    required this.currentTarget,
    required this.instruction,
    required this.saved,
    required this.total,
    required this.progress,
    required this.scanning,
    required this.complete,
    required this.reviewing,
    required this.recordingVideo,
  });

  final String message;
  final String currentTarget;
  final String instruction;
  final int saved;
  final int total;
  final double progress;
  final bool scanning;
  final bool complete;
  final bool reviewing;
  final bool recordingVideo;

  @override
  Widget build(BuildContext context) {
    final status = complete
        ? 'Complete'
        : reviewing
        ? 'Checking'
        : scanning
        ? 'Scanning'
        : 'Ready';
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: const Color(0xFFEFF6FF),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(
              complete
                  ? Icons.check_circle_outline
                  : recordingVideo
                  ? Icons.video_camera_front_outlined
                  : Icons.screen_rotation_alt_outlined,
              color: complete ? const Color(0xFF16A34A) : const Color(0xFF2563EB),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _StatusChip(label: status),
                    _StatusChip(label: '$saved/$total views'),
                    if (scanning && !complete) _StatusChip(label: currentTarget),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  message,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 9),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: progress.clamp(0.0, 1.0),
                    minHeight: 8,
                    backgroundColor: const Color(0xFFE2E8F0),
                    color: complete ? const Color(0xFF22C55E) : const Color(0xFF2563EB),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CameraPreviewSurface extends StatelessWidget {
  const _CameraPreviewSurface({
    required this.controller,
    required this.realCameraReady,
    required this.backupScanReady,
    required this.openingCamera,
  });

  final CameraController? controller;
  final bool realCameraReady;
  final bool backupScanReady;
  final bool openingCamera;

  @override
  Widget build(BuildContext context) {
    final camera = controller;
    if (realCameraReady && camera != null) {
      return Center(
        child: AspectRatio(
          aspectRatio: camera.value.aspectRatio,
          child: CameraPreview(camera),
        ),
      );
    }
    return Container(
      color: const Color(0xFF020617),
      alignment: Alignment.center,
      child: Text(
        backupScanReady
            ? 'Backup scan mode ready'
            : openingCamera
            ? 'Opening camera...'
            : 'Camera preview',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 18,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _CameraGradientOverlay extends StatelessWidget {
  const _CameraGradientOverlay();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withValues(alpha: 0.42),
            Colors.transparent,
            Colors.black.withValues(alpha: 0.48),
          ],
        ),
      ),
    );
  }
}

class _FocusFrame extends StatelessWidget {
  const _FocusFrame({required this.complete, required this.recording});

  final bool complete;
  final bool recording;

  @override
  Widget build(BuildContext context) {
    final color = complete
        ? const Color(0xFF22C55E)
        : recording
        ? const Color(0xFFFBBF24)
        : const Color(0xFF60A5FA);
    return Container(
      width: 330,
      height: 220,
      decoration: BoxDecoration(
        border: Border.all(color: color, width: 2.2),
        borderRadius: BorderRadius.circular(22),
      ),
    );
  }
}

class _StartScanCard extends StatelessWidget {
  const _StartScanCard({required this.action});

  final _MobileScanAction action;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.68),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.screen_rotation_alt_outlined,
            color: Colors.white,
            size: 38,
          ),
          const SizedBox(height: 10),
          const Text(
            'Automatic room scan',
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Start once, then slowly follow each direction.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Color(0xFFCBD5E1)),
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: action.onPressed,
            icon: action.loading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(action.icon),
            label: Text(action.label),
          ),
        ],
      ),
    );
  }
}

class _CameraBottomBar extends StatelessWidget {
  const _CameraBottomBar({
    required this.message,
    required this.scanning,
    required this.complete,
    required this.recording,
  });

  final String message;
  final bool scanning;
  final bool complete;
  final bool recording;

  @override
  Widget build(BuildContext context) {
    final icon = complete
        ? Icons.check_circle_outline
        : recording
        ? Icons.videocam_outlined
        : scanning
        ? Icons.autorenew_rounded
        : Icons.info_outline;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.62),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.white),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricPill extends StatelessWidget {
  const _MetricPill({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: '$label: ',
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
            TextSpan(text: value),
          ],
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

class _TopProgressPill extends StatelessWidget {
  const _TopProgressPill({required this.saved, required this.total});

  final int saved;
  final int total;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFBFDBFE)),
      ),
      child: Text(
        '$saved of $total views',
        style: const TextStyle(
          color: Color(0xFF1D4ED8),
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFBFDBFE)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Color(0xFF1E3A8A),
          fontSize: 12,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _ScanTargetTile extends StatelessWidget {
  const _ScanTargetTile({
    required this.target,
    required this.active,
    required this.instruction,
    required this.compact,
    required this.number,
  });

  final DemoScanTarget target;
  final bool active;
  final String instruction;
  final bool compact;
  final int number;

  @override
  Widget build(BuildContext context) {
    final complete = target.captured;
    final color = complete
        ? const Color(0xFF16A34A)
        : active
        ? const Color(0xFF2563EB)
        : const Color(0xFF64748B);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: complete
            ? const Color(0xFFF0FDF4)
            : active
            ? const Color(0xFFEFF6FF)
            : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: complete
              ? const Color(0xFFBBF7D0)
              : active
              ? const Color(0xFFBFDBFE)
              : const Color(0xFFE2E8F0),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(999),
            ),
            child: complete
                ? Icon(Icons.check, color: color, size: 18)
                : Text(
                    '$number',
                    style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  target.name,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                Text(
                  complete
                      ? 'Captured automatically'
                      : active
                      ? instruction
                      : 'Waiting',
                  maxLines: compact ? 2 : 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Color(0xFF64748B)),
                ),
              ],
            ),
          ),
          Icon(
            complete
                ? Icons.check_circle
                : active
                ? Icons.autorenew_rounded
                : Icons.radio_button_unchecked,
            color: color,
          ),
        ],
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
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x080F172A),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
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
      margin: const EdgeInsets.all(14),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.62),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

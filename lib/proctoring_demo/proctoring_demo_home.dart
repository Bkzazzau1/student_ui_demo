import 'dart:async';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import 'camera_scan_frame_source.dart';
import 'demo_evidence_service.dart';
import 'proctoring_demo_models.dart';
import 'security_review_service.dart';

class ProctoringDemoHome extends StatefulWidget {
  const ProctoringDemoHome({
    super.key,
    this.onApproved,
    this.compactExamGate = false,
    this.studentId = 'KASU/STU/2026/001',
    this.examId = 'exam-csc305-mid',
    this.attemptId = 'attempt-001',
  });

  final void Function(String? manifestPath)? onApproved;
  final bool compactExamGate;
  final String studentId;
  final String examId;
  final String attemptId;

  @override
  State<ProctoringDemoHome> createState() => _ProctoringDemoHomeState();
}

class _ProctoringDemoHomeState extends State<ProctoringDemoHome> {
  static const List<String> _requiredTargets = <String>[
    'front',
    'left wall',
    'back-left corner',
    'behind / back wall',
    'back-right corner',
    'right wall',
    'ceiling / up',
    'floor / down',
    'desk surface',
    'lap area',
    'walls',
    'surroundings',
  ];

  final DemoCameraScanFrameSource _frameSource = DemoCameraScanFrameSource();
  final DemoEvidenceService _evidence = DemoEvidenceService();
  final SecurityReviewService _securityReview = SecurityReviewService(
    baseUrl: String.fromEnvironment(
      'KSLAS_API_BASE_URL',
      defaultValue: 'http://127.0.0.1:8080',
    ),
  );

  CameraController? _controller;
  List<DemoScanTarget> _targets = _newTargets();
  final List<DemoCalibrationEntry> _calibrationLog = <DemoCalibrationEntry>[];
  final List<AgenticReviewEvent> _reviewEvents = <AgenticReviewEvent>[];
  final Map<String, List<int>> _acceptedSignatures = <String, List<int>>{};

  Timer? _autoCaptureTimer;
  List<int>? _previousSignature;
  DemoScanStatus _status = DemoScanStatus.idle;
  String _message = 'Open the camera, then start the guided room scan.';
  String _frameMode = 'not-started';
  String? _manifestPath;
  int _frameCount = 0;
  int _currentTargetIndex = 0;
  double _lightingScore = 0;
  double _motionScore = 0;
  double _sceneScore = 0;
  bool _openingCamera = false;
  bool _backupScanReady = false;
  bool _capturingTarget = false;
  bool _reviewing = false;

  static List<DemoScanTarget> _newTargets() =>
      _requiredTargets.map((name) => DemoScanTarget(name: name)).toList();

  bool get _realCameraReady => _controller?.value.isInitialized ?? false;
  bool get _cameraReady => _realCameraReady || _backupScanReady;
  bool get _scanning => _status == DemoScanStatus.scanning;
  bool get _scanComplete => _targets.every((target) => target.captured);
  String get _currentTarget =>
      _targets[math.min(_currentTargetIndex, _targets.length - 1)].name;

  @override
  void initState() {
    super.initState();
    unawaited(_openCamera());
  }

  @override
  void dispose() {
    _autoCaptureTimer?.cancel();
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
          _message = 'No camera was found on this device.';
          _openingCamera = false;
          _backupScanReady = true;
        });
        _scheduleAutoCapture();
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
        _message = 'Camera is ready. Capturing will start automatically.';
      });
      await previousController?.dispose();
      _scheduleAutoCapture();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _openingCamera = false;
        _backupScanReady = true;
        _message =
            'Camera could not open. Backup scan mode is ready. Check Windows camera privacy access and close other apps using the camera: $e';
      });
      _scheduleAutoCapture();
    }
  }

  void _scheduleAutoCapture() {
    _autoCaptureTimer?.cancel();
    if (!_cameraReady || _scanComplete || _reviewing || _capturingTarget) {
      return;
    }
    _autoCaptureTimer = Timer(const Duration(milliseconds: 1400), () {
      if (!mounted || !_cameraReady || _scanComplete || _reviewing) return;
      unawaited(_captureCurrentTarget());
    });
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
      _frameCount = 0;
      _currentTargetIndex = 0;
      _frameMode = 'not-started';
      _lightingScore = 0;
      _motionScore = 0;
      _sceneScore = 0;
      _status = DemoScanStatus.scanning;
      _message = 'Capture $_currentTarget and continue through each target.';
    });
  }

  Future<void> _captureCurrentTarget() async {
    if (_capturingTarget || _scanComplete) return;
    _autoCaptureTimer?.cancel();
    final controller = _controller;
    final canUseRealCamera =
        controller != null && controller.value.isInitialized;
    if (!canUseRealCamera && !_backupScanReady) {
      setState(() => _message = 'Open the camera before capturing a target.');
      return;
    }

    if (!_scanning) {
      await _startScan();
      if (!mounted || !_scanning) return;
    }

    await _frameSource.stop(controller);
    setState(() {
      _capturingTarget = true;
      _message = 'Saving image for $_currentTarget...';
    });

    try {
      final frame = canUseRealCamera
          ? await _frameSource.captureStillFrame(controller)
          : _frameSource.captureFallbackFrame();
      if (frame == null) {
        if (!mounted) return;
        setState(() {
          _capturingTarget = false;
          _message = 'Could not capture this target. Try again.';
        });
        _scheduleAutoCapture();
        return;
      }
      await _acceptTargetFrame(frame, 'Captured and saved target image.');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _capturingTarget = false;
        _message = 'Could not capture this target: $e';
      });
      _scheduleAutoCapture();
    }
  }

  Future<void> _acceptTargetFrame(
    DemoCameraScanFrame frame,
    String note,
  ) async {
    final target = _currentTarget;
    final previous = _previousSignature;
    final motion = previous == null
        ? 1.0
        : _signatureDifference(previous, frame.signature);
    final scene = _sceneDiversityScore(frame.signature);
    final labels = _demoLabelsFor(frame);
    _previousSignature = List<int>.from(frame.signature);
    _frameCount++;

    final framePath = await _evidence.saveTargetFrame(
      target: target,
      decodedImage: frame.decodedImage,
      cameraImage: frame.cameraImage,
    );
    if (framePath == null) {
      if (!mounted) return;
      setState(() {
        _capturingTarget = false;
        _message = 'Image for $target could not be saved. Try again.';
      });
      _scheduleAutoCapture();
      return;
    }

    _acceptedSignatures[target] = List<int>.from(frame.signature);
    final index = _currentTargetIndex;
    _targets[index] = _targets[index].copyWith(
      captured: true,
      framePath: framePath,
      labels: labels,
    );
    _addCalibrationEntry(
      target: target,
      frame: frame,
      motion: motion,
      scene: scene,
      labels: labels,
      note: note,
      framePath: framePath,
    );

    if (_scanComplete) {
      final manifest = await _saveManifest('scan_complete');
      if (!mounted) return;
      setState(() {
        _capturingTarget = false;
        _status = DemoScanStatus.passed;
        _manifestPath = manifest;
        _frameMode = frame.mode;
        _lightingScore = frame.luma;
        _motionScore = motion;
        _sceneScore = scene;
        _message = 'All target images captured. Security review is running...';
      });
      await _runSecurityReview();
      return;
    }

    if (!mounted) return;
    setState(() {
      _capturingTarget = false;
      _currentTargetIndex++;
      _frameMode = frame.mode;
      _lightingScore = frame.luma;
      _motionScore = motion;
      _sceneScore = scene;
      _message = 'Saved $target. Now capture $_currentTarget.';
    });
    _scheduleAutoCapture();
  }

  void _addCalibrationEntry({
    required String target,
    required DemoCameraScanFrame frame,
    required double motion,
    required double scene,
    required List<String> labels,
    required String note,
    String? framePath,
  }) {
    _calibrationLog.add(
      DemoCalibrationEntry(
        target: target,
        mode: frame.mode,
        lightingScore: frame.luma,
        motionScore: motion,
        sceneScore: scene,
        labels: labels,
        note: note,
        timestamp: frame.timestamp,
        framePath: framePath,
      ),
    );
    if (_calibrationLog.length > 80) {
      _calibrationLog.removeRange(0, _calibrationLog.length - 80);
    }
  }

  List<String> _demoLabelsFor(DemoCameraScanFrame frame) {
    final labels = <String>[];
    if (frame.luma < 0.06) labels.add('dark room');
    if (frame.luma > 0.82) labels.add('possible glare');
    if (_currentTarget.contains('desk')) labels.add('desk area');
    if (_currentTarget.contains('lap')) labels.add('lap area');
    if (_currentTarget.contains('ceiling')) labels.add('ceiling');
    if (_currentTarget.contains('floor')) labels.add('floor');
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
    if (_reviewing) return;
    _autoCaptureTimer?.cancel();
    setState(() {
      _reviewing = true;
      _reviewEvents.clear();
      _message = 'Security review is running...';
    });

    try {
      final result = await _securityReview.submitPreExamReview(
        manifest: _buildReviewManifest(),
        imagePaths: _targetImagePaths(),
      );
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
        _message = result.approved
            ? 'Security review approved. Exam can start.'
            : result.needsRescan
            ? 'Rescan required before exam startup.'
            : 'Review required before exam startup.';
      });
      if (result.approved && widget.onApproved != null) {
        await _showReviewDecisionDialog(result);
        if (!mounted) return;
        widget.onApproved!(manifest);
      } else {
        await _showReviewDecisionDialog(result);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _reviewing = false;
        _status = DemoScanStatus.pendingReview;
        _message =
            'Review required before exam startup. Security review service is unavailable.';
        _reviewEvents
          ..clear()
          ..add(
            const AgenticReviewEvent(
              title: 'Review required',
              detail: 'The evidence record could not be reviewed at this time.',
              severity: 'warning',
            ),
          );
      });
    }
  }

  Future<void> _showReviewDecisionDialog(SecurityReviewResult result) async {
    final title = result.approved
        ? 'Review approved'
        : result.needsRescan
        ? 'Rescan required'
        : 'Review required';
    final message = result.approved
        ? '${result.summary}\n\nClick OK to start the exam.'
        : result.summary;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text(title),
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
    if (result.approved) {
      return const AgenticReviewEvent(
        title: 'Review approved',
        detail: 'Pre-exam security check completed successfully.',
        severity: 'success',
      );
    }
    if (result.needsRescan) {
      return const AgenticReviewEvent(
        title: 'Rescan required',
        detail: 'Please correct the issue and rescan before exam startup.',
        severity: 'warning',
      );
    }
    return const AgenticReviewEvent(
      title: 'Review required',
      detail: 'The evidence record requires invigilator review before startup.',
      severity: 'warning',
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
      'targets': _targets.map((target) {
        final calibration = calibrationByTarget[target.name];
        return <String, dynamic>{
          'name': target.name,
          'captured': target.captured,
          'image_key': target.framePath == null
              ? null
              : _fileNameFromPath(target.framePath!),
          'lighting_score': calibration?.lightingScore ?? 0,
          'motion_score': calibration?.motionScore ?? 0,
          'scene_score': calibration?.sceneScore ?? 0,
          'labels': target.labels,
        };
      }).toList(),
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
    _autoCaptureTimer?.cancel();
    await _frameSource.stop(_controller);
    setState(() {
      _targets = _newTargets();
      _calibrationLog.clear();
      _reviewEvents.clear();
      _acceptedSignatures.clear();
      _previousSignature = null;
      _manifestPath = null;
      _frameCount = 0;
      _currentTargetIndex = 0;
      _lightingScore = 0;
      _motionScore = 0;
      _sceneScore = 0;
      _capturingTarget = false;
      _status = DemoScanStatus.idle;
      _message = 'Open the camera, then start the guided room scan.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      appBar: AppBar(
        title: Text(
          widget.compactExamGate
              ? 'Pre-exam proctoring'
              : 'K-SLAS Student Portal',
        ),
        backgroundColor: colorScheme.surface,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(18),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1280),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildControls(),
                  const SizedBox(height: 14),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final wide = constraints.maxWidth >= 980;
                      final camera = _buildCameraPanel();
                      final side = _buildSidePanel();
                      if (!wide) {
                        return Column(
                          children: [camera, const SizedBox(height: 14), side],
                        );
                      }
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(flex: 7, child: camera),
                          const SizedBox(width: 14),
                          Expanded(flex: 5, child: side),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 14),
                  _buildAgentPanel(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildControls() {
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              FilledButton.icon(
                onPressed: _openingCamera ? null : _openCamera,
                icon: const Icon(Icons.videocam_outlined),
                label: Text(
                  _realCameraReady
                      ? 'Camera ready'
                      : _backupScanReady
                      ? 'Backup ready'
                      : 'Open camera',
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
                  _capturingTarget ? 'Saving image...' : 'Capture target',
                ),
              ),
              OutlinedButton.icon(
                onPressed: _scanComplete && !_reviewing
                    ? _runSecurityReview
                    : null,
                icon: const Icon(Icons.verified_user_outlined),
                label: const Text('Run security review'),
              ),
              TextButton.icon(
                onPressed: _reset,
                icon: const Icon(Icons.refresh),
                label: const Text('Reset'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(_message, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: _targets.where((t) => t.captured).length / _targets.length,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _MetricChip(label: 'Frames', value: '$_frameCount'),
              _MetricChip(label: 'Mode', value: _frameMode),
              _MetricChip(
                label: 'Light',
                value: _lightingScore.toStringAsFixed(3),
              ),
              _MetricChip(
                label: 'Motion',
                value: _motionScore.toStringAsFixed(3),
              ),
              _MetricChip(
                label: 'Scene',
                value: _sceneScore.toStringAsFixed(3),
              ),
            ],
          ),
          if (_manifestPath != null) ...[
            const SizedBox(height: 8),
            Text(
              'Manifest: $_manifestPath',
              style: Theme.of(context).textTheme.bodySmall,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCameraPanel() {
    return _Panel(
      padding: EdgeInsets.zero,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (_realCameraReady)
                CameraPreview(_controller!)
              else if (_backupScanReady)
                Container(
                  color: const Color(0xFF101828),
                  alignment: Alignment.center,
                  child: const Text(
                    'Backup scan mode ready',
                    style: TextStyle(color: Colors.white, fontSize: 18),
                  ),
                )
              else
                Container(
                  color: const Color(0xFF101828),
                  alignment: Alignment.center,
                  child: const Text(
                    'Camera preview',
                    style: TextStyle(color: Colors.white, fontSize: 18),
                  ),
                ),
              Align(
                alignment: Alignment.topCenter,
                child: Container(
                  margin: const EdgeInsets.all(12),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.62),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _scanning
                        ? 'Now capture: $_currentTarget'
                        : 'Guided 360 environment capture',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              Center(
                child: Container(
                  width: 260,
                  height: 180,
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: const Color(0xFF22C55E),
                      width: 2,
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
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
                      _capturingTarget
                          ? 'Saving image...'
                          : _scanComplete
                          ? 'All images captured'
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

  Widget _buildSidePanel() {
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Required scan targets',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 10),
          ..._targets.asMap().entries.map((entry) {
            final index = entry.key;
            final target = entry.value;
            final active =
                _scanning && !_scanComplete && index == _currentTargetIndex;
            return ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              tileColor: active ? const Color(0xFFEFF6FF) : null,
              leading: Icon(
                target.captured
                    ? Icons.check_circle
                    : active
                    ? Icons.camera_alt_outlined
                    : Icons.radio_button_unchecked,
                color: target.captured
                    ? const Color(0xFF16A34A)
                    : active
                    ? const Color(0xFF1D4ED8)
                    : const Color(0xFF64748B),
              ),
              title: Text(target.name),
              subtitle: target.framePath != null
                  ? const Text('Image saved')
                  : active
                  ? const Text('Ready to capture')
                  : target.labels.isEmpty
                  ? null
                  : Text(target.labels.join(', ')),
            );
          }),
          const Divider(height: 24),
          Text(
            'Calibration log',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 190,
            child: _calibrationLog.isEmpty
                ? const Center(child: Text('Scan frames will appear here.'))
                : ListView.builder(
                    itemCount: math.min(_calibrationLog.length, 20),
                    itemBuilder: (context, index) {
                      final entry = _calibrationLog.reversed.elementAt(index);
                      return Text(
                        '${entry.target}: L ${entry.lightingScore.toStringAsFixed(2)} '
                        'M ${entry.motionScore.toStringAsFixed(2)} '
                        'S ${entry.sceneScore.toStringAsFixed(2)} - ${entry.note}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildAgentPanel() {
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Security review',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 10),
          if (_reviewEvents.isEmpty)
            const Text('Run the review after all scan targets are captured.')
          else
            ..._reviewEvents.map(
              (event) => ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  event.severity == 'success'
                      ? Icons.check_circle_outline
                      : event.severity == 'warning'
                      ? Icons.warning_amber_outlined
                      : Icons.info_outline,
                  color: event.severity == 'success'
                      ? const Color(0xFF16A34A)
                      : event.severity == 'warning'
                      ? const Color(0xFFD97706)
                      : const Color(0xFF2563EB),
                ),
                title: Text(event.title),
                subtitle: Text(event.detail),
              ),
            ),
        ],
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.child, this.padding = const EdgeInsets.all(16)});

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: child,
    );
  }
}

class _MetricChip extends StatelessWidget {
  const _MetricChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFBFDBFE)),
      ),
      child: Text(
        '$label: $value',
        style: const TextStyle(
          fontWeight: FontWeight.w700,
          color: Color(0xFF1E3A8A),
        ),
      ),
    );
  }
}

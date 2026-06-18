import 'dart:async';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import 'agentic_ai_review_service.dart';
import 'camera_scan_frame_source.dart';
import 'demo_evidence_service.dart';
import 'proctoring_demo_models.dart';

class ProctoringDemoHome extends StatefulWidget {
  const ProctoringDemoHome({
    super.key,
    this.onApproved,
    this.compactExamGate = false,
  });

  final void Function(String? manifestPath)? onApproved;
  final bool compactExamGate;

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

  static const double _minimumSceneChangeScore = 0.032;
  static const double _minimumMotionScore = 0.018;
  static const double _minimumLightingScore = 0.20;

  final DemoCameraScanFrameSource _frameSource = DemoCameraScanFrameSource();
  final DemoEvidenceService _evidence = DemoEvidenceService();
  final AgenticAiReviewService _agent = MockAgenticAiReviewService();

  CameraController? _controller;
  List<DemoScanTarget> _targets = _newTargets();
  final List<DemoCalibrationEntry> _calibrationLog = <DemoCalibrationEntry>[];
  final List<AgenticReviewEvent> _reviewEvents = <AgenticReviewEvent>[];
  final Map<String, List<int>> _acceptedSignatures = <String, List<int>>{};

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
        _message = 'Camera is ready. Start the scan and rotate slowly.';
      });
      await previousController?.dispose();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _openingCamera = false;
        _backupScanReady = true;
        _message =
            'Camera could not open. Backup scan mode is ready. Check Windows camera privacy access and close other apps using the camera: $e';
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
      _frameCount = 0;
      _currentTargetIndex = 0;
      _frameMode = 'not-started';
      _lightingScore = 0;
      _motionScore = 0;
      _sceneScore = 0;
      _status = DemoScanStatus.scanning;
      _message =
          'Capture $_currentTarget. Move slowly until the scene changes.';
    });

    bool shouldContinue() => mounted && _scanning && !_scanComplete;
    void onStatus(String status) {
      if (!mounted) return;
      setState(() => _frameMode = status);
    }
    if (controller != null && controller.value.isInitialized) {
      await _frameSource.start(
        controller: controller,
        shouldContinue: shouldContinue,
        onFrame: _handleFrame,
        onStatus: onStatus,
      );
    } else {
      await _frameSource.startFallback(
        shouldContinue: shouldContinue,
        onFrame: _handleFrame,
        onStatus: onStatus,
      );
    }
  }

  Future<void> _handleFrame(DemoCameraScanFrame frame) async {
    if (!_scanning || _scanComplete) return;
    final target = _currentTarget;
    final previous = _previousSignature;
    final motion = previous == null
        ? 1.0
        : _signatureDifference(previous, frame.signature);
    final scene = _sceneDiversityScore(frame.signature);
    final labels = _demoLabelsFor(frame);
    final enoughLight = frame.luma >= _minimumLightingScore;
    final firstTarget = _acceptedSignatures.isEmpty;
    final enoughMotion = firstTarget || motion >= _minimumMotionScore;
    final uniqueScene = firstTarget || scene >= _minimumSceneChangeScore;

    _previousSignature = List<int>.from(frame.signature);
    _frameCount++;

    if (!enoughLight || !enoughMotion || !uniqueScene) {
      final note = !enoughLight
          ? 'Need more light before this target can pass.'
          : !enoughMotion
          ? 'Camera has not moved enough for this target.'
          : 'This scene looks too similar to a previous accepted target.';
      _addCalibrationEntry(
        target: target,
        frame: frame,
        motion: motion,
        scene: scene,
        labels: labels,
        note: note,
      );
      if (!mounted) return;
      setState(() {
        _lightingScore = frame.luma;
        _motionScore = motion;
        _sceneScore = scene;
        _message = note;
      });
      return;
    }

    final framePath = await _evidence.saveTargetFrame(
      target: target,
      decodedImage: frame.decodedImage,
      cameraImage: frame.cameraImage,
    );
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
      note: 'Accepted and saved evidence frame.',
      framePath: framePath,
    );

    if (_scanComplete) {
      await _frameSource.stop(_controller);
      final manifest = await _saveManifest('scan_complete');
      if (!mounted) return;
      setState(() {
        _status = DemoScanStatus.passed;
        _manifestPath = manifest;
        _message = 'Room scan complete. Run the security review.';
      });
      return;
    }

    if (!mounted) return;
    setState(() {
      _currentTargetIndex++;
      _lightingScore = frame.luma;
      _motionScore = motion;
      _sceneScore = scene;
      _message = 'Accepted $target. Now capture $_currentTarget.';
    });
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
    if (frame.luma < 0.18) labels.add('dark room');
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

  Future<void> _runAgenticReview() async {
    if (_reviewing) return;
    setState(() {
      _reviewing = true;
      _reviewEvents.clear();
      _message = 'Security review is running...';
    });

    await for (final event in _agent.review(
      targets: _targets,
      calibrationLog: _calibrationLog,
    )) {
      if (!mounted) return;
      setState(() => _reviewEvents.add(event));
    }

    final last = _reviewEvents.isEmpty ? null : _reviewEvents.last;
    final decision = last?.severity == 'success' ? 'ready' : 'pending_review';
    final manifest = await _saveManifest(decision);
    if (!mounted) return;
    setState(() {
      _reviewing = false;
      _manifestPath = manifest;
      _status = decision == 'ready'
          ? DemoScanStatus.passed
          : DemoScanStatus.pendingReview;
      _message = decision == 'ready'
          ? 'Security review approved. Exam can start.'
          : 'Security review needs correction or human review.';
    });
    if (decision == 'ready' && widget.onApproved != null) {
      widget.onApproved!(manifest);
    }
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
      _frameCount = 0;
      _currentTargetIndex = 0;
      _lightingScore = 0;
      _motionScore = 0;
      _sceneScore = 0;
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
              OutlinedButton.icon(
                onPressed: _scanComplete && !_reviewing
                    ? _runAgenticReview
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
          ..._targets.map(
            (target) => ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                target.captured
                    ? Icons.check_circle
                    : Icons.radio_button_unchecked,
                color: target.captured
                    ? const Color(0xFF16A34A)
                    : const Color(0xFF64748B),
              ),
              title: Text(target.name),
              subtitle: target.labels.isEmpty
                  ? null
                  : Text(target.labels.join(', ')),
            ),
          ),
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

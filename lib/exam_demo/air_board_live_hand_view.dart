import 'dart:async';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../proctoring_demo/camera_runtime_coordinator.dart';
import '../rust/api/air_board.dart' as rust_air;
import '../rust/api/hand_air_board.dart' as rust_hand;
import '../rust/api/hand_vision.dart' as rust_vision;

const Color _brand = Color(0xFF0F4C81);
const Color _ink = Color(0xFF0B1220);
const Color _muted = Color(0xFF64748B);
const Color _line = Color(0xFFE2E8F0);
const Color _surface = Colors.white;
const Color _background = Color(0xFFF4F7FB);

class AirBoardLiveHandView extends StatefulWidget {
  const AirBoardLiveHandView({super.key});

  @override
  State<AirBoardLiveHandView> createState() => _AirBoardLiveHandViewState();
}

class _AirBoardLiveHandViewState extends State<AirBoardLiveHandView> {
  static const String _cameraOwner = 'air_board_live_hand';
  static const Duration _inferenceInterval = Duration(milliseconds: 800);

  final DateTime _openedAt = DateTime.now();
  final CameraRuntimeCoordinator _cameraRuntime =
      CameraRuntimeCoordinator.instance;
  final List<_BoardStroke> _strokes = <_BoardStroke>[];

  CameraController? _camera;
  _BoardStroke? _activeStroke;
  bool _ownsCameraLease = false;
  bool _openingCamera = false;
  bool _streaming = false;
  bool _processingFrame = false;
  bool _modelLoaded = false;
  DateTime? _lastInferenceAt;
  DateTime? _lastBoardActivityAt;
  String _cameraStatus = 'Preparing local hand monitor...';
  String _modelStatus = 'Loading local hand model...';
  rust_vision.HandVisionResult? _handVisionResult;
  late rust_air.AirBoardActivitySummary _airSummary;
  late rust_hand.HandAirBoardDecision _handDecision;
  int _strokeCounter = 0;

  @override
  void initState() {
    super.initState();
    _airSummary = _analyzeBoard();
    _handDecision = _analyzeHandAndBoard(_fallbackHandSignal());
    unawaited(_initializeLocalHandVision());
  }

  @override
  void dispose() {
    final camera = _camera;
    _camera = null;
    if (camera != null) {
      unawaited(_stopAndDisposeCamera(camera));
    }
    if (_ownsCameraLease) {
      _cameraRuntime.release(_cameraOwner);
    }
    super.dispose();
  }

  Future<void> _initializeLocalHandVision() async {
    try {
      final manifest = await rootBundle.loadString(
        'assets/models/hand_vision/manifest.json',
      );
      final modelData = await rootBundle.load(
        'assets/models/hand_vision/hand_detector.onnx',
      );
      final modelBytes = modelData.buffer.asUint8List(
        modelData.offsetInBytes,
        modelData.lengthInBytes,
      );
      final status = rust_vision.loadHandVisionModel(
        manifestJson: manifest,
        modelBytes: modelBytes,
      );
      if (!mounted) return;
      setState(() {
        _modelLoaded = status.loaded;
        _modelStatus = status.loaded
            ? '${status.modelName} ready (${status.inputWidth}×${status.inputHeight})'
            : status.message;
      });
      if (status.loaded) {
        await _startCameraAndStream();
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _modelLoaded = false;
        _modelStatus = 'Local hand model could not load: $error';
      });
    }
  }

  Future<void> _startCameraAndStream() async {
    if (_openingCamera || _camera != null) return;
    final lease = _cameraRuntime.tryAcquire(
      owner: _cameraOwner,
      purpose: 'air_board_live_hand_inference',
    );
    if (lease == null) {
      if (!mounted) return;
      final owner = _cameraRuntime.activeLease?.owner ?? 'live monitoring';
      setState(() {
        _cameraStatus =
            'The camera is already being used by $owner. The shared camera stream must be connected before live hand inference can run here.';
      });
      return;
    }

    _ownsCameraLease = true;
    setState(() {
      _openingCamera = true;
      _cameraStatus = 'Opening front camera...';
    });

    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        throw StateError('No camera was found.');
      }
      final selected = cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        selected,
        ResolutionPreset.low,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      _camera = controller;
      setState(() {
        _cameraStatus = 'Camera ready. Starting local hand detection...';
      });

      await controller.startImageStream(_onCameraImage);
      if (!mounted) return;
      setState(() {
        _streaming = true;
        _cameraStatus = 'Local hand detection active';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _cameraStatus = 'Camera hand detection could not start: $error';
      });
    } finally {
      if (mounted) {
        setState(() => _openingCamera = false);
      }
    }
  }

  Future<void> _onCameraImage(CameraImage image) async {
    if (!_modelLoaded || _processingFrame) return;
    final now = DateTime.now();
    final last = _lastInferenceAt;
    if (last != null && now.difference(last) < _inferenceInterval) return;

    _processingFrame = true;
    _lastInferenceAt = now;
    try {
      final rgb = _cameraImageToRgb(image);
      if (rgb == null) {
        if (mounted) {
          setState(() {
            _cameraStatus =
                'Camera format ${image.format.group.name} is not supported for hand inference yet.';
          });
        }
        return;
      }

      final result = rust_vision.analyzeHandRgbFrame(
        rgbBytes: rgb,
        imageWidth: image.width,
        imageHeight: image.height,
        zones: const rust_vision.HandVisionZones(
          keyboardYMin: 0.66,
          stylusXMin: 0.15,
          stylusXMax: 0.88,
          stylusYMin: 0.58,
          faceXMin: 0.28,
          faceXMax: 0.72,
          faceYMin: 0.08,
          faceYMax: 0.52,
          deskLineY: 0.94,
        ),
        timestampMs: now.millisecondsSinceEpoch,
      );
      if (!mounted) return;
      setState(() {
        _handVisionResult = result;
        _handDecision = _analyzeHandAndBoard(result.signal);
        _cameraStatus = result.usable
            ? 'Local hand detection active'
            : result.reason;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _cameraStatus = 'Local hand inference error: $error';
      });
    } finally {
      _processingFrame = false;
    }
  }

  Uint8List? _cameraImageToRgb(CameraImage image) {
    switch (image.format.group) {
      case ImageFormatGroup.bgra8888:
        return _bgraToRgb(image);
      case ImageFormatGroup.yuv420:
        return _yuv420ToRgb(image);
      case ImageFormatGroup.nv21:
        return _nv21ToRgb(image);
      default:
        return null;
    }
  }

  Uint8List? _bgraToRgb(CameraImage image) {
    if (image.planes.isEmpty) return null;
    final plane = image.planes.first;
    final bytes = plane.bytes;
    final rowStride = plane.bytesPerRow;
    final rgb = Uint8List(image.width * image.height * 3);
    var output = 0;
    for (var y = 0; y < image.height; y++) {
      final row = y * rowStride;
      for (var x = 0; x < image.width; x++) {
        final index = row + x * 4;
        if (index + 2 >= bytes.length) return null;
        rgb[output++] = bytes[index + 2];
        rgb[output++] = bytes[index + 1];
        rgb[output++] = bytes[index];
      }
    }
    return rgb;
  }

  Uint8List? _yuv420ToRgb(CameraImage image) {
    if (image.planes.length < 3) return null;
    final yPlane = image.planes[0];
    final uPlane = image.planes[1];
    final vPlane = image.planes[2];
    final uvPixelStride = uPlane.bytesPerPixel ?? 1;
    final rgb = Uint8List(image.width * image.height * 3);
    var output = 0;

    for (var y = 0; y < image.height; y++) {
      final yRow = y * yPlane.bytesPerRow;
      final uvRow = (y >> 1) * uPlane.bytesPerRow;
      for (var x = 0; x < image.width; x++) {
        final yIndex = yRow + x;
        final uvIndex = uvRow + (x >> 1) * uvPixelStride;
        if (yIndex >= yPlane.bytes.length ||
            uvIndex >= uPlane.bytes.length ||
            uvIndex >= vPlane.bytes.length) {
          return null;
        }
        final yValue = yPlane.bytes[yIndex];
        final uValue = uPlane.bytes[uvIndex] - 128;
        final vValue = vPlane.bytes[uvIndex] - 128;
        final r = (yValue + 1.402 * vValue).round().clamp(0, 255);
        final g =
            (yValue - 0.344136 * uValue - 0.714136 * vValue)
                .round()
                .clamp(0, 255);
        final b = (yValue + 1.772 * uValue).round().clamp(0, 255);
        rgb[output++] = r;
        rgb[output++] = g;
        rgb[output++] = b;
      }
    }
    return rgb;
  }

  Uint8List? _nv21ToRgb(CameraImage image) {
    if (image.planes.length < 2) return null;
    final yPlane = image.planes[0];
    final vuPlane = image.planes[1];
    final rgb = Uint8List(image.width * image.height * 3);
    var output = 0;
    for (var y = 0; y < image.height; y++) {
      for (var x = 0; x < image.width; x++) {
        final yIndex = y * yPlane.bytesPerRow + x;
        final vuIndex =
            (y >> 1) * vuPlane.bytesPerRow + (x >> 1) * 2;
        if (yIndex >= yPlane.bytes.length || vuIndex + 1 >= vuPlane.bytes.length) {
          return null;
        }
        final yValue = yPlane.bytes[yIndex];
        final vValue = vuPlane.bytes[vuIndex] - 128;
        final uValue = vuPlane.bytes[vuIndex + 1] - 128;
        final r = (yValue + 1.402 * vValue).round().clamp(0, 255);
        final g =
            (yValue - 0.344136 * uValue - 0.714136 * vValue)
                .round()
                .clamp(0, 255);
        final b = (yValue + 1.772 * uValue).round().clamp(0, 255);
        rgb[output++] = r;
        rgb[output++] = g;
        rgb[output++] = b;
      }
    }
    return rgb;
  }

  void _startStroke(Offset point) {
    final now = DateTime.now();
    setState(() {
      _activeStroke = _BoardStroke(
        id: 'stroke-${++_strokeCounter}',
        startedAt: now,
        endedAt: now,
        points: <_BoardPoint>[_BoardPoint(point, now)],
      );
      _lastBoardActivityAt = now;
      _refreshBoardDecision();
    });
  }

  void _appendStroke(Offset point) {
    final stroke = _activeStroke;
    if (stroke == null) return;
    final now = DateTime.now();
    setState(() {
      stroke.points.add(_BoardPoint(point, now));
      stroke.endedAt = now;
      _lastBoardActivityAt = now;
      _refreshBoardDecision();
    });
  }

  void _finishStroke() {
    final stroke = _activeStroke;
    setState(() {
      if (stroke != null && stroke.points.length > 1) {
        _strokes.add(stroke);
      }
      _activeStroke = null;
      _lastBoardActivityAt = DateTime.now();
      _refreshBoardDecision();
    });
  }

  void _undo() {
    if (_strokes.isEmpty) return;
    setState(() {
      _strokes.removeLast();
      _lastBoardActivityAt = DateTime.now();
      _refreshBoardDecision();
    });
  }

  void _clear() {
    setState(() {
      _strokes.clear();
      _activeStroke = null;
      _lastBoardActivityAt = DateTime.now();
      _refreshBoardDecision();
    });
  }

  void _refreshBoardDecision() {
    _airSummary = _analyzeBoard();
    _handDecision = _analyzeHandAndBoard(
      _handVisionResult?.signal ?? _fallbackHandSignal(),
    );
  }

  rust_air.AirBoardActivitySummary _analyzeBoard() {
    final now = DateTime.now();
    final strokes = <_BoardStroke>[
      ..._strokes,
      if (_activeStroke != null) _activeStroke!,
    ];
    return rust_air.analyzeAirBoardContext(
      context: rust_air.AirBoardContext(
        isOpen: true,
        activePageIndex: 0,
        pageCount: 1,
        strokes: strokes.map(_toRustStroke).toList(growable: false),
        lastActivityAtMs:
            (_lastBoardActivityAt ?? _openedAt).millisecondsSinceEpoch,
        openedAtMs: _openedAt.millisecondsSinceEpoch,
        nowMs: now.millisecondsSinceEpoch,
      ),
    );
  }

  rust_hand.HandAirBoardDecision _analyzeHandAndBoard(
    rust_hand.HandRegionSignal signal,
  ) {
    return rust_hand.analyzeHandAirBoardContext(
      context: rust_hand.HandAirBoardContext(
        airBoard: _airSummary,
        hand: signal,
        gazeZone: _airSummary.currentlyWriting ? 'air_board' : 'answer_area',
        screenZone: 'air_board',
        nowMs: DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }

  rust_air.AirBoardStroke _toRustStroke(_BoardStroke stroke) {
    return rust_air.AirBoardStroke(
      strokeId: stroke.id,
      pageIndex: 0,
      tool: 'pen',
      points: stroke.points
          .map(
            (point) => rust_air.AirBoardStrokePoint(
              x: point.offset.dx,
              y: point.offset.dy,
              pressure: 1,
              timestampMs: point.timestamp.millisecondsSinceEpoch,
            ),
          )
          .toList(growable: false),
      startedAtMs: stroke.startedAt.millisecondsSinceEpoch,
      endedAtMs: stroke.endedAt.millisecondsSinceEpoch,
    );
  }

  rust_hand.HandRegionSignal _fallbackHandSignal() {
    return rust_hand.HandRegionSignal(
      handVisible: false,
      handCount: 0,
      primaryHandX: 0,
      primaryHandY: 0,
      handConfidence: 0,
      nearKeyboard: false,
      nearMouseOrStylusArea: false,
      nearFace: false,
      belowDeskLine: false,
      timestampMs: DateTime.now().millisecondsSinceEpoch,
    );
  }

  Future<void> _stopAndDisposeCamera(CameraController camera) async {
    try {
      if (camera.value.isStreamingImages) {
        await camera.stopImageStream();
      }
    } catch (_) {}
    await camera.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final handResult = _handVisionResult;
    final camera = _camera;
    final cameraReady = camera != null && camera.value.isInitialized;
    return Scaffold(
      backgroundColor: _background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        title: const Text(
          'Rough-work board',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        actions: [
          TextButton.icon(
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.close_rounded),
            label: const Text('Close'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(18),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1180),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _StatusHeader(
                      modelStatus: _modelStatus,
                      cameraStatus: _cameraStatus,
                      decision: _handDecision,
                    ),
                    const SizedBox(height: 14),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final wide = constraints.maxWidth >= 850;
                        final cameraPanel = _CameraHandPanel(
                          camera: cameraReady ? camera : null,
                          opening: _openingCamera,
                          streaming: _streaming,
                          processing: _processingFrame,
                          result: handResult,
                          decision: _handDecision,
                        );
                        final board = _DrawingBoard(
                          strokes: _strokes,
                          activeStroke: _activeStroke,
                          onStart: _startStroke,
                          onMove: _appendStroke,
                          onEnd: _finishStroke,
                          onUndo: _undo,
                          onClear: _clear,
                        );
                        if (!wide) {
                          return Column(
                            children: [
                              cameraPanel,
                              const SizedBox(height: 14),
                              board,
                            ],
                          );
                        }
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(width: 350, child: cameraPanel),
                            const SizedBox(width: 14),
                            Expanded(child: board),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 14),
                    _EvidencePanel(
                      airSummary: _airSummary,
                      handResult: handResult,
                      decision: _handDecision,
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
}

class _StatusHeader extends StatelessWidget {
  const _StatusHeader({
    required this.modelStatus,
    required this.cameraStatus,
    required this.decision,
  });

  final String modelStatus;
  final String cameraStatus;
  final rust_hand.HandAirBoardDecision decision;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [_ink, Color(0xFF113A63), _brand],
        ),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Local camera-assisted rough work',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 22,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            decision.studentMessage,
            style: const TextStyle(
              color: Color(0xFFE2E8F0),
              fontWeight: FontWeight.w600,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _DarkTag(modelStatus),
              _DarkTag(cameraStatus),
              _DarkTag(_friendlyLevel(decision.attentionLevel)),
            ],
          ),
        ],
      ),
    );
  }
}

class _CameraHandPanel extends StatelessWidget {
  const _CameraHandPanel({
    required this.camera,
    required this.opening,
    required this.streaming,
    required this.processing,
    required this.result,
    required this.decision,
  });

  final CameraController? camera;
  final bool opening;
  final bool streaming;
  final bool processing;
  final rust_vision.HandVisionResult? result;
  final rust_hand.HandAirBoardDecision decision;

  @override
  Widget build(BuildContext context) {
    final signal = result?.signal;
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Camera hand monitor',
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17),
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: AspectRatio(
              aspectRatio: 4 / 3,
              child: Container(
                color: _ink,
                child: camera == null
                    ? Center(
                        child: Icon(
                          opening
                              ? Icons.hourglass_top_rounded
                              : Icons.videocam_off_outlined,
                          color: Colors.white,
                          size: 36,
                        ),
                      )
                    : CameraPreview(camera!),
              ),
            ),
          ),
          const SizedBox(height: 12),
          _Metric('Stream', streaming ? 'Active' : 'Not active'),
          _Metric('Inference', processing ? 'Processing' : 'Ready'),
          _Metric('Hands', '${signal?.handCount ?? 0}'),
          _Metric(
            'Confidence',
            '${(((signal?.handConfidence ?? 0) * 100).round())}%',
          ),
          _Metric(
            'Work-area match',
            decision.handMatchesAirBoard ? 'Matched' : 'Not confirmed',
          ),
          if (result != null) ...[
            const SizedBox(height: 8),
            Text(
              result!.reason,
              style: const TextStyle(
                color: _muted,
                height: 1.35,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _DrawingBoard extends StatelessWidget {
  const _DrawingBoard({
    required this.strokes,
    required this.activeStroke,
    required this.onStart,
    required this.onMove,
    required this.onEnd,
    required this.onUndo,
    required this.onClear,
  });

  final List<_BoardStroke> strokes;
  final _BoardStroke? activeStroke;
  final ValueChanged<Offset> onStart;
  final ValueChanged<Offset> onMove;
  final VoidCallback onEnd;
  final VoidCallback onUndo;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Digital rough work',
                      style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'Use mouse, touchscreen, or stylus.',
                      style: TextStyle(color: _muted, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Undo',
                onPressed: onUndo,
                icon: const Icon(Icons.undo_rounded),
              ),
              IconButton(
                tooltip: 'Clear',
                onPressed: onClear,
                icon: const Icon(Icons.delete_outline_rounded),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: AspectRatio(
              aspectRatio: 16 / 10,
              child: Listener(
                onPointerDown: (event) => onStart(event.localPosition),
                onPointerMove: (event) => onMove(event.localPosition),
                onPointerUp: (_) => onEnd(),
                onPointerCancel: (_) => onEnd(),
                child: CustomPaint(
                  painter: _BoardPainter(
                    strokes: strokes,
                    activeStroke: activeStroke,
                  ),
                  child: const SizedBox.expand(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EvidencePanel extends StatelessWidget {
  const _EvidencePanel({
    required this.airSummary,
    required this.handResult,
    required this.decision,
  });

  final rust_air.AirBoardActivitySummary airSummary;
  final rust_vision.HandVisionResult? handResult;
  final rust_hand.HandAirBoardDecision decision;

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Wrap(
        spacing: 24,
        runSpacing: 12,
        children: [
          _Metric('Board strokes', '${airSummary.strokeCount}'),
          _Metric('Board points', '${airSummary.totalPoints}'),
          _Metric(
            'Writing now',
            airSummary.currentlyWriting ? 'Yes' : 'No',
          ),
          _Metric('Hand detections', '${handResult?.detections.length ?? 0}'),
          _Metric('Hand state', decision.behaviourLabel.replaceAll('_', ' ')),
          _Metric('Review', decision.reviewRequired ? 'Required' : 'Normal'),
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _line),
        boxShadow: const [
          BoxShadow(
            color: Color(0x080F172A),
            blurRadius: 18,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _DarkTag extends StatelessWidget {
  const _DarkTag(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 420),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
      ),
      child: Text(
        text,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$label: ',
            style: const TextStyle(color: _muted, fontWeight: FontWeight.w700),
          ),
          Flexible(
            child: Text(
              value,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: _ink, fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
    );
  }
}

class _BoardPainter extends CustomPainter {
  const _BoardPainter({
    required this.strokes,
    required this.activeStroke,
  });

  final List<_BoardStroke> strokes;
  final _BoardStroke? activeStroke;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.white);
    final grid = Paint()
      ..color = _line
      ..strokeWidth = 1;
    for (var x = 32.0; x < size.width; x += 32) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
    }
    for (var y = 32.0; y < size.height; y += 32) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    for (final stroke in strokes) {
      _paintStroke(canvas, stroke);
    }
    final active = activeStroke;
    if (active != null) _paintStroke(canvas, active);
  }

  void _paintStroke(Canvas canvas, _BoardStroke stroke) {
    if (stroke.points.length < 2) return;
    final paint = Paint()
      ..color = _ink
      ..strokeWidth = 3.2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    final path = Path()
      ..moveTo(stroke.points.first.offset.dx, stroke.points.first.offset.dy);
    for (var index = 1; index < stroke.points.length; index++) {
      final previous = stroke.points[index - 1].offset;
      final current = stroke.points[index].offset;
      final midpoint = Offset(
        (previous.dx + current.dx) / 2,
        (previous.dy + current.dy) / 2,
      );
      path.quadraticBezierTo(
        previous.dx,
        previous.dy,
        midpoint.dx,
        midpoint.dy,
      );
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _BoardPainter oldDelegate) => true;
}

class _BoardStroke {
  _BoardStroke({
    required this.id,
    required this.points,
    required this.startedAt,
    required this.endedAt,
  });

  final String id;
  final List<_BoardPoint> points;
  final DateTime startedAt;
  DateTime endedAt;
}

class _BoardPoint {
  const _BoardPoint(this.offset, this.timestamp);

  final Offset offset;
  final DateTime timestamp;
}

String _friendlyLevel(String level) {
  switch (level) {
    case 'normal':
      return 'Normal';
    case 'medium_attention_required':
      return 'Attention needed';
    case 'high_attention_required':
      return 'Review needed';
    case 'urgent_review_required':
      return 'Urgent review';
    default:
      return level.replaceAll('_', ' ');
  }
}

import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../proctoring_demo/camera_runtime_coordinator.dart';
import '../rust/api/air_board.dart' as rust_air;
import '../rust/api/hand_air_board.dart' as rust_hand;
import '../rust/api/hand_vision.dart' as rust_vision;

const _brand = Color(0xFF0F4C81);
const _ink = Color(0xFF0B1220);
const _muted = Color(0xFF64748B);
const _line = Color(0xFFE2E8F0);
const _page = Color(0xFFF4F7FB);

class AirBoardLiveHandView extends StatefulWidget {
  const AirBoardLiveHandView({super.key});

  @override
  State<AirBoardLiveHandView> createState() => _AirBoardLiveHandViewState();
}

class _AirBoardLiveHandViewState extends State<AirBoardLiveHandView> {
  static const _owner = 'air_board_live_hand';
  static const _interval = Duration(milliseconds: 800);

  final _openedAt = DateTime.now();
  final _cameraRuntime = CameraRuntimeCoordinator.instance;
  final List<_Stroke> _strokes = [];

  CameraController? _camera;
  _Stroke? _activeStroke;
  rust_vision.HandVisionResult? _handResult;
  late rust_air.AirBoardActivitySummary _boardSummary;
  late rust_hand.HandAirBoardDecision _decision;

  bool _ownsLease = false;
  bool _opening = false;
  bool _streaming = false;
  bool _processing = false;
  bool _modelLoaded = false;
  DateTime? _lastInference;
  DateTime? _lastBoardActivity;
  int _strokeId = 0;
  String _modelStatus = 'Loading local hand model...';
  String _cameraStatus = 'Preparing camera...';

  @override
  void initState() {
    super.initState();
    _refreshDecision();
    unawaited(_initialize());
  }

  @override
  void dispose() {
    final camera = _camera;
    _camera = null;
    if (camera != null) unawaited(_disposeCamera(camera));
    if (_ownsLease) _cameraRuntime.release(_owner);
    super.dispose();
  }

  Future<void> _initialize() async {
    try {
      final manifest = await rootBundle.loadString(
        'assets/models/hand_vision/manifest.json',
      );
      final data = await rootBundle.load(
        'assets/models/hand_vision/hand_detector.onnx',
      );
      final bytes = data.buffer.asUint8List(
        data.offsetInBytes,
        data.lengthInBytes,
      );
      final status = rust_vision.loadHandVisionModel(
        manifestJson: manifest,
        modelBytes: bytes,
      );
      if (!mounted) return;
      setState(() {
        _modelLoaded = status.loaded;
        _modelStatus = status.loaded
            ? '${status.modelName} ready (${status.inputWidth}×${status.inputHeight})'
            : status.message;
      });
      if (status.loaded) await _openCamera();
    } catch (error) {
      if (!mounted) return;
      setState(() => _modelStatus = 'Hand model could not load: $error');
    }
  }

  Future<void> _openCamera() async {
    if (_opening || _camera != null) return;
    final lease = _cameraRuntime.tryAcquire(
      owner: _owner,
      purpose: 'air_board_live_hand_inference',
    );
    if (lease == null) {
      if (!mounted) return;
      final active = _cameraRuntime.activeLease?.owner ?? 'live monitoring';
      setState(() {
        _cameraStatus =
            'Camera is already active for $active. Connect this screen to the shared monitoring stream to run hand inference.';
      });
      return;
    }

    _ownsLease = true;
    setState(() {
      _opening = true;
      _cameraStatus = 'Opening front camera...';
    });

    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) throw StateError('No camera was found.');
      final selected = cameras.firstWhere(
        (item) => item.lensDirection == CameraLensDirection.front,
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
      await controller.startImageStream(_onFrame);
      if (!mounted) return;
      setState(() {
        _streaming = true;
        _cameraStatus = 'Local hand detection active';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _cameraStatus = 'Camera stream could not start: $error');
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  Future<void> _onFrame(CameraImage image) async {
    if (!_modelLoaded || _processing) return;
    final now = DateTime.now();
    if (_lastInference != null &&
        now.difference(_lastInference!) < _interval) {
      return;
    }
    _lastInference = now;
    _processing = true;

    try {
      final rgb = _toRgb(image);
      if (rgb == null) {
        if (mounted) {
          setState(() {
            _cameraStatus =
                'Unsupported camera format: ${image.format.group.name}';
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
        _handResult = result;
        _decision = _analyzeHand(result.signal);
        _cameraStatus = result.usable
            ? 'Local hand detection active'
            : result.reason;
      });
    } catch (error) {
      if (mounted) {
        setState(() => _cameraStatus = 'Hand inference error: $error');
      }
    } finally {
      _processing = false;
    }
  }

  Uint8List? _toRgb(CameraImage image) {
    switch (image.format.group) {
      case ImageFormatGroup.bgra8888:
        return _bgraToRgb(image);
      case ImageFormatGroup.yuv420:
        return _yuvToRgb(image);
      case ImageFormatGroup.nv21:
        return _nv21ToRgb(image);
      default:
        return null;
    }
  }

  Uint8List? _bgraToRgb(CameraImage image) {
    if (image.planes.isEmpty) return null;
    final plane = image.planes.first;
    final rgb = Uint8List(image.width * image.height * 3);
    var out = 0;
    for (var y = 0; y < image.height; y++) {
      final row = y * plane.bytesPerRow;
      for (var x = 0; x < image.width; x++) {
        final i = row + x * 4;
        if (i + 2 >= plane.bytes.length) return null;
        rgb[out++] = plane.bytes[i + 2];
        rgb[out++] = plane.bytes[i + 1];
        rgb[out++] = plane.bytes[i];
      }
    }
    return rgb;
  }

  Uint8List? _yuvToRgb(CameraImage image) {
    if (image.planes.length < 3) return null;
    final yp = image.planes[0];
    final up = image.planes[1];
    final vp = image.planes[2];
    final pixelStride = up.bytesPerPixel ?? 1;
    final rgb = Uint8List(image.width * image.height * 3);
    var out = 0;

    for (var y = 0; y < image.height; y++) {
      final yRow = y * yp.bytesPerRow;
      final uvRow = (y >> 1) * up.bytesPerRow;
      for (var x = 0; x < image.width; x++) {
        final yi = yRow + x;
        final uvi = uvRow + (x >> 1) * pixelStride;
        if (yi >= yp.bytes.length ||
            uvi >= up.bytes.length ||
            uvi >= vp.bytes.length) {
          return null;
        }
        _writeRgb(
          rgb,
          out,
          yp.bytes[yi],
          up.bytes[uvi] - 128,
          vp.bytes[uvi] - 128,
        );
        out += 3;
      }
    }
    return rgb;
  }

  Uint8List? _nv21ToRgb(CameraImage image) {
    if (image.planes.length < 2) return null;
    final yp = image.planes[0];
    final vup = image.planes[1];
    final rgb = Uint8List(image.width * image.height * 3);
    var out = 0;

    for (var y = 0; y < image.height; y++) {
      for (var x = 0; x < image.width; x++) {
        final yi = y * yp.bytesPerRow + x;
        final vui = (y >> 1) * vup.bytesPerRow + (x >> 1) * 2;
        if (yi >= yp.bytes.length || vui + 1 >= vup.bytes.length) {
          return null;
        }
        _writeRgb(
          rgb,
          out,
          yp.bytes[yi],
          vup.bytes[vui + 1] - 128,
          vup.bytes[vui] - 128,
        );
        out += 3;
      }
    }
    return rgb;
  }

  void _writeRgb(Uint8List target, int offset, int y, int u, int v) {
    target[offset] =
        (y + 1.402 * v).round().clamp(0, 255).toInt();
    target[offset + 1] =
        (y - 0.344136 * u - 0.714136 * v)
            .round()
            .clamp(0, 255)
            .toInt();
    target[offset + 2] =
        (y + 1.772 * u).round().clamp(0, 255).toInt();
  }

  void _startStroke(Offset offset) {
    final now = DateTime.now();
    setState(() {
      _activeStroke = _Stroke(
        id: 'stroke-${++_strokeId}',
        points: [_Point(offset, now)],
        startedAt: now,
        endedAt: now,
      );
      _lastBoardActivity = now;
      _refreshDecision();
    });
  }

  void _appendStroke(Offset offset) {
    final stroke = _activeStroke;
    if (stroke == null) return;
    final now = DateTime.now();
    setState(() {
      stroke.points.add(_Point(offset, now));
      stroke.endedAt = now;
      _lastBoardActivity = now;
      _refreshDecision();
    });
  }

  void _finishStroke() {
    final stroke = _activeStroke;
    setState(() {
      if (stroke != null && stroke.points.length > 1) _strokes.add(stroke);
      _activeStroke = null;
      _lastBoardActivity = DateTime.now();
      _refreshDecision();
    });
  }

  void _undo() {
    if (_strokes.isEmpty) return;
    setState(() {
      _strokes.removeLast();
      _lastBoardActivity = DateTime.now();
      _refreshDecision();
    });
  }

  void _clear() {
    setState(() {
      _strokes.clear();
      _activeStroke = null;
      _lastBoardActivity = DateTime.now();
      _refreshDecision();
    });
  }

  void _refreshDecision() {
    _boardSummary = _analyzeBoard();
    _decision = _analyzeHand(_handResult?.signal ?? _emptyHand());
  }

  rust_air.AirBoardActivitySummary _analyzeBoard() {
    final now = DateTime.now();
    final all = <_Stroke>[..._strokes, if (_activeStroke != null) _activeStroke!];
    return rust_air.analyzeAirBoardContext(
      context: rust_air.AirBoardContext(
        isOpen: true,
        activePageIndex: 0,
        pageCount: 1,
        strokes: all.map(_toRustStroke).toList(growable: false),
        lastActivityAtMs:
            (_lastBoardActivity ?? _openedAt).millisecondsSinceEpoch,
        openedAtMs: _openedAt.millisecondsSinceEpoch,
        nowMs: now.millisecondsSinceEpoch,
      ),
    );
  }

  rust_hand.HandAirBoardDecision _analyzeHand(
    rust_hand.HandRegionSignal signal,
  ) {
    return rust_hand.analyzeHandAirBoardContext(
      context: rust_hand.HandAirBoardContext(
        airBoard: _boardSummary,
        hand: signal,
        gazeZone: _boardSummary.currentlyWriting ? 'air_board' : 'answer_area',
        screenZone: 'air_board',
        nowMs: DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }

  rust_air.AirBoardStroke _toRustStroke(_Stroke stroke) {
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
              timestampMs: point.at.millisecondsSinceEpoch,
            ),
          )
          .toList(growable: false),
      startedAtMs: stroke.startedAt.millisecondsSinceEpoch,
      endedAtMs: stroke.endedAt.millisecondsSinceEpoch,
    );
  }

  rust_hand.HandRegionSignal _emptyHand() => rust_hand.HandRegionSignal(
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

  Future<void> _disposeCamera(CameraController camera) async {
    try {
      if (camera.value.isStreamingImages) await camera.stopImageStream();
    } catch (_) {}
    await camera.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final camera = _camera;
    final cameraReady = camera != null && camera.value.isInitialized;
    final signal = _handResult?.signal;

    return Scaffold(
      backgroundColor: _page,
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
                    _Header(
                      modelStatus: _modelStatus,
                      cameraStatus: _cameraStatus,
                      decision: _decision,
                    ),
                    const SizedBox(height: 14),
                    LayoutBuilder(
                      builder: (context, box) {
                        final cameraPanel = _CameraPanel(
                          camera: cameraReady ? camera : null,
                          opening: _opening,
                          streaming: _streaming,
                          processing: _processing,
                          signal: signal,
                          resultReason: _handResult?.reason,
                          decision: _decision,
                        );
                        final board = _Board(
                          strokes: _strokes,
                          active: _activeStroke,
                          onStart: _startStroke,
                          onMove: _appendStroke,
                          onEnd: _finishStroke,
                          onUndo: _undo,
                          onClear: _clear,
                        );
                        if (box.maxWidth < 850) {
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
                    _Evidence(
                      board: _boardSummary,
                      handResult: _handResult,
                      decision: _decision,
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

class _Header extends StatelessWidget {
  const _Header({
    required this.modelStatus,
    required this.cameraStatus,
    required this.decision,
  });

  final String modelStatus;
  final String cameraStatus;
  final rust_hand.HandAirBoardDecision decision;

  @override
  Widget build(BuildContext context) => Container(
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
                height: 1.4,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _Tag(modelStatus),
                _Tag(cameraStatus),
                _Tag(_friendly(decision.attentionLevel)),
              ],
            ),
          ],
        ),
      );
}

class _CameraPanel extends StatelessWidget {
  const _CameraPanel({
    required this.camera,
    required this.opening,
    required this.streaming,
    required this.processing,
    required this.signal,
    required this.resultReason,
    required this.decision,
  });

  final CameraController? camera;
  final bool opening;
  final bool streaming;
  final bool processing;
  final rust_hand.HandRegionSignal? signal;
  final String? resultReason;
  final rust_hand.HandAirBoardDecision decision;

  @override
  Widget build(BuildContext context) => _Card(
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
                child: ColoredBox(
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
            _RowMetric('Stream', streaming ? 'Active' : 'Not active'),
            _RowMetric('Inference', processing ? 'Processing' : 'Ready'),
            _RowMetric('Hands', '${signal?.handCount ?? 0}'),
            _RowMetric(
              'Confidence',
              '${((signal?.handConfidence ?? 0) * 100).round()}%',
            ),
            _RowMetric(
              'Work-area match',
              decision.handMatchesAirBoard ? 'Matched' : 'Not confirmed',
            ),
            if (resultReason != null) ...[
              const SizedBox(height: 8),
              Text(
                resultReason!,
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

class _Board extends StatelessWidget {
  const _Board({
    required this.strokes,
    required this.active,
    required this.onStart,
    required this.onMove,
    required this.onEnd,
    required this.onUndo,
    required this.onClear,
  });

  final List<_Stroke> strokes;
  final _Stroke? active;
  final ValueChanged<Offset> onStart;
  final ValueChanged<Offset> onMove;
  final VoidCallback onEnd;
  final VoidCallback onUndo;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) => _Card(
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
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 17,
                        ),
                      ),
                      Text(
                        'Use mouse, touchscreen, or stylus.',
                        style: TextStyle(
                          color: _muted,
                          fontWeight: FontWeight.w600,
                        ),
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
                    painter: _Painter(strokes: strokes, active: active),
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
}

class _Evidence extends StatelessWidget {
  const _Evidence({
    required this.board,
    required this.handResult,
    required this.decision,
  });

  final rust_air.AirBoardActivitySummary board;
  final rust_vision.HandVisionResult? handResult;
  final rust_hand.HandAirBoardDecision decision;

  @override
  Widget build(BuildContext context) => _Card(
        child: Wrap(
          spacing: 24,
          runSpacing: 12,
          children: [
            _RowMetric('Board strokes', '${board.strokeCount}'),
            _RowMetric('Board points', '${board.totalPoints}'),
            _RowMetric('Writing now', board.currentlyWriting ? 'Yes' : 'No'),
            _RowMetric(
              'Hand detections',
              '${handResult?.detections.length ?? 0}',
            ),
            _RowMetric(
              'Hand state',
              decision.behaviourLabel.replaceAll('_', ' '),
            ),
            _RowMetric(
              'Review',
              decision.reviewRequired ? 'Required' : 'Normal',
            ),
          ],
        ),
      );
}

class _Card extends StatelessWidget {
  const _Card({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
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

class _Tag extends StatelessWidget {
  const _Tag(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Container(
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

class _RowMetric extends StatelessWidget {
  const _RowMetric(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 7),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '$label: ',
              style: const TextStyle(
                color: _muted,
                fontWeight: FontWeight.w700,
              ),
            ),
            Flexible(
              child: Text(
                value,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: _ink,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ),
      );
}

class _Painter extends CustomPainter {
  const _Painter({required this.strokes, required this.active});
  final List<_Stroke> strokes;
  final _Stroke? active;

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
      _drawStroke(canvas, stroke);
    }
    if (active != null) _drawStroke(canvas, active!);
  }

  void _drawStroke(Canvas canvas, _Stroke stroke) {
    if (stroke.points.length < 2) return;
    final paint = Paint()
      ..color = _ink
      ..strokeWidth = 3.2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    final path = Path()
      ..moveTo(stroke.points.first.offset.dx, stroke.points.first.offset.dy);
    for (var i = 1; i < stroke.points.length; i++) {
      final previous = stroke.points[i - 1].offset;
      final current = stroke.points[i].offset;
      final middle = Offset(
        (previous.dx + current.dx) / 2,
        (previous.dy + current.dy) / 2,
      );
      path.quadraticBezierTo(
        previous.dx,
        previous.dy,
        middle.dx,
        middle.dy,
      );
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _Painter oldDelegate) => true;
}

class _Stroke {
  _Stroke({
    required this.id,
    required this.points,
    required this.startedAt,
    required this.endedAt,
  });

  final String id;
  final List<_Point> points;
  final DateTime startedAt;
  DateTime endedAt;
}

class _Point {
  const _Point(this.offset, this.at);
  final Offset offset;
  final DateTime at;
}

String _friendly(String level) {
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

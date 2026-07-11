import 'dart:async';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;

import '../proctoring_demo/camera_runtime_coordinator.dart';
import '../rust/api/hand_gesture.dart' as rust_gesture;
import '../rust/api/hand_landmark_runtime.dart' as rust_landmark;
import '../rust/api/hand_vision.dart' as rust_vision;
import '../rust/api/native_vision.dart' as rust_native;

const _brand = Color(0xFF0F4C81);
const _ink = Color(0xFF0B1220);
const _muted = Color(0xFF64748B);
const _line = Color(0xFFE2E8F0);
const _page = Color(0xFFF4F7FB);

class AirBoardFingertipView extends StatefulWidget {
  const AirBoardFingertipView({super.key});

  @override
  State<AirBoardFingertipView> createState() => _AirBoardFingertipViewState();
}

class _AirBoardFingertipViewState extends State<AirBoardFingertipView> {
  static const _owner = 'air_board_fingertip';
  static const _sampleInterval = Duration(milliseconds: 550);
  static const _gestureFramesRequired = 2;

  final _cameraRuntime = CameraRuntimeCoordinator.instance;
  final GlobalKey _canvasKey = GlobalKey();
  final List<_GestureStroke> _strokes = <_GestureStroke>[];

  CameraController? _camera;
  Timer? _snapshotTimer;
  _GestureStroke? _activeStroke;
  rust_vision.HandVisionResult? _handVision;
  rust_landmark.HandLandmarkInferenceResult? _landmarkResult;

  bool _ownsLease = false;
  bool _processing = false;
  bool _detectorLoaded = false;
  bool _landmarkLoaded = false;
  bool _boardArmed = false;
  bool _disposed = false;
  int _strokeId = 0;
  int _gestureStableFrames = 0;
  String _pendingGesture = 'none';
  String _stableGesture = 'none';
  Offset? _smoothedTip;

  String _modelStatus = 'Loading local hand models...';
  String _cameraStatus = 'Preparing camera...';
  String _studentMessage = 'Show an open palm to activate the Air Board.';

  @override
  void initState() {
    super.initState();
    unawaited(_initialize());
  }

  @override
  void dispose() {
    _disposed = true;
    _snapshotTimer?.cancel();
    final camera = _camera;
    _camera = null;
    if (camera != null) unawaited(camera.dispose());
    if (_ownsLease) _cameraRuntime.release(_owner);
    super.dispose();
  }

  Future<void> _initialize() async {
    try {
      final detectorManifest = await rootBundle.loadString(
        'assets/models/hand_vision/manifest.json',
      );
      final detectorData = await rootBundle.load(
        'assets/models/hand_vision/hand_detector.onnx',
      );
      final detectorStatus = rust_vision.loadHandVisionModel(
        manifestJson: detectorManifest,
        modelBytes: detectorData.buffer.asUint8List(
          detectorData.offsetInBytes,
          detectorData.lengthInBytes,
        ),
      );
      _detectorLoaded = detectorStatus.loaded;

      try {
        final landmarkManifest = await rootBundle.loadString(
          'assets/models/hand_landmark/manifest.json',
        );
        final landmarkData = await rootBundle.load(
          'assets/models/hand_landmark/hand_landmark.onnx',
        );
        final landmarkStatus = rust_landmark.loadHandLandmarkModel(
          manifestJson: landmarkManifest,
          modelBytes: landmarkData.buffer.asUint8List(
            landmarkData.offsetInBytes,
            landmarkData.lengthInBytes,
          ),
        );
        _landmarkLoaded = landmarkStatus.loaded;
        _modelStatus = landmarkStatus.loaded
            ? '${detectorStatus.modelName} + ${landmarkStatus.modelName} ready'
            : landmarkStatus.message;
      } catch (error) {
        _landmarkLoaded = false;
        _modelStatus =
            'Hand detector ready. Add assets/models/hand_landmark/hand_landmark.onnx to enable fingertip writing. $error';
      }

      if (!_detectorLoaded) {
        _modelStatus = detectorStatus.message;
      }
      if (mounted) setState(() {});
      if (_detectorLoaded) await _openCamera();
    } catch (error) {
      if (!mounted) return;
      setState(() => _modelStatus = 'Local hand models could not load: $error');
    }
  }

  Future<void> _openCamera() async {
    final lease = _cameraRuntime.tryAcquire(
      owner: _owner,
      purpose: 'air_board_fingertip_snapshot_inference',
    );
    if (lease == null) {
      if (!mounted) return;
      setState(() {
        _cameraStatus = 'Camera is already active for another exam monitor.';
      });
      return;
    }
    _ownsLease = true;

    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) throw StateError('No camera was found.');
      final selected = cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        selected,
        ResolutionPreset.medium,
        enableAudio: false,
      );
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      _camera = controller;
      setState(() => _cameraStatus = 'Camera snapshot analysis active');
      _snapshotTimer = Timer.periodic(
        _sampleInterval,
        (_) => unawaited(_captureAndAnalyze()),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _cameraStatus = 'Camera could not start: $error');
    }
  }

  Future<void> _captureAndAnalyze() async {
    final camera = _camera;
    if (_processing || !_detectorLoaded || camera == null || !camera.value.isInitialized) {
      return;
    }
    _processing = true;
    try {
      final picture = await camera.takePicture();
      final encoded = await picture.readAsBytes();
      final frame = img.decodeImage(encoded);
      if (frame == null) throw StateError('Camera snapshot could not be decoded.');
      final rgb = _imageToRgb(frame);
      final now = DateTime.now();
      final handResult = rust_vision.analyzeHandRgbFrame(
        rgbBytes: rgb,
        imageWidth: frame.width,
        imageHeight: frame.height,
        zones: const rust_vision.HandVisionZones(
          keyboardYMin: 0.66,
          stylusXMin: 0.05,
          stylusXMax: 0.95,
          stylusYMin: 0.40,
          faceXMin: 0.25,
          faceXMax: 0.75,
          faceYMin: 0.05,
          faceYMax: 0.45,
          deskLineY: 0.96,
        ),
        timestampMs: now.millisecondsSinceEpoch,
      );
      _handVision = handResult;

      if (!_landmarkLoaded || handResult.detections.isEmpty) {
        _handleNoGesture(
          _landmarkLoaded
              ? 'Keep one hand clearly visible to the camera.'
              : 'Fingertip model is not installed yet.',
        );
        return;
      }

      final detection = handResult.detections.reduce(
        (a, b) => a.confidence >= b.confidence ? a : b,
      );
      final crop = _cropHand(frame, detection);
      if (crop == null) {
        _handleNoGesture('Keep your full hand inside the camera view.');
        return;
      }

      final landmarkResult = rust_landmark.analyzeHandLandmarkRgbCrop(
        rgbBytes: _imageToRgb(crop.image),
        cropWidth: crop.image.width,
        cropHeight: crop.image.height,
        mirrored: true,
        timestampMs: now.millisecondsSinceEpoch,
      );
      _landmarkResult = landmarkResult;
      final gesture = landmarkResult.gesture;
      final frameTip = Offset(
        (crop.left + gesture.indexTipX * crop.width) / frame.width,
        (crop.top + gesture.indexTipY * crop.height) / frame.height,
      );
      _consumeGesture(gesture, frameTip);
    } catch (error) {
      if (mounted) {
        setState(() => _cameraStatus = 'Local gesture analysis error: $error');
      }
    } finally {
      _processing = false;
    }
  }

  _HandCrop? _cropHand(img.Image frame, rust_native.NativeVisionDetection detection) {
    final padX = detection.width * 0.28;
    final padY = detection.height * 0.28;
    final left = math.max(0, (detection.xMin - padX).floor());
    final top = math.max(0, (detection.yMin - padY).floor());
    final right = math.min(frame.width, (detection.xMax + padX).ceil());
    final bottom = math.min(frame.height, (detection.yMax + padY).ceil());
    final width = right - left;
    final height = bottom - top;
    if (width < 32 || height < 32) return null;
    return _HandCrop(
      image: img.copyCrop(frame, x: left, y: top, width: width, height: height),
      left: left,
      top: top,
      width: width,
      height: height,
    );
  }

  Uint8List _imageToRgb(img.Image image) {
    final bytes = Uint8List(image.width * image.height * 3);
    var index = 0;
    for (final pixel in image) {
      bytes[index++] = pixel.r.toInt();
      bytes[index++] = pixel.g.toInt();
      bytes[index++] = pixel.b.toInt();
    }
    return bytes;
  }

  void _consumeGesture(rust_gesture.HandGestureResult gesture, Offset normalizedTip) {
    if (!gesture.usable) {
      _handleNoGesture(gesture.studentMessage);
      return;
    }

    if (_pendingGesture == gesture.gesture) {
      _gestureStableFrames++;
    } else {
      _pendingGesture = gesture.gesture;
      _gestureStableFrames = 1;
    }
    if (_gestureStableFrames < _gestureFramesRequired) return;
    _stableGesture = gesture.gesture;

    final previous = _smoothedTip;
    final smoothed = previous == null
        ? normalizedTip
        : Offset(
            previous.dx * 0.62 + normalizedTip.dx * 0.38,
            previous.dy * 0.62 + normalizedTip.dy * 0.38,
          );
    _smoothedTip = smoothed;

    if (_stableGesture == 'open_palm') {
      _finishGestureStroke();
      if (mounted) {
        setState(() {
          _boardArmed = true;
          _studentMessage = 'Air Board ready. Raise only your index finger to write.';
        });
      }
      return;
    }

    if (_stableGesture == 'index_only' && _boardArmed) {
      final boardPoint = _toCanvasPoint(smoothed);
      if (boardPoint != null) _writeGesturePoint(boardPoint);
      if (mounted) setState(() => _studentMessage = gesture.studentMessage);
      return;
    }

    if (_stableGesture == 'two_fingers' && _boardArmed) {
      _finishGestureStroke();
      final boardPoint = _toCanvasPoint(smoothed);
      if (boardPoint != null) _eraseNear(boardPoint);
      if (mounted) setState(() => _studentMessage = gesture.studentMessage);
      return;
    }

    _finishGestureStroke();
    if (mounted) setState(() => _studentMessage = gesture.studentMessage);
  }

  void _handleNoGesture(String message) {
    _gestureStableFrames = 0;
    _pendingGesture = 'none';
    _stableGesture = 'none';
    _finishGestureStroke();
    if (mounted) setState(() => _studentMessage = message);
  }

  Offset? _toCanvasPoint(Offset normalized) {
    final box = _canvasKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    return Offset(
      normalized.dx.clamp(0.0, 1.0) * box.size.width,
      normalized.dy.clamp(0.0, 1.0) * box.size.height,
    );
  }

  void _writeGesturePoint(Offset point) {
    final now = DateTime.now();
    if (_activeStroke == null) {
      _activeStroke = _GestureStroke(
        id: 'gesture-${++_strokeId}',
        points: <Offset>[point],
        startedAt: now,
        endedAt: now,
      );
    } else {
      final previous = _activeStroke!.points.last;
      if ((point - previous).distance >= 2.2) {
        _activeStroke!.points.add(point);
        _activeStroke!.endedAt = now;
      }
    }
    if (mounted) setState(() {});
  }

  void _finishGestureStroke() {
    final stroke = _activeStroke;
    if (stroke == null) return;
    if (stroke.points.length > 1) _strokes.add(stroke);
    _activeStroke = null;
    if (mounted && !_disposed) setState(() {});
  }

  void _eraseNear(Offset point) {
    const radius = 34.0;
    _strokes.removeWhere(
      (stroke) => stroke.points.any((candidate) => (candidate - point).distance <= radius),
    );
    if (mounted) setState(() {});
  }

  void _clear() {
    setState(() {
      _strokes.clear();
      _activeStroke = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final camera = _camera;
    final cameraReady = camera != null && camera.value.isInitialized;
    final gesture = _landmarkResult?.gesture;

    return Scaffold(
      backgroundColor: _page,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        title: const Text('Air Board', style: TextStyle(fontWeight: FontWeight.w900)),
        actions: [
          IconButton(onPressed: _clear, icon: const Icon(Icons.delete_outline_rounded)),
          TextButton.icon(
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.close_rounded),
            label: const Text('Close'),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _ink,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Camera-controlled rough work',
                    style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 6),
                  Text(_studentMessage, style: const TextStyle(color: Color(0xFFE2E8F0), fontWeight: FontWeight.w700)),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _StatusChip(_modelStatus),
                      _StatusChip(_cameraStatus),
                      _StatusChip(_boardArmed ? 'Board activated' : 'Show open palm'),
                      _StatusChip('Gesture: ${gesture?.gesture ?? 'waiting'}'),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Expanded(
              child: Row(
                children: [
                  SizedBox(
                    width: 300,
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        border: Border.all(color: _line),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Camera hand monitor', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                          const SizedBox(height: 12),
                          AspectRatio(
                            aspectRatio: 4 / 3,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(16),
                              child: ColoredBox(
                                color: _ink,
                                child: cameraReady ? CameraPreview(camera) : const Icon(Icons.videocam_off_outlined, color: Colors.white, size: 38),
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),
                          _InfoLine('Hands', '${_handVision?.signal.handCount ?? 0}'),
                          _InfoLine('Gesture', gesture?.gesture ?? 'Waiting'),
                          _InfoLine('Fingers', '${gesture?.fingerCount ?? 0}'),
                          _InfoLine('Confidence', '${((gesture?.confidence ?? 0) * 100).round()}%'),
                          _InfoLine('Writing', gesture?.writingActive == true ? 'Active' : 'Paused'),
                          _InfoLine('Eraser', gesture?.erasingActive == true ? 'Active' : 'Paused'),
                          const SizedBox(height: 14),
                          const Text(
                            'Open palm activates the board. One index finger writes. Two fingers erase. Closed hand pauses.',
                            style: TextStyle(color: _muted, height: 1.45, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        border: Border.all(color: _line),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Digital rough work', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                          const SizedBox(height: 4),
                          const Text('Move your raised index finger to write.', style: TextStyle(color: _muted, fontWeight: FontWeight.w600)),
                          const SizedBox(height: 12),
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(16),
                              child: CustomPaint(
                                key: _canvasKey,
                                painter: _GestureBoardPainter(
                                  strokes: _strokes,
                                  activeStroke: _activeStroke,
                                  cursor: _smoothedTip,
                                  armed: _boardArmed,
                                ),
                                child: const SizedBox.expand(),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HandCrop {
  const _HandCrop({required this.image, required this.left, required this.top, required this.width, required this.height});
  final img.Image image;
  final int left;
  final int top;
  final int width;
  final int height;
}

class _GestureStroke {
  _GestureStroke({required this.id, required this.points, required this.startedAt, required this.endedAt});
  final String id;
  final List<Offset> points;
  final DateTime startedAt;
  DateTime endedAt;
}

class _GestureBoardPainter extends CustomPainter {
  const _GestureBoardPainter({required this.strokes, required this.activeStroke, required this.cursor, required this.armed});
  final List<_GestureStroke> strokes;
  final _GestureStroke? activeStroke;
  final Offset? cursor;
  final bool armed;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.white);
    final grid = Paint()..color = const Color(0xFFE2E8F0)..strokeWidth = 1;
    for (var x = 40.0; x < size.width; x += 40) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
    }
    for (var y = 40.0; y < size.height; y += 40) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    for (final stroke in <_GestureStroke>[...strokes, if (activeStroke != null) activeStroke!]) {
      if (stroke.points.length < 2) continue;
      final path = Path()..moveTo(stroke.points.first.dx, stroke.points.first.dy);
      for (var i = 1; i < stroke.points.length; i++) {
        path.lineTo(stroke.points[i].dx, stroke.points[i].dy);
      }
      canvas.drawPath(path, Paint()..color = _ink..strokeWidth = 3.2..strokeCap = StrokeCap.round..strokeJoin = StrokeJoin.round..style = PaintingStyle.stroke);
    }
    final normalized = cursor;
    if (normalized != null) {
      final point = Offset(normalized.dx.clamp(0.0, 1.0) * size.width, normalized.dy.clamp(0.0, 1.0) * size.height);
      canvas.drawCircle(point, armed ? 8 : 6, Paint()..color = armed ? _brand : _muted);
    }
  }

  @override
  bool shouldRepaint(covariant _GestureBoardPainter oldDelegate) => true;
}

class _StatusChip extends StatelessWidget {
  const _StatusChip(this.label);
  final String label;
  @override
  Widget build(BuildContext context) => Container(
        constraints: const BoxConstraints(maxWidth: 420),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(999), border: Border.all(color: Colors.white.withValues(alpha: 0.16))),
        child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
      );
}

class _InfoLine extends StatelessWidget {
  const _InfoLine(this.label, this.value);
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 9),
        child: Row(children: [Expanded(child: Text(label, style: const TextStyle(color: _muted, fontWeight: FontWeight.w700))), Text(value, style: const TextStyle(color: _ink, fontWeight: FontWeight.w900))]),
      );
}

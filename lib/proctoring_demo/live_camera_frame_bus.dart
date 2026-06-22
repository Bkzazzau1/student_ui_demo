import 'dart:async';
import 'dart:convert';

import 'package:camera/camera.dart';
import 'package:flutter/services.dart';

class LiveCameraFrame {
  const LiveCameraFrame({
    required this.sequence,
    required this.owner,
    required this.purpose,
    required this.image,
    required this.capturedAt,
  });

  final int sequence;
  final String owner;
  final String purpose;
  final CameraImage image;
  final DateTime capturedAt;

  int get width => image.width;
  int get height => image.height;
  String get formatGroup => image.format.group.name;

  Map<String, Object?> toMetadata() => <String, Object?>{
        'frame_sequence': sequence,
        'frame_owner': owner,
        'frame_purpose': purpose,
        'frame_width': width,
        'frame_height': height,
        'frame_format': formatGroup,
        'captured_at': capturedAt.toUtc().toIso8601String(),
      };
}

/// Single in-process frame bus for the exam camera.
///
/// The live camera owner publishes processed frames here. Lightweight local
/// checks and future object review can subscribe without creating a second
/// camera controller.
class LiveCameraFrameBus {
  LiveCameraFrameBus._();

  static final LiveCameraFrameBus instance = LiveCameraFrameBus._();

  final StreamController<LiveCameraFrame> _controller =
      StreamController<LiveCameraFrame>.broadcast(sync: true);

  int _sequence = 0;
  LiveCameraFrame? _latestFrame;

  Stream<LiveCameraFrame> get frames => _controller.stream;
  LiveCameraFrame? get latestFrame => _latestFrame;
  int get latestSequence => _sequence;
  bool get hasListeners => _controller.hasListener;

  LiveCameraFrame publish({
    required String owner,
    required String purpose,
    required CameraImage image,
  }) {
    final frame = LiveCameraFrame(
      sequence: ++_sequence,
      owner: owner,
      purpose: purpose,
      image: image,
      capturedAt: DateTime.now(),
    );
    _latestFrame = frame;
    if (!_controller.isClosed) {
      _controller.add(frame);
    }
    return frame;
  }

  Map<String, Object?> currentState() => <String, Object?>{
        'latest_frame_sequence': _latestFrame?.sequence,
        'latest_frame_at': _latestFrame?.capturedAt.toUtc().toIso8601String(),
        'has_listeners': hasListeners,
      };
}

class ObjectModelRuntimeConfig {
  const ObjectModelRuntimeConfig({
    this.assetPath =
        'assets/models/optimized_vision_runtime/object_reflection_shadow_detector.int8.onnx',
    this.minimumFrameGap = 2,
  });

  final String assetPath;
  final int minimumFrameGap;
}

class ObjectModelRuntimeStatus {
  const ObjectModelRuntimeStatus({
    required this.assetPath,
    required this.assetPresent,
    required this.inferenceReady,
    required this.running,
    required this.lastFrameSequence,
    required this.message,
  });

  final String assetPath;
  final bool assetPresent;
  final bool inferenceReady;
  final bool running;
  final int lastFrameSequence;
  final String message;

  Map<String, Object?> toJson() => <String, Object?>{
        'asset_path': assetPath,
        'asset_present': assetPresent,
        'inference_ready': inferenceReady,
        'running': running,
        'last_frame_sequence': lastFrameSequence,
        'message': message,
      };
}

class ObjectModelFrameGate {
  ObjectModelFrameGate({
    LiveCameraFrameBus? frameBus,
    this.config = const ObjectModelRuntimeConfig(),
  }) : _frameBus = frameBus ?? LiveCameraFrameBus.instance;

  final LiveCameraFrameBus _frameBus;
  final ObjectModelRuntimeConfig config;

  StreamSubscription<LiveCameraFrame>? _subscription;
  bool _running = false;
  bool _assetPresent = false;
  int _lastFrameSequence = 0;

  bool get isRunning => _running;
  bool get assetPresent => _assetPresent;
  int get lastFrameSequence => _lastFrameSequence;

  Future<ObjectModelRuntimeStatus> start({
    required void Function(LiveCameraFrame frame) onFrameReady,
  }) async {
    if (_running) return status('Object model frame gate already running.');

    _assetPresent = await _assetExists(config.assetPath);
    if (!_assetPresent) {
      return status('Object model asset not found. Frame gate remains disabled.');
    }

    _running = true;
    _subscription = _frameBus.frames.listen((frame) {
      if (frame.sequence - _lastFrameSequence < config.minimumFrameGap) return;
      _lastFrameSequence = frame.sequence;
      onFrameReady(frame);
    });

    return status('Object model asset found. Frame gate is running.');
  }

  Future<void> stop() async {
    _running = false;
    await _subscription?.cancel();
    _subscription = null;
  }

  ObjectModelRuntimeStatus status(String message) => ObjectModelRuntimeStatus(
        assetPath: config.assetPath,
        assetPresent: _assetPresent,
        inferenceReady: false,
        running: _running,
        lastFrameSequence: _lastFrameSequence,
        message: message,
      );

  Future<bool> _assetExists(String assetPath) async {
    try {
      final manifestText = await rootBundle.loadString('AssetManifest.json');
      final decoded = jsonDecode(manifestText);
      if (decoded is Map<String, dynamic>) {
        return decoded.containsKey(assetPath);
      }
    } catch (_) {
      return false;
    }
    return false;
  }
}

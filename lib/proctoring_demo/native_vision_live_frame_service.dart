import 'dart:async';

import 'live_camera_frame_bus.dart';
import 'native_vision_bridge.dart';

class NativeVisionLiveFrameResult {
  const NativeVisionLiveFrameResult({
    required this.frameSequence,
    required this.capturedAt,
    required this.quality,
  });

  final int frameSequence;
  final DateTime capturedAt;
  final NativeVisionFrameQualitySnapshot quality;

  bool get isUsable => quality.isUsable;
  bool get needsLightingGuidance => !quality.isUsable &&
      (quality.reason.contains('dark') ||
          quality.reason.contains('overexposed') ||
          quality.reason.contains('contrast') ||
          quality.reason.contains('blurry'));

  Map<String, Object?> toJson() => <String, Object?>{
        'frame_sequence': frameSequence,
        'captured_at': capturedAt.toUtc().toIso8601String(),
        'quality': quality.toJson(),
        'is_usable': isUsable,
        'needs_lighting_guidance': needsLightingGuidance,
      };
}

class NativeVisionLiveFrameService {
  NativeVisionLiveFrameService({
    LiveCameraFrameBus? frameBus,
    NativeVisionBridge? bridge,
    this.minimumFrameGap = 6,
  })  : _frameBus = frameBus ?? LiveCameraFrameBus.instance,
        _bridge = bridge ?? const GeneratedNativeVisionBridge();

  final LiveCameraFrameBus _frameBus;
  final NativeVisionBridge _bridge;
  final int minimumFrameGap;

  StreamSubscription<LiveCameraFrame>? _subscription;
  int _lastFrameSequence = 0;
  bool _running = false;

  bool get isRunning => _running;
  int get lastFrameSequence => _lastFrameSequence;

  Future<void> start({
    required void Function(NativeVisionLiveFrameResult result) onQualityResult,
  }) async {
    if (_running) return;
    _running = true;
    _subscription = _frameBus.frames.listen((frame) {
      if (frame.sequence - _lastFrameSequence < minimumFrameGap) return;
      _lastFrameSequence = frame.sequence;
      final quality = _bridge.analyzeFrameQuality(frame.image);
      if (quality == null) return;
      onQualityResult(
        NativeVisionLiveFrameResult(
          frameSequence: frame.sequence,
          capturedAt: frame.capturedAt,
          quality: quality,
        ),
      );
    });
  }

  Future<void> stop() async {
    _running = false;
    await _subscription?.cancel();
    _subscription = null;
  }
}

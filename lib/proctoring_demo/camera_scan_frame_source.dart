import 'dart:async';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

class DemoCameraScanFrame {
  const DemoCameraScanFrame({
    required this.mode,
    required this.luma,
    required this.signature,
    required this.timestamp,
    this.decodedImage,
    this.cameraImage,
  });

  final String mode;
  final double luma;
  final List<int> signature;
  final DateTime timestamp;
  final img.Image? decodedImage;
  final CameraImage? cameraImage;
}

class DemoCameraScanFrameSource {
  DemoCameraScanFrameSource({
    this.stillCaptureInterval = const Duration(milliseconds: 1400),
  });

  final Duration stillCaptureInterval;
  Timer? _timer;
  bool _active = false;
  bool _busy = false;
  Future<void> Function(DemoCameraScanFrame frame)? _onFrame;
  bool Function()? _shouldContinue;
  void Function(String status)? _onStatus;

  Future<void> start({
    required CameraController controller,
    required bool Function() shouldContinue,
    required Future<void> Function(DemoCameraScanFrame frame) onFrame,
    required void Function(String status) onStatus,
  }) async {
    await stop(controller);
    _active = true;
    _busy = false;
    _onFrame = onFrame;
    _shouldContinue = shouldContinue;
    _onStatus = onStatus;

    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
      _startStill(controller);
      return;
    }

    try {
      await controller.startImageStream(_handleLive);
      onStatus('live-frame');
    } catch (_) {
      _startStill(controller);
    }
  }

  Future<void> stop(CameraController? controller) async {
    _timer?.cancel();
    _timer = null;
    _active = false;
    _busy = false;
    if (controller == null || !controller.value.isInitialized) return;
    try {
      if (controller.value.isStreamingImages) {
        await controller.stopImageStream();
      }
    } catch (_) {}
  }

  bool get _usable => _active && (_shouldContinue?.call() ?? false);

  void _startStill(CameraController controller) {
    _onStatus?.call('still-frame');
    _timer = Timer.periodic(stillCaptureInterval, (_) {
      unawaited(_captureStill(controller));
    });
    Future<void>.delayed(const Duration(milliseconds: 500), () {
      if (_usable) unawaited(_captureStill(controller));
    });
  }

  Future<void> _captureStill(CameraController controller) async {
    if (!_usable || _busy || !controller.value.isInitialized) return;
    _busy = true;
    try {
      final file = await controller.takePicture();
      final decoded = img.decodeImage(await file.readAsBytes());
      if (decoded == null) return;
      await _onFrame?.call(
        DemoCameraScanFrame(
          mode: 'still-frame',
          luma: _averageDecodedLuma(decoded),
          signature: _decodedSignature(decoded),
          timestamp: DateTime.now(),
          decodedImage: decoded,
        ),
      );
    } catch (e) {
      _onStatus?.call('camera-busy: $e');
    } finally {
      _busy = false;
    }
  }

  void _handleLive(CameraImage image) {
    if (!_usable || _busy) return;
    _busy = true;
    unawaited(_processLive(image));
  }

  Future<void> _processLive(CameraImage image) async {
    try {
      await _onFrame?.call(
        DemoCameraScanFrame(
          mode: 'live-frame',
          luma: _averageLuma(image),
          signature: _liveSignature(image),
          timestamp: DateTime.now(),
          cameraImage: image,
        ),
      );
    } finally {
      _busy = false;
    }
  }

  double _averageLuma(CameraImage image) {
    if (image.planes.isEmpty || image.planes.first.bytes.isEmpty) return 0.5;
    final bytes = image.planes.first.bytes;
    final step = math.max(1, bytes.length ~/ 600);
    var total = 0;
    var count = 0;
    for (var i = 0; i < bytes.length; i += step) {
      total += bytes[i];
      count++;
    }
    return count == 0 ? 0.5 : (total / count / 255).clamp(0.0, 1.0);
  }

  List<int> _liveSignature(CameraImage image) {
    if (image.planes.isEmpty || image.planes.first.bytes.isEmpty) {
      return const <int>[128];
    }
    return _signatureFromBytes(image.planes.first.bytes);
  }

  List<int> _signatureFromBytes(List<int> bytes) {
    const buckets = 48;
    final signature = <int>[];
    for (var bucket = 0; bucket < buckets; bucket++) {
      final start = (bytes.length * bucket / buckets).floor();
      final end = (bytes.length * (bucket + 1) / buckets).floor();
      var total = 0;
      var count = 0;
      for (var i = start; i < end; i += math.max(1, (end - start) ~/ 12)) {
        total += bytes[i.clamp(0, bytes.length - 1)];
        count++;
      }
      signature.add(count == 0 ? 128 : (total / count).round());
    }
    return signature;
  }

  double _averageDecodedLuma(img.Image image) {
    final stepX = math.max(1, image.width ~/ 24);
    final stepY = math.max(1, image.height ~/ 24);
    var total = 0.0;
    var count = 0;
    for (var y = 0; y < image.height; y += stepY) {
      for (var x = 0; x < image.width; x += stepX) {
        final pixel = image.getPixel(x, y);
        total += (pixel.r * 0.299) + (pixel.g * 0.587) + (pixel.b * 0.114);
        count++;
      }
    }
    return count == 0 ? 0.5 : (total / count / 255).clamp(0.0, 1.0);
  }

  List<int> _decodedSignature(img.Image image) {
    final values = <int>[];
    for (var y = 0; y < 6; y++) {
      for (var x = 0; x < 8; x++) {
        final pixel = image.getPixel(
          (((x + 0.5) * image.width / 8).floor()).clamp(0, image.width - 1),
          (((y + 0.5) * image.height / 6).floor()).clamp(0, image.height - 1),
        );
        values.add(
          ((pixel.r * 0.299) + (pixel.g * 0.587) + (pixel.b * 0.114)).round(),
        );
      }
    }
    return values;
  }
}

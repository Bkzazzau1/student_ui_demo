import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../rust/api/hand_vision.dart' as rust_hand_vision;

class HandVisionCameraRuntime {
  HandVisionCameraRuntime({
    this.sampleInterval = const Duration(milliseconds: 400),
    this.manifestAssetPath = 'assets/models/hand_vision/manifest.json',
    this.modelAssetPath = 'assets/models/hand_vision/hand_detector.onnx',
    rust_hand_vision.HandVisionZones? zones,
  }) : zones = zones ??
            const rust_hand_vision.HandVisionZones(
              keyboardYMin: 0.68,
              stylusXMin: 0.30,
              stylusXMax: 0.95,
              stylusYMin: 0.58,
              faceXMin: 0.24,
              faceXMax: 0.76,
              faceYMin: 0.05,
              faceYMax: 0.52,
              deskLineY: 0.94,
            );

  final Duration sampleInterval;
  final String manifestAssetPath;
  final String modelAssetPath;
  final rust_hand_vision.HandVisionZones zones;

  bool _running = false;
  bool _processing = false;
  DateTime? _lastSampleAt;
  CameraController? _controller;

  rust_hand_vision.HandVisionModelStatus? _modelStatus;
  rust_hand_vision.HandVisionResult? _lastResult;
  String? _lastError;

  bool get isRunning => _running;
  bool get isProcessing => _processing;
  rust_hand_vision.HandVisionModelStatus? get modelStatus => _modelStatus;
  rust_hand_vision.HandVisionResult? get lastResult => _lastResult;
  String? get lastError => _lastError;

  Future<rust_hand_vision.HandVisionModelStatus> loadModel() async {
    try {
      final manifestJson = await rootBundle.loadString(manifestAssetPath);
      final modelData = await rootBundle.load(modelAssetPath);
      final status = rust_hand_vision.loadHandVisionModel(
        manifestJson: manifestJson,
        modelBytes: modelData.buffer.asUint8List(
          modelData.offsetInBytes,
          modelData.lengthInBytes,
        ),
      );
      _modelStatus = status;
      _lastError = status.loaded ? null : status.message;
      return status;
    } on FlutterError catch (_) {
      final status = rust_hand_vision.currentHandVisionModelStatus();
      _modelStatus = status;
      _lastError =
          'Hand model asset is missing. Add $modelAssetPath before enabling live hand intelligence.';
      return status;
    } catch (error) {
      final status = rust_hand_vision.currentHandVisionModelStatus();
      _modelStatus = status;
      _lastError = 'Hand model could not be loaded: $error';
      return status;
    }
  }

  Future<void> start({
    required CameraController controller,
    required void Function(rust_hand_vision.HandVisionResult result) onResult,
    void Function(String message)? onStatus,
  }) async {
    if (_running) return;
    if (!controller.value.isInitialized) {
      throw StateError('Camera must be initialized before starting hand vision.');
    }

    _controller = controller;
    final status = _modelStatus ?? await loadModel();
    if (!status.loaded) {
      onStatus?.call(
        _lastError ??
            'Hand model is not loaded. Camera preview may continue, but hand-position intelligence is unavailable.',
      );
      return;
    }

    _running = true;
    _lastSampleAt = null;
    onStatus?.call('Local hand model active');

    await controller.startImageStream((image) {
      if (!_running || _processing) return;
      final now = DateTime.now();
      final last = _lastSampleAt;
      if (last != null && now.difference(last) < sampleInterval) return;
      _lastSampleAt = now;
      _processing = true;
      unawaited(
        _processFrame(image, now)
            .then((result) {
              if (result == null || !_running) return;
              _lastResult = result;
              _lastError = null;
              onResult(result);
            })
            .catchError((Object error) {
              _lastError = 'Hand frame analysis failed: $error';
              onStatus?.call(_lastError!);
              return null;
            })
            .whenComplete(() => _processing = false),
      );
    });
  }

  Future<void> stop() async {
    _running = false;
    _processing = false;
    final controller = _controller;
    _controller = null;
    if (controller != null && controller.value.isStreamingImages) {
      try {
        await controller.stopImageStream();
      } catch (_) {
        // Camera may already be stopping or disposed by the owning screen.
      }
    }
  }

  Future<rust_hand_vision.HandVisionResult?> _processFrame(
    CameraImage image,
    DateTime capturedAt,
  ) async {
    final rgb = _cameraImageToRgb(image);
    if (rgb == null) {
      throw StateError('Unsupported camera image format: ${image.format.group.name}');
    }

    return rust_hand_vision.analyzeHandRgbFrame(
      rgbBytes: rgb,
      imageWidth: image.width,
      imageHeight: image.height,
      zones: zones,
      timestampMs: capturedAt.millisecondsSinceEpoch,
    );
  }

  Uint8List? _cameraImageToRgb(CameraImage image) {
    switch (image.format.group) {
      case ImageFormatGroup.bgra8888:
        return _bgraToRgb(image);
      case ImageFormatGroup.yuv420:
      case ImageFormatGroup.nv21:
        return _yuv420ToRgb(image);
      default:
        return null;
    }
  }

  Uint8List? _bgraToRgb(CameraImage image) {
    if (image.planes.isEmpty) return null;
    final plane = image.planes.first;
    final bytes = plane.bytes;
    final rowStride = plane.bytesPerRow;
    const pixelStride = 4;
    final output = Uint8List(image.width * image.height * 3);
    var outputIndex = 0;

    for (var y = 0; y < image.height; y++) {
      final rowStart = y * rowStride;
      for (var x = 0; x < image.width; x++) {
        final index = rowStart + x * pixelStride;
        if (index + 2 >= bytes.length) return null;
        output[outputIndex++] = bytes[index + 2];
        output[outputIndex++] = bytes[index + 1];
        output[outputIndex++] = bytes[index];
      }
    }
    return output;
  }

  Uint8List? _yuv420ToRgb(CameraImage image) {
    if (image.planes.length < 2) return null;

    final yPlane = image.planes[0];
    final uPlane = image.planes[1];
    final vPlane = image.planes.length > 2 ? image.planes[2] : image.planes[1];
    final yBytes = yPlane.bytes;
    final uBytes = uPlane.bytes;
    final vBytes = vPlane.bytes;
    final uvPixelStride = uPlane.bytesPerPixel ?? 1;
    final output = Uint8List(image.width * image.height * 3);
    var outputIndex = 0;

    for (var y = 0; y < image.height; y++) {
      final yRow = y * yPlane.bytesPerRow;
      final uvRow = (y >> 1) * uPlane.bytesPerRow;
      for (var x = 0; x < image.width; x++) {
        final yIndex = yRow + x;
        final uvIndex = uvRow + (x >> 1) * uvPixelStride;
        if (yIndex >= yBytes.length || uvIndex >= uBytes.length || uvIndex >= vBytes.length) {
          return null;
        }

        final yValue = yBytes[yIndex].toDouble();
        final uValue = uBytes[uvIndex].toDouble() - 128.0;
        final vValue = vBytes[uvIndex].toDouble() - 128.0;

        final red = (yValue + 1.402 * vValue).round().clamp(0, 255);
        final green =
            (yValue - 0.344136 * uValue - 0.714136 * vValue).round().clamp(0, 255);
        final blue = (yValue + 1.772 * uValue).round().clamp(0, 255);

        output[outputIndex++] = red;
        output[outputIndex++] = green;
        output[outputIndex++] = blue;
      }
    }
    return output;
  }
}

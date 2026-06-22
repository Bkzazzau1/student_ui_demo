import 'dart:async';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:image/image.dart' as img;

import '../rust/api/proctoring.dart' as native_proctoring;
import '../rust/frb_generated.dart';
import 'camera_scan_frame_source.dart';

class NativeScanFrameReviewResult {
  const NativeScanFrameReviewResult({
    required this.available,
    required this.lightingScore,
    required this.objectLabels,
    required this.faceCount,
    required this.estimatedYaw,
    required this.estimatedPitch,
    this.message,
  });

  final bool available;
  final double lightingScore;
  final List<String> objectLabels;
  final int faceCount;
  final double estimatedYaw;
  final double estimatedPitch;
  final String? message;

  Map<String, Object?> toJson() => <String, Object?>{
        'available': available,
        'lighting_score': lightingScore,
        'object_labels': objectLabels,
        'face_count': faceCount,
        'estimated_yaw': estimatedYaw,
        'estimated_pitch': estimatedPitch,
        if (message != null) 'message': message,
      };
}

class NativeScanFrameReviewService {
  NativeScanFrameReviewService();

  static Future<bool>? _nativeReady;

  Future<NativeScanFrameReviewResult?> analyse(DemoCameraScanFrame frame) async {
    if (!await _ensureNativeReady()) {
      return const NativeScanFrameReviewResult(
        available: false,
        lightingScore: 0,
        objectLabels: <String>[],
        faceCount: 0,
        estimatedYaw: 0,
        estimatedPitch: 0,
        message: 'Native scan review is not available.',
      );
    }

    try {
      final cameraImage = frame.cameraImage;
      if (cameraImage != null && cameraImage.planes.isNotEmpty) {
        final plane = cameraImage.planes.first;
        final decision = native_proctoring.analyzeScanFrame(
          plane0Bytes: plane.bytes,
          width: cameraImage.width,
          height: cameraImage.height,
          bytesPerRow: plane.bytesPerRow,
          pixelFormat: cameraImage.format.group.name,
        );
        return _fromDecision(decision);
      }

      final decoded = frame.decodedImage;
      if (decoded != null) {
        final luma = _decodedLuma(decoded);
        final decision = native_proctoring.analyzeScanFrame(
          plane0Bytes: luma,
          width: decoded.width,
          height: decoded.height,
          bytesPerRow: decoded.width,
          pixelFormat: 'luma8',
        );
        return _fromDecision(decision);
      }
    } catch (e) {
      return NativeScanFrameReviewResult(
        available: false,
        lightingScore: frame.luma,
        objectLabels: const <String>[],
        faceCount: 0,
        estimatedYaw: 0,
        estimatedPitch: 0,
        message: 'Native scan review failed: $e',
      );
    }

    return NativeScanFrameReviewResult(
      available: false,
      lightingScore: frame.luma,
      objectLabels: const <String>[],
      faceCount: 0,
      estimatedYaw: 0,
      estimatedPitch: 0,
      message: 'No camera frame was available for native scan review.',
    );
  }

  NativeScanFrameReviewResult _fromDecision(
    native_proctoring.ScanFrameDecision decision,
  ) {
    return NativeScanFrameReviewResult(
      available: true,
      lightingScore: decision.lightingScore.clamp(0.0, 1.0),
      objectLabels: _normalizeLabels(decision.objectLabels),
      faceCount: decision.faceCount,
      estimatedYaw: decision.estimatedYaw,
      estimatedPitch: decision.estimatedPitch,
      message: 'Native scan review completed.',
    );
  }

  static Future<bool> _ensureNativeReady() {
    return _nativeReady ??= () async {
      try {
        await BrainCoreApi.init();
        return true;
      } catch (_) {
        return false;
      }
    }();
  }

  List<String> _normalizeLabels(List<String> labels) {
    final normalized = <String>{};
    for (final label in labels) {
      final value = label
          .trim()
          .toLowerCase()
          .replaceAll(RegExp(r'[_\-]+'), ' ')
          .replaceAll(RegExp(r'\s+'), ' ');
      if (value.isEmpty || value == 'background' || value == 'none') continue;
      normalized.add(value);
    }
    return normalized.toList()..sort();
  }

  Uint8List _decodedLuma(img.Image image) {
    final bytes = Uint8List(image.width * image.height);
    var index = 0;
    for (var y = 0; y < image.height; y++) {
      for (var x = 0; x < image.width; x++) {
        final pixel = image.getPixel(x, y);
        final luma = ((pixel.r * 0.299) + (pixel.g * 0.587) + (pixel.b * 0.114))
            .round()
            .clamp(0, 255);
        bytes[index++] = luma;
      }
    }
    return bytes;
  }
}

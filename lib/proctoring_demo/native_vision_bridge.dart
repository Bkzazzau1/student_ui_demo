import 'dart:typed_data';

import 'package:camera/camera.dart';

import '../rust/api/native_vision.dart' as native_vision;
import '../rust/frb_generated.dart';

class NativeVisionFrameQualitySnapshot {
  const NativeVisionFrameQualitySnapshot({
    required this.isUsable,
    required this.brightness,
    required this.contrast,
    required this.sharpness,
    required this.reason,
  });

  final bool isUsable;
  final double brightness;
  final double contrast;
  final double sharpness;
  final String reason;

  Map<String, Object?> toJson() => <String, Object?>{
        'is_usable': isUsable,
        'brightness': brightness,
        'contrast': contrast,
        'sharpness': sharpness,
        'reason': reason,
        'source': 'native_vision_frame_quality',
      };
}

class NativeVisionDetectionSnapshot {
  const NativeVisionDetectionSnapshot({
    required this.classId,
    required this.label,
    required this.confidence,
    required this.xCenter,
    required this.yCenter,
    required this.width,
    required this.height,
    required this.xMin,
    required this.yMin,
    required this.xMax,
    required this.yMax,
  });

  final int classId;
  final String label;
  final double confidence;
  final double xCenter;
  final double yCenter;
  final double width;
  final double height;
  final double xMin;
  final double yMin;
  final double xMax;
  final double yMax;

  Map<String, Object?> toJson() => <String, Object?>{
        'class_id': classId,
        'label': label,
        'confidence': confidence,
        'x_center': xCenter,
        'y_center': yCenter,
        'width': width,
        'height': height,
        'x_min': xMin,
        'y_min': yMin,
        'x_max': xMax,
        'y_max': yMax,
      };
}

class NativeObjectReviewSnapshot {
  const NativeObjectReviewSnapshot({
    required this.detections,
    required this.peopleCount,
    required this.phoneCount,
    required this.bookCount,
    required this.paperCount,
    required this.needsReview,
    required this.attentionLevel,
    required this.reason,
  });

  final List<NativeVisionDetectionSnapshot> detections;
  final int peopleCount;
  final int phoneCount;
  final int bookCount;
  final int paperCount;
  final bool needsReview;
  final String attentionLevel;
  final String reason;

  Map<String, Object?> toJson() => <String, Object?>{
        'detections': detections.map((item) => item.toJson()).toList(),
        'people_count': peopleCount,
        'phone_count': phoneCount,
        'book_count': bookCount,
        'paper_count': paperCount,
        'needs_review': needsReview,
        'attention_level': attentionLevel,
        'reason': reason,
        'source': 'native_vision_object_review',
      };
}

class NativeHeadPoseReviewSnapshot {
  const NativeHeadPoseReviewSnapshot({
    required this.usable,
    required this.lookingAway,
    required this.yawScore,
    required this.pitchScore,
    required this.rollScore,
    required this.attentionLevel,
    required this.reason,
  });

  final bool usable;
  final bool lookingAway;
  final double yawScore;
  final double pitchScore;
  final double rollScore;
  final String attentionLevel;
  final String reason;

  Map<String, Object?> toJson() => <String, Object?>{
        'usable': usable,
        'looking_away': lookingAway,
        'yaw_score': yawScore,
        'pitch_score': pitchScore,
        'roll_score': rollScore,
        'attention_level': attentionLevel,
        'reason': reason,
        'source': 'native_vision_head_pose',
      };
}

abstract class NativeVisionBridge {
  NativeVisionFrameQualitySnapshot? analyzeFrameQuality(CameraImage image);

  NativeObjectReviewSnapshot? decodeYoloOutput({
    required List<double> output,
    required int numPredictions,
    required int numClasses,
    required int imageWidth,
    required int imageHeight,
    required double confidenceThreshold,
    required double iouThreshold,
    required String layout,
    required List<String> classNames,
  });

  NativeHeadPoseReviewSnapshot? analyzeHeadPoseGeometry({
    required double leftEyeX,
    required double leftEyeY,
    required double rightEyeX,
    required double rightEyeY,
    required double noseX,
    required double noseY,
    required double mouthX,
    required double mouthY,
    required double faceWidth,
    required double faceHeight,
  });
}

class DisabledNativeVisionBridge implements NativeVisionBridge {
  const DisabledNativeVisionBridge();

  @override
  NativeVisionFrameQualitySnapshot? analyzeFrameQuality(CameraImage image) => null;

  @override
  NativeObjectReviewSnapshot? decodeYoloOutput({
    required List<double> output,
    required int numPredictions,
    required int numClasses,
    required int imageWidth,
    required int imageHeight,
    required double confidenceThreshold,
    required double iouThreshold,
    required String layout,
    required List<String> classNames,
  }) => null;

  @override
  NativeHeadPoseReviewSnapshot? analyzeHeadPoseGeometry({
    required double leftEyeX,
    required double leftEyeY,
    required double rightEyeX,
    required double rightEyeY,
    required double noseX,
    required double noseY,
    required double mouthX,
    required double mouthY,
    required double faceWidth,
    required double faceHeight,
  }) => null;
}

class GeneratedNativeVisionBridge implements NativeVisionBridge {
  const GeneratedNativeVisionBridge();

  static Future<void>? _nativeInit;
  static bool _nativeReady = false;
  static bool _nativeFailed = false;

  @override
  NativeVisionFrameQualitySnapshot? analyzeFrameQuality(CameraImage image) {
    if (!_ensureStarted()) return null;
    try {
      final rgb = _cameraImageToCompactRgb(image);
      if (rgb == null) return null;
      final result = native_vision.analyzeRgbFrameQuality(
        width: rgb.width,
        height: rgb.height,
        rgbBytes: rgb.bytes,
      );
      return NativeVisionFrameQualitySnapshot(
        isUsable: result.isUsable,
        brightness: result.brightness,
        contrast: result.contrast,
        sharpness: result.sharpness,
        reason: result.reason,
      );
    } catch (_) {
      return null;
    }
  }

  @override
  NativeObjectReviewSnapshot? decodeYoloOutput({
    required List<double> output,
    required int numPredictions,
    required int numClasses,
    required int imageWidth,
    required int imageHeight,
    required double confidenceThreshold,
    required double iouThreshold,
    required String layout,
    required List<String> classNames,
  }) {
    if (!_ensureStarted()) return null;
    try {
      final result = native_vision.decodeYoloOutput(
        output: output,
        numPredictions: numPredictions,
        numClasses: numClasses,
        imageWidth: imageWidth,
        imageHeight: imageHeight,
        confidenceThreshold: confidenceThreshold,
        iouThreshold: iouThreshold,
        layout: layout,
        classNames: classNames,
      );
      return _objectReviewFromNative(result);
    } catch (_) {
      return null;
    }
  }

  @override
  NativeHeadPoseReviewSnapshot? analyzeHeadPoseGeometry({
    required double leftEyeX,
    required double leftEyeY,
    required double rightEyeX,
    required double rightEyeY,
    required double noseX,
    required double noseY,
    required double mouthX,
    required double mouthY,
    required double faceWidth,
    required double faceHeight,
  }) {
    if (!_ensureStarted()) return null;
    try {
      final result = native_vision.analyzeHeadPoseGeometry(
        leftEyeX: leftEyeX,
        leftEyeY: leftEyeY,
        rightEyeX: rightEyeX,
        rightEyeY: rightEyeY,
        noseX: noseX,
        noseY: noseY,
        mouthX: mouthX,
        mouthY: mouthY,
        faceWidth: faceWidth,
        faceHeight: faceHeight,
      );
      return NativeHeadPoseReviewSnapshot(
        usable: result.usable,
        lookingAway: result.lookingAway,
        yawScore: result.yawScore,
        pitchScore: result.pitchScore,
        rollScore: result.rollScore,
        attentionLevel: result.attentionLevel,
        reason: result.reason,
      );
    } catch (_) {
      return null;
    }
  }

  static bool _ensureStarted() {
    if (_nativeReady) return true;
    if (_nativeFailed) return false;
    _nativeInit ??= _ensureNativeReady().then((ready) {
      _nativeReady = ready;
      _nativeFailed = !ready;
    });
    return false;
  }

  static Future<bool> _ensureNativeReady() async {
    try {
      await BrainCoreApi.init();
      return true;
    } catch (_) {
      return false;
    }
  }
}

NativeObjectReviewSnapshot _objectReviewFromNative(
  native_vision.NativeObjectReviewResult result,
) {
  return NativeObjectReviewSnapshot(
    detections: result.detections
        .map(
          (item) => NativeVisionDetectionSnapshot(
            classId: item.classId,
            label: item.label,
            confidence: item.confidence,
            xCenter: item.xCenter,
            yCenter: item.yCenter,
            width: item.width,
            height: item.height,
            xMin: item.xMin,
            yMin: item.yMin,
            xMax: item.xMax,
            yMax: item.yMax,
          ),
        )
        .toList(growable: false),
    peopleCount: result.peopleCount,
    phoneCount: result.phoneCount,
    bookCount: result.bookCount,
    paperCount: result.paperCount,
    needsReview: result.needsReview,
    attentionLevel: result.attentionLevel,
    reason: result.reason,
  );
}

class _CompactRgbFrame {
  const _CompactRgbFrame({
    required this.width,
    required this.height,
    required this.bytes,
  });

  final int width;
  final int height;
  final Uint8List bytes;
}

_CompactRgbFrame? _cameraImageToCompactRgb(CameraImage image) {
  if (image.width <= 0 || image.height <= 0 || image.planes.isEmpty) {
    return null;
  }

  const targetMaxSide = 96;
  final step = _samplingStep(image.width, image.height, targetMaxSide);
  final outWidth = (image.width / step).floor().clamp(1, image.width);
  final outHeight = (image.height / step).floor().clamp(1, image.height);
  final out = Uint8List(outWidth * outHeight * 3);

  final format = image.format.group;
  if (format == ImageFormatGroup.bgra8888 && image.planes.first.bytesPerRow > 0) {
    _sampleBgra8888(image, step, outWidth, outHeight, out);
  } else {
    _sampleLumaAsRgb(image, step, outWidth, outHeight, out);
  }

  return _CompactRgbFrame(width: outWidth, height: outHeight, bytes: out);
}

int _samplingStep(int width, int height, int targetMaxSide) {
  final maxSide = width > height ? width : height;
  if (maxSide <= targetMaxSide) return 1;
  return (maxSide / targetMaxSide).ceil().clamp(1, maxSide);
}

void _sampleLumaAsRgb(
  CameraImage image,
  int step,
  int outWidth,
  int outHeight,
  Uint8List out,
) {
  final plane = image.planes.first;
  final bytes = plane.bytes;
  final rowStride = plane.bytesPerRow <= 0 ? image.width : plane.bytesPerRow;
  var cursor = 0;
  for (var y = 0; y < outHeight; y++) {
    final sourceY = (y * step).clamp(0, image.height - 1);
    final rowStart = sourceY * rowStride;
    for (var x = 0; x < outWidth; x++) {
      final sourceX = (x * step).clamp(0, image.width - 1);
      final index = rowStart + sourceX;
      final value = index >= 0 && index < bytes.length ? bytes[index] : 0;
      out[cursor++] = value;
      out[cursor++] = value;
      out[cursor++] = value;
    }
  }
}

void _sampleBgra8888(
  CameraImage image,
  int step,
  int outWidth,
  int outHeight,
  Uint8List out,
) {
  final plane = image.planes.first;
  final bytes = plane.bytes;
  final rowStride = plane.bytesPerRow;
  var cursor = 0;
  for (var y = 0; y < outHeight; y++) {
    final sourceY = (y * step).clamp(0, image.height - 1);
    final rowStart = sourceY * rowStride;
    for (var x = 0; x < outWidth; x++) {
      final sourceX = (x * step).clamp(0, image.width - 1);
      final index = rowStart + sourceX * 4;
      if (index + 2 < bytes.length) {
        out[cursor++] = bytes[index + 2];
        out[cursor++] = bytes[index + 1];
        out[cursor++] = bytes[index];
      } else {
        out[cursor++] = 0;
        out[cursor++] = 0;
        out[cursor++] = 0;
      }
    }
  }
}

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:camera/camera.dart';

import '../proctoring_demo/native_vision_bridge.dart';
import '../proctoring_demo/optimized_vision_runtime_bridge.dart';

/// Outcome of asking the existing YOLO runtime "is this an identity-capture
/// scene we can trust?" before any face/identity work runs on the frame.
///
/// YOLO only ever answers person-presence/person-count questions here. It is
/// never used as a facial-identity signal, and the current COCO-trained
/// model has no eye/nose/mouth classes, so this gate must not claim any.
enum FaceIdentityPersonGateState {
  accepted,
  noPersonDetected,
  multiplePeopleDetected,
  runtimeUnavailable,
}

class FaceIdentityPersonGateResult {
  const FaceIdentityPersonGateResult({
    required this.state,
    required this.personCount,
    required this.personConfidence,
    required this.reason,
  });

  final FaceIdentityPersonGateState state;
  final int personCount;
  final double personConfidence;
  final String reason;

  bool get accepted => state == FaceIdentityPersonGateState.accepted;

  /// True when the scene must be rejected outright (as opposed to "unknown
  /// because the runtime is unavailable on this platform/build").
  bool get blocking =>
      state == FaceIdentityPersonGateState.noPersonDetected ||
      state == FaceIdentityPersonGateState.multiplePeopleDetected;
}

/// Wraps the existing exam-review YOLO runtime for identity-capture scenes.
///
/// This intentionally reuses [OptimizedVisionRuntimeBridge], the same bridge
/// the proctoring feature already drives, instead of standing up a second
/// inference path. The decode strategy mirrors the one already proven in
/// `live_exam_monitor.dart`: prefer already-decoded `objects`, fall back to
/// raw YOLO tensor decode via the Rust NMS decoder, and finally fall back to
/// the native aggregate counters when neither decoded form is present.
class FaceIdentityPersonGate {
  FaceIdentityPersonGate({
    OptimizedVisionRuntimeBridge? bridge,
    NativeVisionBridge nativeVision = const GeneratedNativeVisionBridge(),
    this.minimumConfidence = 0.5,
  }) : _bridge = bridge ?? OptimizedVisionRuntimeBridge(),
       _nativeVision = nativeVision;

  final OptimizedVisionRuntimeBridge _bridge;
  final NativeVisionBridge _nativeVision;
  final double minimumConfidence;

  Future<FaceIdentityPersonGateResult> analyzeRgb({
    required Uint8List rgbBytes,
    required int width,
    required int height,
  }) async {
    final result = await _bridge.runRgbFrame(
      rgbBytes: rgbBytes,
      width: width,
      height: height,
      tasks: const <String>['yolo_exam_review', 'object_review'],
    );
    return evaluate(result);
  }

  /// Same check as [analyzeRgb], but for a live camera-stream frame (raw
  /// YUV/BGRA planes) instead of an already-decoded still photo. Used by the
  /// live capture engine's periodic "multiple people" sweep, so it doesn't
  /// need a JPEG round-trip either.
  Future<FaceIdentityPersonGateResult> analyzeCameraImage(
    CameraImage image,
  ) async {
    final result = await _bridge.runFrame(
      image: image,
      tasks: const <String>['yolo_exam_review', 'object_review'],
    );
    return evaluate(result);
  }

  /// Pure decision function so the gate logic can be unit tested without a
  /// camera, a method channel, or a real ONNX runtime.
  FaceIdentityPersonGateResult evaluate(OptimizedVisionRuntimeResult? result) {
    if (result == null || !result.available) {
      return const FaceIdentityPersonGateResult(
        state: FaceIdentityPersonGateState.runtimeUnavailable,
        personCount: 0,
        personConfidence: 0,
        reason: 'The person-detection runtime is unavailable on this device.',
      );
    }

    final decodedPersons = _confidentPersonConfidences(result.outputs);
    if (decodedPersons != null) {
      return _fromConfidences(decodedPersons);
    }

    final nativeCount =
        int.tryParse('${result.outputs['person_count'] ?? ''}') ?? 0;
    final nativeMultiple = result.outputs['multiple_people_likely'] == true;
    final count = nativeMultiple && nativeCount < 2 ? 2 : nativeCount;
    if (count <= 0) {
      return const FaceIdentityPersonGateResult(
        state: FaceIdentityPersonGateState.noPersonDetected,
        personCount: 0,
        personConfidence: 0,
        reason: 'No person was detected in the capture scene.',
      );
    }
    if (count >= 2) {
      return FaceIdentityPersonGateResult(
        state: FaceIdentityPersonGateState.multiplePeopleDetected,
        personCount: count,
        personConfidence: 0,
        reason: 'More than one person is visible in the capture scene.',
      );
    }
    return const FaceIdentityPersonGateResult(
      state: FaceIdentityPersonGateState.accepted,
      personCount: 1,
      personConfidence: 1.0,
      reason: 'Exactly one person is present in the capture scene.',
    );
  }

  /// Returns confidences for detections already labeled `person`, decoding
  /// the raw YOLO tensor via the Rust NMS decoder when the native layer
  /// returned a tensor instead of pre-decoded detections. Returns null when
  /// neither decoded form is present, so the caller can fall back to the
  /// native aggregate counters.
  List<double>? _confidentPersonConfidences(Map<String, Object?> outputs) {
    final rawObjects = outputs['objects'];
    if (rawObjects is Iterable) {
      // The native Windows engine decodes its own ONNX output directly and
      // does NOT run non-max suppression on it: a single real person can
      // legitimately produce several overlapping raw "person" boxes from
      // neighboring grid cells/anchors, especially when the face fills most
      // of the frame during identity capture (as it does for enrollment).
      // Counting those raw entries directly overcounts people and would
      // reject a lone, well-framed student as "multiple people". Collapse
      // duplicates with the same greedy per-class NMS the Rust decoder
      // uses, kept local and synchronous so this stays a pure function.
      final boxes = <_DetectionBox>[];
      for (final raw in rawObjects) {
        if (raw is! Map) continue;
        final object = Map<Object?, Object?>.from(raw);
        final box = object['box'];
        final boxMap = box is Map ? Map<Object?, Object?>.from(box) : null;
        boxes.add(
          _DetectionBox(
            classId: _int(object['class_id']) ?? -1,
            label: _label(object),
            confidence: _confidence(object),
            x1: _boxValue(boxMap, 'x1'),
            y1: _boxValue(boxMap, 'y1'),
            x2: _boxValue(boxMap, 'x2'),
            y2: _boxValue(boxMap, 'y2'),
          ),
        );
      }
      return _nonMaxSuppress(boxes, 0.45)
          .where(
            (box) =>
                box.label.toLowerCase() == 'person' &&
                box.confidence >= minimumConfidence,
          )
          .map((box) => box.confidence)
          .toList(growable: false);
    }

    final tensor = _doubleList(
      outputs['yolo_output'] ?? outputs['raw_yolo_output'] ?? outputs['output'],
    );
    if (tensor.isEmpty) return null;
    final classNames = _stringList(
      outputs['class_names'] ?? outputs['labels'] ?? outputs['output_labels'],
    );
    if (classNames.isEmpty) return null;
    final numClasses = _int(outputs['num_classes']) ?? classNames.length;
    final numPredictions =
        _int(outputs['num_predictions']) ??
        _inferPredictionCount(
          outputLength: tensor.length,
          numClasses: numClasses,
          layout: outputs['layout']?.toString() ?? '',
        );
    if (numPredictions <= 0 || numClasses <= 0) return null;

    final decoded = _nativeVision.decodeYoloOutput(
      output: tensor,
      numPredictions: numPredictions,
      numClasses: numClasses,
      imageWidth: _int(outputs['image_width']) ?? _int(outputs['width']) ?? 640,
      imageHeight:
          _int(outputs['image_height']) ?? _int(outputs['height']) ?? 480,
      confidenceThreshold: minimumConfidence,
      iouThreshold: _double(outputs['iou_threshold']) ?? 0.45,
      layout: outputs['layout']?.toString() ?? 'rows_yolov8',
      classNames: classNames,
    );
    if (decoded == null) return null;
    return decoded.detections
        .where(
          (detection) =>
              detection.label.toLowerCase() == 'person' &&
              detection.confidence >= minimumConfidence,
        )
        .map((detection) => detection.confidence)
        .toList(growable: false);
  }

  FaceIdentityPersonGateResult _fromConfidences(List<double> confidences) {
    if (confidences.isEmpty) {
      return const FaceIdentityPersonGateResult(
        state: FaceIdentityPersonGateState.noPersonDetected,
        personCount: 0,
        personConfidence: 0,
        reason: 'No person was detected in the capture scene.',
      );
    }
    if (confidences.length >= 2) {
      return FaceIdentityPersonGateResult(
        state: FaceIdentityPersonGateState.multiplePeopleDetected,
        personCount: confidences.length,
        personConfidence: confidences.reduce((a, b) => a > b ? a : b),
        reason: 'More than one person is visible in the capture scene.',
      );
    }
    return FaceIdentityPersonGateResult(
      state: FaceIdentityPersonGateState.accepted,
      personCount: 1,
      personConfidence: confidences.first,
      reason: 'Exactly one person is present in the capture scene.',
    );
  }

  int _inferPredictionCount({
    required int outputLength,
    required int numClasses,
    required String layout,
  }) {
    final attributesYolov8 = 4 + numClasses;
    final attributesYolov5 = 5 + numClasses;
    final normalized = layout.trim().toLowerCase();
    if (normalized == 'rows_yolov5' && outputLength % attributesYolov5 == 0) {
      return outputLength ~/ attributesYolov5;
    }
    if (outputLength % attributesYolov8 == 0) {
      return outputLength ~/ attributesYolov8;
    }
    return 0;
  }

  String _label(Map<Object?, Object?> object) {
    for (final key in const <String>['label', 'class', 'name', 'category']) {
      final value = object[key];
      if (value != null && value.toString().trim().isNotEmpty) {
        return value.toString();
      }
    }
    return '';
  }

  double _confidence(Map<Object?, Object?> object) {
    for (final key in const <String>['confidence', 'score', 'probability']) {
      final value = object[key];
      if (value is num) return value.toDouble().clamp(0.0, 1.0);
      final parsed = double.tryParse(value?.toString() ?? '');
      if (parsed != null) return parsed.clamp(0.0, 1.0);
    }
    return 1.0;
  }

  double _boxValue(Map<Object?, Object?>? box, String key) {
    final value = box?[key];
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0.0;
  }

  List<double> _doubleList(Object? value) {
    if (value is! Iterable) return const <double>[];
    final output = <double>[];
    for (final item in value) {
      if (item is num) {
        output.add(item.toDouble());
        continue;
      }
      final parsed = double.tryParse(item?.toString() ?? '');
      if (parsed != null) output.add(parsed);
    }
    return output;
  }

  List<String> _stringList(Object? value) {
    if (value is! Iterable) return const <String>[];
    return value
        .map((item) => item?.toString().trim() ?? '')
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
  }

  int? _int(Object? value) {
    if (value is int) return value;
    if (value is num) return value.round();
    return int.tryParse(value?.toString() ?? '');
  }

  double? _double(Object? value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '');
  }

  /// Greedy per-class non-max suppression: keeps the highest-confidence box
  /// for each cluster of overlapping same-class detections, discarding the
  /// rest. Mirrors the Rust decoder's algorithm exactly so both decode paths
  /// agree on how many real objects are in a frame.
  List<_DetectionBox> _nonMaxSuppress(List<_DetectionBox> boxes, double iouThreshold) {
    final sorted = List<_DetectionBox>.of(boxes)
      ..sort((a, b) => b.confidence.compareTo(a.confidence));
    final kept = <_DetectionBox>[];
    for (final candidate in sorted) {
      final suppressed = kept.any(
        (existing) =>
            existing.classId == candidate.classId &&
            _iou(candidate, existing) > iouThreshold,
      );
      if (!suppressed) kept.add(candidate);
    }
    return kept;
  }

  double _iou(_DetectionBox a, _DetectionBox b) {
    final left = math.max(a.x1, b.x1);
    final top = math.max(a.y1, b.y1);
    final right = math.min(a.x2, b.x2);
    final bottom = math.min(a.y2, b.y2);
    if (right <= left || bottom <= top) return 0.0;
    final intersection = (right - left) * (bottom - top);
    final areaA = math.max(0.0, a.x2 - a.x1) * math.max(0.0, a.y2 - a.y1);
    final areaB = math.max(0.0, b.x2 - b.x1) * math.max(0.0, b.y2 - b.y1);
    return intersection / math.max(0.0001, areaA + areaB - intersection);
  }
}

class _DetectionBox {
  const _DetectionBox({
    required this.classId,
    required this.label,
    required this.confidence,
    required this.x1,
    required this.y1,
    required this.x2,
    required this.y2,
  });

  final int classId;
  final String label;
  final double confidence;
  final double x1;
  final double y1;
  final double x2;
  final double y2;
}

import 'dart:typed_data';

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
      final confidences = <double>[];
      for (final raw in rawObjects) {
        if (raw is! Map) continue;
        final object = Map<Object?, Object?>.from(raw);
        final label = _label(object).toLowerCase();
        if (label != 'person') continue;
        final confidence = _confidence(object);
        if (confidence >= minimumConfidence) confidences.add(confidence);
      }
      return confidences;
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
}

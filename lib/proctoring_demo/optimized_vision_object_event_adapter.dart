import 'native_vision_bridge.dart';
import 'object_review_event_mapper.dart';
import 'optimized_vision_runtime_bridge.dart';

class OptimizedVisionObjectEventAdapter {
  const OptimizedVisionObjectEventAdapter({
    this.mapper = const ObjectReviewEventMapper(),
    this.nativeVision = const GeneratedNativeVisionBridge(),
    this.minimumConfidence = 0.25,
  });

  final ObjectReviewEventMapper mapper;
  final NativeVisionBridge nativeVision;
  final double minimumConfidence;

  List<ObjectReviewEventDecision> mapResult(
    OptimizedVisionRuntimeResult result, {
    String source = 'optimized_vision_runtime',
  }) {
    if (!result.available) return const <ObjectReviewEventDecision>[];

    final nativeReview = _decodeNativeYoloReview(result.outputs);
    if (nativeReview != null) {
      final labels = nativeReview.detections
          .where((item) => item.confidence >= minimumConfidence)
          .map((item) => item.label)
          .toList();
      final decisions = mapper.mapLabels(
        labels,
        source: 'native_vision_yolo_decoder',
      );
      final enriched = decisions
          .map(
            (decision) => ObjectReviewEventDecision(
              eventType: decision.eventType,
              severity: nativeReview.attentionLevel == 'high_attention_required'
                  ? 'high'
                  : decision.severity,
              message: decision.message,
              labels: decision.labels,
              metadata: <String, Object?>{
                ...decision.metadata,
                'native_vision_review': nativeReview.toJson(),
              },
            ),
          )
          .toList();

      if (nativeReview.peopleCount > 1) {
        enriched.add(
          ObjectReviewEventDecision(
            eventType: 'camera_view_needs_review',
            severity: 'warning',
            message: 'Camera view may need review.',
            labels: const <String>['person'],
            metadata: <String, Object?>{
              'source_component': 'native_vision_yolo_decoder',
              'native_vision_review': nativeReview.toJson(),
              'person_count': nativeReview.peopleCount,
            },
          ),
        );
      }

      return enriched;
    }

    if (_requiresRustYoloDecode(result.outputs)) {
      return const <ObjectReviewEventDecision>[];
    }

    final labels = extractObjectLabels(result.outputs);
    return mapper.mapLabels(labels, source: source);
  }

  List<String> extractObjectLabels(Map<String, Object?> outputs) {
    final labels = <String>{};
    final rawObjects = outputs['objects'];
    if (rawObjects is Iterable) {
      for (final raw in rawObjects) {
        if (raw is! Map) continue;
        final object = Map<Object?, Object?>.from(raw);
        final label = _readLabel(object);
        if (label.isEmpty) continue;
        final confidence = _readConfidence(object);
        if (confidence < minimumConfidence) continue;
        labels.add(_normalize(label));
      }
    }

    if (outputs['screen_glow'] == true ||
        outputs['offscreen_interaction'] == true) {
      labels.add('screen');
    }

    return labels.where((label) => label.isNotEmpty).toList()..sort();
  }

  bool _requiresRustYoloDecode(Map<String, Object?> outputs) {
    final family =
        outputs['model_family']?.toString().trim().toLowerCase() ?? '';
    return family == 'yolo' || outputs['requires_rust_decode'] == true;
  }

  NativeObjectReviewSnapshot? _decodeNativeYoloReview(
    Map<String, Object?> outputs,
  ) {
    final output = _readDoubleList(
      outputs['yolo_output'] ?? outputs['raw_yolo_output'] ?? outputs['output'],
    );
    if (output.isEmpty) return null;

    final classNames = _readStringList(
      outputs['class_names'] ?? outputs['labels'] ?? outputs['output_labels'],
    );
    if (classNames.isEmpty) return null;

    final numClasses = _readInt(outputs['num_classes']) ?? classNames.length;
    final numPredictions =
        _readInt(outputs['num_predictions']) ??
        _inferPredictionCount(
          outputLength: output.length,
          numClasses: numClasses,
          layout: outputs['layout']?.toString() ?? '',
        );
    if (numPredictions <= 0 || numClasses <= 0) return null;

    return nativeVision.decodeYoloOutput(
      output: output,
      numPredictions: numPredictions,
      numClasses: numClasses,
      imageWidth:
          _readInt(outputs['image_width']) ?? _readInt(outputs['width']) ?? 640,
      imageHeight:
          _readInt(outputs['image_height']) ??
          _readInt(outputs['height']) ??
          480,
      confidenceThreshold:
          _readDouble(outputs['confidence_threshold']) ?? minimumConfidence,
      iouThreshold: _readDouble(outputs['iou_threshold']) ?? 0.45,
      layout: outputs['layout']?.toString() ?? 'rows_yolov8',
      classNames: classNames,
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

  List<double> _readDoubleList(Object? value) {
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

  List<String> _readStringList(Object? value) {
    if (value is! Iterable) return const <String>[];
    return value
        .map((item) => item?.toString().trim() ?? '')
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
  }

  int? _readInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.round();
    return int.tryParse(value?.toString() ?? '');
  }

  double? _readDouble(Object? value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '');
  }

  String _readLabel(Map<Object?, Object?> object) {
    for (final key in const <String>['label', 'class', 'name', 'category']) {
      final value = object[key];
      if (value != null && value.toString().trim().isNotEmpty) {
        return value.toString();
      }
    }
    return '';
  }

  double _readConfidence(Map<Object?, Object?> object) {
    for (final key in const <String>['confidence', 'score', 'probability']) {
      final value = object[key];
      if (value is num) return value.toDouble().clamp(0.0, 1.0);
      final parsed = double.tryParse(value?.toString() ?? '');
      if (parsed != null) return parsed.clamp(0.0, 1.0);
    }
    return 1.0;
  }

  String _normalize(String label) {
    return label
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[_\-]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ');
  }
}

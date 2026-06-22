import 'object_review_event_mapper.dart';
import 'optimized_vision_runtime_bridge.dart';

class OptimizedVisionObjectEventAdapter {
  const OptimizedVisionObjectEventAdapter({
    this.mapper = const ObjectReviewEventMapper(),
    this.minimumConfidence = 0.45,
  });

  final ObjectReviewEventMapper mapper;
  final double minimumConfidence;

  List<ObjectReviewEventDecision> mapResult(
    OptimizedVisionRuntimeResult result, {
    String source = 'optimized_vision_runtime',
  }) {
    if (!result.available) return const <ObjectReviewEventDecision>[];
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

    // Some native runtimes may surface boolean summary signals before a full
    // object list is available. Preserve those signals as review labels so the
    // same mapper can raise policy events consistently.
    if (outputs['screen_glow'] == true || outputs['offscreen_interaction'] == true) {
      labels.add('screen');
    }

    return labels.where((label) => label.isNotEmpty).toList()..sort();
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

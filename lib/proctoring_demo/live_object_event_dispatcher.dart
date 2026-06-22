import 'object_review_event_mapper.dart';
import 'optimized_vision_object_event_adapter.dart';
import 'optimized_vision_runtime_bridge.dart';

typedef LiveObjectEventSink = void Function(ObjectReviewEventDecision decision);

class LiveObjectEventDispatcher {
  const LiveObjectEventDispatcher({
    this.adapter = const OptimizedVisionObjectEventAdapter(),
  });

  final OptimizedVisionObjectEventAdapter adapter;

  List<ObjectReviewEventDecision> dispatchOptimizedVisionResult(
    OptimizedVisionRuntimeResult result, {
    required LiveObjectEventSink sink,
  }) {
    final decisions = adapter.mapResult(result);
    for (final decision in decisions) {
      sink(decision);
    }
    return decisions;
  }
}

import 'package:flutter_test/flutter_test.dart';
import 'package:students_ui_demo/proctoring_demo/live_object_event_dispatcher.dart';
import 'package:students_ui_demo/proctoring_demo/object_review_event_mapper.dart';
import 'package:students_ui_demo/proctoring_demo/optimized_vision_runtime_bridge.dart';

void main() {
  const dispatcher = LiveObjectEventDispatcher();

  test('dispatches mapped object events to the sink', () {
    final received = <ObjectReviewEventDecision>[];
    final decisions = dispatcher.dispatchOptimizedVisionResult(
      const OptimizedVisionRuntimeResult(
        available: true,
        backend: 'onnxRuntimeDirectML',
        precision: 'int8',
        inferenceMs: 9.5,
        outputs: <String, Object?>{
          'objects': <Map<String, Object?>>[
            <String, Object?>{'label': 'phone', 'confidence': 0.80},
            <String, Object?>{'label': 'calculator', 'confidence': 0.66},
          ],
        },
      ),
      sink: received.add,
    );

    expect(decisions, hasLength(2));
    expect(received, hasLength(2));
    expect(
      received.map((decision) => decision.eventType),
      containsAll(<String>['yolo_phone_detected', 'yolo_calculator_detected']),
    );
  });
}

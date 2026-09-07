import 'package:flutter_test/flutter_test.dart';
import 'package:students_ui_demo/proctoring_demo/optimized_vision_object_event_adapter.dart';
import 'package:students_ui_demo/proctoring_demo/optimized_vision_runtime_bridge.dart';

void main() {
  const adapter = OptimizedVisionObjectEventAdapter();

  OptimizedVisionRuntimeResult result(Map<String, Object?> outputs) {
    return OptimizedVisionRuntimeResult(
      available: true,
      backend: 'onnxRuntimeDirectML',
      precision: 'int8',
      inferenceMs: 12.5,
      outputs: outputs,
    );
  }

  test('extracts confident object labels from optimized vision outputs', () {
    final labels = adapter.extractObjectLabels(<String, Object?>{
      'objects': <Map<String, Object?>>[
        <String, Object?>{'label': 'cell_phone', 'confidence': 0.82},
        <String, Object?>{'label': 'book', 'confidence': 0.62},
        <String, Object?>{'label': 'paper', 'confidence': 0.30},
      ],
    });

    expect(labels, contains('cell phone'));
    expect(labels, contains('book'));
    expect(labels, contains('paper'));
  });

  test('maps optimized vision labels to policy event decisions', () {
    final decisions = adapter.mapResult(
      result(<String, Object?>{
        'objects': <Map<String, Object?>>[
          <String, Object?>{'label': 'cell phone', 'confidence': 0.82},
          <String, Object?>{'label': 'laptop', 'confidence': 0.76},
        ],
      }),
    );
    final eventTypes = decisions.map((decision) => decision.eventType).toSet();

    expect(eventTypes, contains('yolo_phone_detected'));
    expect(eventTypes, contains('yolo_extra_screen_detected'));
  });

  test('uses summary screen signal when object list is empty', () {
    final decisions = adapter.mapResult(
      result(<String, Object?>{
        'objects': const <Object?>[],
        'screen_glow': true,
      }),
    );

    expect(
      decisions.map((decision) => decision.eventType),
      contains('yolo_extra_screen_detected'),
    );
  });

  test('ignores unavailable optimized vision results', () {
    const unavailable = OptimizedVisionRuntimeResult(
      available: false,
      backend: 'onnxRuntimeCpu',
      precision: 'int8',
      inferenceMs: 0,
      outputs: <String, Object?>{},
    );

    expect(adapter.mapResult(unavailable), isEmpty);
  });

  test('does not emit formal E1 events without capture provenance', () {
    final noProvenance = result(<String, Object?>{
      'model_family': 'yolo',
      'yolo_output': <double>[],
    });

    expect(
      adapter.mapModelEvents(noProvenance, sessionId: 'attempt-001'),
      isEmpty,
    );
    expect(noProvenance.hasModelEventProvenance, isFalse);
  });

  test('runtime result reports complete provenance only when all fields exist', () {
    const withProvenance = OptimizedVisionRuntimeResult(
      available: true,
      backend: 'onnxRuntimeDirectML',
      precision: 'fp16',
      inferenceMs: 8.2,
      outputs: <String, Object?>{},
      sourceFrameId: 12,
      captureTimestampNs: 1_000,
      inferenceTimestampNs: 1_200,
      modelId: 'e1-yolo-exam-review',
      modelVersion: 'development-baseline-1',
      imageWidth: 640,
      imageHeight: 480,
    );

    expect(withProvenance.hasModelEventProvenance, isTrue);
    final json = withProvenance.toJson();
    expect(json['source_frame_id'], 12);
    expect(json['capture_timestamp_ns'], 1_000);
    expect(json['inference_timestamp_ns'], 1_200);
  });
}

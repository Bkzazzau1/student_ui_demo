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

  test('maps normalized Windows objects into frozen E1 model events', () {
    const withProvenance = OptimizedVisionRuntimeResult(
      available: true,
      backend: 'onnxRuntimeDirectML',
      precision: 'int8',
      inferenceMs: 7.4,
      outputs: <String, Object?>{
        'objects': <Map<String, Object?>>[
          <String, Object?>{
            'label': 'person',
            'class_id': 0,
            'confidence': 0.91,
            'box': <String, Object?>{
              'x1': 0.60,
              'y1': 0.10,
              'x2': 0.90,
              'y2': 0.70,
            },
          },
          <String, Object?>{
            'label': 'cell_phone',
            'class_id': 67,
            'confidence': 0.84,
            'box': <String, Object?>{
              'x1': 0.72,
              'y1': 0.72,
              'x2': 0.82,
              'y2': 0.88,
            },
          },
        ],
      },
      sourceFrameId: 44,
      captureTimestampNs: 5_000,
      inferenceTimestampNs: 5_320,
      modelId: 'e1-yolo-exam-review',
      modelVersion: 'development-baseline-1',
      imageWidth: 1280,
      imageHeight: 720,
    );

    final events = adapter.mapModelEvents(
      withProvenance,
      sessionId: 'attempt-001',
    );

    expect(events, hasLength(2));
    expect(events.first.classId, 'person');
    expect(events.first.sourceFrameId, 44);
    expect(events.first.trackId, isNull);
    expect(events.first.geometry?.coordinateSpace, 'normalized_frame');
    expect(events.first.geometry?.boundingBox?['x'], closeTo(0.60, 0.0001));
    expect(events.first.geometry?.boundingBox?['width'], closeTo(0.30, 0.0001));
    expect(events.first.geometry?.regionId, 'middle_right');
    expect(
      events.first.metadata['source_representation'],
      'windows_onnx_normalized_objects',
    );
    expect(events.last.classId, 'cell_phone');
    expect(events.last.geometry?.regionId, 'lower_right');
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

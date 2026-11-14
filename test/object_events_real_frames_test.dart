// Real COCO frames through the real object-event code.
//
// Each fixture in test/fixtures/object_events/ holds what the native engines
// return for one COCO val2017 image (exam YOLO model, 416 letterbox, strict
// YOLOv8 decode): the decoded `objects` and the raw tensor, stored sparse
// (only predictions with a best class score >= 0.25; the rest are zero, which
// decodes identically). The Rust decoder re-decodes the tensor exactly as in
// the app.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:students_ui_demo/face_demo/face_identity_person_gate.dart';
import 'package:students_ui_demo/proctoring_demo/native_vision_bridge.dart';
import 'package:students_ui_demo/proctoring_demo/object_event_persistence_gate.dart';
import 'package:students_ui_demo/proctoring_demo/optimized_vision_object_event_adapter.dart';
import 'package:students_ui_demo/proctoring_demo/optimized_vision_runtime_bridge.dart';
import 'package:students_ui_demo/proctoring_demo/person_count_policy.dart';
import 'package:students_ui_demo/rust/brain_core_runtime.dart';

OptimizedVisionRuntimeResult _frame(String name) {
  final fixture =
      jsonDecode(
            File('test/fixtures/object_events/$name.json').readAsStringSync(),
          )
          as Map<String, Object?>;
  final outputs = Map<String, Object?>.from(fixture['outputs']! as Map);
  final sparse = Map<String, Object?>.from(
    outputs.remove('yolo_output_sparse')! as Map,
  );
  final predictions = sparse['num_predictions']! as int;
  final attributes = sparse['attributes']! as int;
  final indices = (sparse['indices']! as List).cast<int>();
  final packed = base64Decode(sparse['values_b64']! as String);
  final values = packed.buffer.asFloat32List(
    packed.offsetInBytes,
    packed.length ~/ 4,
  );
  final dense = Float32List(predictions * attributes);
  for (var a = 0; a < attributes; a++) {
    for (var j = 0; j < indices.length; j++) {
      dense[a * predictions + indices[j]] = values[a * indices.length + j];
    }
  }
  outputs['yolo_output'] = dense;
  return OptimizedVisionRuntimeResult(
    available: true,
    backend: 'onnxRuntimeCpu',
    precision: 'int8',
    inferenceMs: 5,
    outputs: outputs,
    imageWidth: outputs['image_width']! as int,
    imageHeight: outputs['image_height']! as int,
  );
}

Set<String> _events(OptimizedVisionRuntimeResult frame) =>
    const OptimizedVisionObjectEventAdapter()
        .mapResult(frame)
        .map((decision) => decision.eventType)
        .toSet();

int _people(OptimizedVisionRuntimeResult frame) => PersonCountPolicy.count(
  PersonBox.fromObjects(frame.outputs['objects']! as List),
);

void main() {
  setUpAll(BrainCoreRuntime.ensureInitialized);

  test('a phone in the hand is reported', () {
    final frame = _frame('000000016598');
    expect(_events(frame), contains('yolo_phone_detected'));
    expect(_people(frame), 1);
  });

  test('a single person at a table raises nothing', () {
    final frame = _frame('000000025096');
    expect(_events(frame), isEmpty);
    expect(_people(frame), 1);
    expect(
      FaceIdentityPersonGate().evaluate(frame).state,
      FaceIdentityPersonGateState.accepted,
    );
  });

  test('a phone seen only as "remote" is a handheld-device note', () {
    final events = _events(_frame('000000052413'));
    expect(events, contains('yolo_handheld_device_detected'));
    expect(events, isNot(contains('yolo_phone_detected')));
  });

  test('two people side by side are counted as two', () {
    final frame = _frame('000000066771');
    expect(_people(frame), 2);
    expect(_events(frame), contains('yolo_phone_detected'));
    expect(
      FaceIdentityPersonGate().evaluate(frame).state,
      FaceIdentityPersonGateState.multiplePeopleDetected,
    );
    expect(_people(_frame('000000110449')), 2);
  });

  test('a dark board seen as a TV at 0.50 is not an extra screen', () {
    final frame = _frame('000000075612');
    final tv = (frame.outputs['objects']! as List).cast<Map>().where(
      (object) => object['label'] == 'tv',
    );
    expect(tv.single['confidence'] as num, lessThan(0.55));
    expect(_events(frame), isNot(contains('yolo_extra_screen_detected')));
  });

  test('a book is reported and a faint person is present but not counted', () {
    final frame = _frame('000000099182');
    expect(_events(frame), contains('yolo_book_or_paper_detected'));
    expect(_people(frame), 0);
    expect(
      FaceIdentityPersonGate().evaluate(frame).state,
      FaceIdentityPersonGateState.accepted,
    );
  });

  test('one frame with a phone among clean frames raises no event', () {
    final gate = ObjectEventPersistenceGate();
    final phone = _events(_frame('000000016598'));
    final clean = _events(_frame('000000025096'));
    final raised = <String>{};
    for (final events in [clean, clean, phone, clean, clean]) {
      raised.addAll(gate.observe(events));
    }
    expect(raised, isEmpty);
    // A phone that stays in view is reported.
    for (final events in [phone, phone]) {
      raised.addAll(gate.observe(events));
    }
    expect(raised, contains('yolo_phone_detected'));
  });

  test('without the Rust decoder the native detections are used', () {
    final frame = _frame('000000016598');
    final decisions = const OptimizedVisionObjectEventAdapter(
      nativeVision: DisabledNativeVisionBridge(),
    ).mapResult(frame);
    expect(
      decisions.map((decision) => decision.eventType),
      contains('yolo_phone_detected'),
    );
  });
}

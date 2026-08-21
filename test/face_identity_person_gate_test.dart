import 'package:flutter_test/flutter_test.dart';
import 'package:students_ui_demo/face_demo/face_identity_person_gate.dart';
import 'package:students_ui_demo/proctoring_demo/optimized_vision_runtime_bridge.dart';

void main() {
  final gate = FaceIdentityPersonGate();

  OptimizedVisionRuntimeResult result(Map<String, Object?> outputs) {
    return OptimizedVisionRuntimeResult(
      available: true,
      backend: 'onnxRuntimeCpu',
      precision: 'int8',
      inferenceMs: 8.0,
      outputs: outputs,
    );
  }

  group('FaceIdentityPersonGate.evaluate', () {
    test('accepts a scene with exactly one confident person', () {
      final outcome = gate.evaluate(
        result(<String, Object?>{
          'objects': <Map<String, Object?>>[
            <String, Object?>{'label': 'person', 'confidence': 0.91},
          ],
        }),
      );

      expect(outcome.state, FaceIdentityPersonGateState.accepted);
      expect(outcome.accepted, isTrue);
      expect(outcome.personCount, 1);
    });

    test('rejects a scene with no person detected', () {
      final outcome = gate.evaluate(
        result(<String, Object?>{
          'objects': <Map<String, Object?>>[
            <String, Object?>{'label': 'book', 'confidence': 0.8},
          ],
        }),
      );

      expect(outcome.state, FaceIdentityPersonGateState.noPersonDetected);
      expect(outcome.blocking, isTrue);
    });

    test('rejects a scene with more than one person for review', () {
      final outcome = gate.evaluate(
        result(<String, Object?>{
          'objects': <Map<String, Object?>>[
            <String, Object?>{'label': 'person', 'confidence': 0.9},
            <String, Object?>{'label': 'person', 'confidence': 0.85},
          ],
        }),
      );

      expect(outcome.state, FaceIdentityPersonGateState.multiplePeopleDetected);
      expect(outcome.personCount, 2);
      expect(outcome.blocking, isTrue);
    });

    test('ignores low-confidence person detections below the gate threshold', () {
      final outcome = gate.evaluate(
        result(<String, Object?>{
          'objects': <Map<String, Object?>>[
            <String, Object?>{'label': 'person', 'confidence': 0.1},
          ],
        }),
      );

      expect(outcome.state, FaceIdentityPersonGateState.noPersonDetected);
    });

    test('falls back to native person_count/multiple_people_likely aggregates', () {
      final single = gate.evaluate(
        result(<String, Object?>{'person_count': 1}),
      );
      final multiple = gate.evaluate(
        result(<String, Object?>{
          'person_count': 2,
          'multiple_people_likely': true,
        }),
      );

      expect(single.state, FaceIdentityPersonGateState.accepted);
      expect(multiple.state, FaceIdentityPersonGateState.multiplePeopleDetected);
    });

    test('reports the runtime as unavailable instead of faking a pass', () {
      final missing = gate.evaluate(null);
      final unavailable = gate.evaluate(
        const OptimizedVisionRuntimeResult(
          available: false,
          backend: 'onnxRuntimeCpu',
          precision: 'int8',
          inferenceMs: 0,
          outputs: <String, Object?>{},
        ),
      );

      expect(missing.state, FaceIdentityPersonGateState.runtimeUnavailable);
      expect(missing.accepted, isFalse);
      expect(missing.blocking, isFalse);
      expect(unavailable.state, FaceIdentityPersonGateState.runtimeUnavailable);
    });
  });
}

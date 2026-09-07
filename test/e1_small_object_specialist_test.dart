import 'package:flutter_test/flutter_test.dart';
import 'package:students_ui_demo/proctoring_demo/e1_small_object_specialist.dart';

void main() {
  group('E1SmallObjectCascadePlanner', () {
    const planner = E1SmallObjectCascadePlanner();

    test('plans wearable specialist from person anchor without claiming evidence', () {
      final requests = planner.plan(
        sessionId: 'attempt-001',
        sourceFrameId: 12,
        captureTimestampNs: 1000,
        imageWidth: 640,
        imageHeight: 480,
        baseLabels: const <String>['person'],
      );

      expect(requests, hasLength(1));
      final request = requests.single;
      expect(request.isValid, isTrue);
      expect(request.sourceFrameId, 12);
      expect(request.captureTimestampNs, 1000);
      expect(
        request.targets,
        containsAll(<E1SmallObjectTarget>[
          E1SmallObjectTarget.smartwatch,
          E1SmallObjectTarget.earbud,
        ]),
      );
      expect(request.roiHint.strategy, 'person_relative_wearable');
    });

    test('plans desk specialist only when a real desk anchor exists', () {
      final noAnchor = planner.plan(
        sessionId: 'attempt-001',
        sourceFrameId: 1,
        captureTimestampNs: 10,
        imageWidth: 640,
        imageHeight: 480,
        baseLabels: const <String>[],
      );
      expect(noAnchor, isEmpty);

      final withBook = planner.plan(
        sessionId: 'attempt-001',
        sourceFrameId: 2,
        captureTimestampNs: 20,
        imageWidth: 640,
        imageHeight: 480,
        baseLabels: const <String>['book'],
      );
      expect(withBook, hasLength(1));
      expect(
        withBook.single.targets,
        containsAll(<E1SmallObjectTarget>[
          E1SmallObjectTarget.tablet,
          E1SmallObjectTarget.paperNote,
          E1SmallObjectTarget.calculator,
        ]),
      );
    });
  });

  group('E1SmallObjectSpecialistObservation', () {
    test('accepts specialist evidence only with valid provenance and geometry', () {
      const observation = E1SmallObjectSpecialistObservation(
        canonicalObjectId: 'smartwatch',
        confidence: 0.88,
        boundingBox: <String, double>{
          'x': 0.2,
          'y': 0.3,
          'width': 0.1,
          'height': 0.1,
        },
        modelId: 'e1-small-object-specialist',
        modelVersion: 'test-version-1',
        sourceFrameId: 42,
        captureTimestampNs: 1000,
        inferenceTimestampNs: 1100,
      );

      expect(observation.isValid, isTrue);
    });

    test('rejects unsupported class, missing model provenance, and time reversal', () {
      const unsupported = E1SmallObjectSpecialistObservation(
        canonicalObjectId: 'phone',
        confidence: 0.9,
        boundingBox: <String, double>{
          'x': 0.1,
          'y': 0.1,
          'width': 0.2,
          'height': 0.2,
        },
        modelId: 'specialist',
        modelVersion: '1',
        sourceFrameId: 1,
        captureTimestampNs: 10,
        inferenceTimestampNs: 11,
      );
      const missingModel = E1SmallObjectSpecialistObservation(
        canonicalObjectId: 'earbud',
        confidence: 0.9,
        boundingBox: <String, double>{
          'x': 0.1,
          'y': 0.1,
          'width': 0.2,
          'height': 0.2,
        },
        modelId: '',
        modelVersion: '1',
        sourceFrameId: 1,
        captureTimestampNs: 10,
        inferenceTimestampNs: 11,
      );
      const reversedTime = E1SmallObjectSpecialistObservation(
        canonicalObjectId: 'calculator',
        confidence: 0.9,
        boundingBox: <String, double>{
          'x': 0.1,
          'y': 0.1,
          'width': 0.2,
          'height': 0.2,
        },
        modelId: 'specialist',
        modelVersion: '1',
        sourceFrameId: 1,
        captureTimestampNs: 20,
        inferenceTimestampNs: 19,
      );

      expect(unsupported.isValid, isFalse);
      expect(missingModel.isValid, isFalse);
      expect(reversedTime.isValid, isFalse);
    });
  });
}

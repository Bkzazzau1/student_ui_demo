import 'package:flutter_test/flutter_test.dart';
import 'package:students_ui_demo/proctoring_demo/e1_small_object_specialist.dart';
import 'package:students_ui_demo/proctoring_demo/model_event_v1.dart';

ModelEventV1Payload _baseEvent({
  required String canonicalObjectId,
  Map<String, Object?>? box,
  String sessionId = 'attempt-001',
  int? sourceFrameId = 12,
  int captureTimestampNs = 1000,
  double confidence = 0.9,
}) {
  return ModelEventV1Payload(
    sessionId: sessionId,
    eventId: '$sessionId:$canonicalObjectId:$captureTimestampNs',
    sourceFrameId: sourceFrameId,
    captureTimestampNs: captureTimestampNs,
    inferenceTimestampNs: captureTimestampNs + 10,
    modelId: 'base-e1',
    modelVersion: '1',
    trackId: null,
    classId: canonicalObjectId,
    confidence: confidence,
    quality: null,
    geometry: box == null
        ? null
        : ModelEventGeometryV1(
            coordinateSpace: 'normalized_frame',
            boundingBox: box,
          ),
    validityInterval: ModelEventValidityIntervalV1(
      startTimestampNs: captureTimestampNs,
      endTimestampNs: captureTimestampNs,
    ),
    metadata: <String, Object?>{
      'canonical_object_id': canonicalObjectId,
      'modality': 'vision',
    },
  );
}

void main() {
  group('E1SmallObjectCascadePlanner', () {
    const planner = E1SmallObjectCascadePlanner();

    test('derives separate ear and watch ROIs from real person geometry', () {
      final requests = planner.plan(
        sessionId: 'attempt-001',
        sourceFrameId: 12,
        captureTimestampNs: 1000,
        imageWidth: 640,
        imageHeight: 480,
        baseEvents: <ModelEventV1Payload>[
          _baseEvent(
            canonicalObjectId: 'person',
            box: const <String, Object?>{
              'x': 0.2,
              'y': 0.1,
              'width': 0.4,
              'height': 0.8,
            },
          ),
        ],
      );

      expect(requests, hasLength(2));
      final ear = requests.firstWhere(
        (request) => request.targets.contains(E1SmallObjectTarget.earbud),
      );
      final watch = requests.firstWhere(
        (request) => request.targets.contains(E1SmallObjectTarget.smartwatch),
      );

      expect(ear.isValid, isTrue);
      expect(ear.roiHint.strategy, 'person_head_earbud');
      expect(ear.roiHint.roi!.x, closeTo(0.152, 0.0001));
      expect(ear.roiHint.roi!.y, closeTo(0.06, 0.0001));
      expect(ear.roiHint.roi!.width, closeTo(0.496, 0.0001));
      expect(ear.roiHint.roi!.height, closeTo(0.408, 0.0001));

      expect(watch.isValid, isTrue);
      expect(watch.roiHint.strategy, 'person_arm_watch');
      expect(watch.roiHint.roi!.x, closeTo(0.128, 0.0001));
      expect(watch.roiHint.roi!.y, closeTo(0.3, 0.0001));
      expect(watch.roiHint.roi!.width, closeTo(0.544, 0.0001));
      expect(watch.roiHint.roi!.height, closeTo(0.64, 0.0001));
    });

    test('clips person-derived ROIs to the source frame', () {
      final requests = planner.plan(
        sessionId: 'attempt-001',
        sourceFrameId: 12,
        captureTimestampNs: 1000,
        imageWidth: 640,
        imageHeight: 480,
        baseEvents: <ModelEventV1Payload>[
          _baseEvent(
            canonicalObjectId: 'person',
            box: const <String, Object?>{
              'x': 0.0,
              'y': 0.0,
              'width': 0.2,
              'height': 0.5,
            },
          ),
        ],
      );

      expect(requests, hasLength(2));
      for (final request in requests) {
        final roi = request.roiHint.roi!;
        expect(roi.isValid, isTrue);
        expect(roi.x, greaterThanOrEqualTo(0.0));
        expect(roi.y, greaterThanOrEqualTo(0.0));
        expect(roi.right, lessThanOrEqualTo(1.0001));
        expect(roi.bottom, lessThanOrEqualTo(1.0001));
      }
    });

    test('builds one bounded desk union from real desk-anchor geometry', () {
      final requests = planner.plan(
        sessionId: 'attempt-001',
        sourceFrameId: 12,
        captureTimestampNs: 1000,
        imageWidth: 640,
        imageHeight: 480,
        baseEvents: <ModelEventV1Payload>[
          _baseEvent(
            canonicalObjectId: 'book',
            box: const <String, Object?>{
              'x': 0.2,
              'y': 0.6,
              'width': 0.2,
              'height': 0.2,
            },
          ),
          _baseEvent(
            canonicalObjectId: 'laptop',
            box: const <String, Object?>{
              'x': 0.45,
              'y': 0.5,
              'width': 0.3,
              'height': 0.25,
            },
          ),
        ],
      );

      expect(requests, hasLength(1));
      final request = requests.single;
      expect(request.isValid, isTrue);
      expect(request.roiHint.strategy, 'desk_anchor_union');
      expect(
        request.targets,
        containsAll(<E1SmallObjectTarget>[
          E1SmallObjectTarget.tablet,
          E1SmallObjectTarget.paperNote,
          E1SmallObjectTarget.calculator,
        ]),
      );
      final roi = request.roiHint.roi!;
      expect(roi.x, lessThanOrEqualTo(0.2));
      expect(roi.y, lessThanOrEqualTo(0.5));
      expect(roi.right, greaterThanOrEqualTo(0.75));
      expect(roi.bottom, greaterThanOrEqualTo(0.8));
    });

    test('missing, malformed, or mismatched geometry produces no ROI request', () {
      final missing = planner.plan(
        sessionId: 'attempt-001',
        sourceFrameId: 12,
        captureTimestampNs: 1000,
        imageWidth: 640,
        imageHeight: 480,
        baseEvents: <ModelEventV1Payload>[
          _baseEvent(canonicalObjectId: 'person'),
        ],
      );
      expect(missing, isEmpty);

      final malformed = planner.plan(
        sessionId: 'attempt-001',
        sourceFrameId: 12,
        captureTimestampNs: 1000,
        imageWidth: 640,
        imageHeight: 480,
        baseEvents: <ModelEventV1Payload>[
          _baseEvent(
            canonicalObjectId: 'person',
            box: const <String, Object?>{
              'x': 0.9,
              'y': 0.1,
              'width': 0.3,
              'height': 0.4,
            },
          ),
        ],
      );
      expect(malformed, isEmpty);

      final wrongFrame = planner.plan(
        sessionId: 'attempt-001',
        sourceFrameId: 12,
        captureTimestampNs: 1000,
        imageWidth: 640,
        imageHeight: 480,
        baseEvents: <ModelEventV1Payload>[
          _baseEvent(
            canonicalObjectId: 'person',
            sourceFrameId: 99,
            box: const <String, Object?>{
              'x': 0.2,
              'y': 0.1,
              'width': 0.4,
              'height': 0.8,
            },
          ),
        ],
      );
      expect(wrongFrame, isEmpty);
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

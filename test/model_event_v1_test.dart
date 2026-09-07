import 'package:flutter_test/flutter_test.dart';
import 'package:students_ui_demo/proctoring_demo/model_event_v1.dart';

void main() {
  group('ModelEventV1Payload', () {
    test('serializes the complete frozen core field set', () {
      const event = ModelEventV1Payload(
        sessionId: 'session-001',
        eventId: 'event-001',
        sourceFrameId: 42,
        captureTimestampNs: 1000,
        inferenceTimestampNs: 1400,
        modelId: 'e1-yolo-exam-review',
        modelVersion: 'development-baseline-1',
        trackId: null,
        classId: 'cell_phone',
        confidence: 0.91,
        quality: 0.88,
        geometry: ModelEventGeometryV1(
          coordinateSpace: 'normalized_frame',
          boundingBox: <String, Object?>{
            'x': 0.5,
            'y': 0.4,
            'width': 0.2,
            'height': 0.3,
          },
        ),
        validityInterval: ModelEventValidityIntervalV1(
          startTimestampNs: 1000,
          endTimestampNs: 1600,
        ),
        metadata: <String, Object?>{'modality': 'vision'},
      );

      final json = event.toJson();
      expect(json.keys.toSet(), <String>{
        'schema_version',
        'session_id',
        'event_id',
        'source_frame_id',
        'capture_timestamp_ns',
        'inference_timestamp_ns',
        'model_id',
        'model_version',
        'track_id',
        'class_id',
        'confidence',
        'quality',
        'geometry',
        'validity_interval',
        'metadata',
      });
      expect(json['track_id'], isNull);
    });

    test('rejects inference timestamps earlier than capture', () {
      const event = ModelEventV1Payload(
        sessionId: 'session-001',
        eventId: 'event-002',
        sourceFrameId: null,
        captureTimestampNs: 2000,
        inferenceTimestampNs: 1999,
        modelId: 'e1-yolo-exam-review',
        modelVersion: 'development-baseline-1',
        trackId: null,
        classId: 'person',
        confidence: null,
        quality: null,
        geometry: null,
        validityInterval: ModelEventValidityIntervalV1(
          startTimestampNs: 2000,
        ),
      );

      expect(event.toJson, throwsFormatException);
    });

    test('preserves unknown optional evidence as null', () {
      const event = ModelEventV1Payload(
        sessionId: 'session-001',
        eventId: 'event-003',
        sourceFrameId: null,
        captureTimestampNs: 3000,
        inferenceTimestampNs: 3000,
        modelId: 'system-security',
        modelVersion: '1.0',
        trackId: null,
        classId: 'bluetooth_state_unknown',
        confidence: null,
        quality: null,
        geometry: null,
        validityInterval: ModelEventValidityIntervalV1(
          startTimestampNs: 3000,
        ),
      );

      final json = event.toJson();
      expect(json['source_frame_id'], isNull);
      expect(json['track_id'], isNull);
      expect(json['confidence'], isNull);
      expect(json['quality'], isNull);
      expect(json['geometry'], isNull);
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:students_ui_demo/proctoring_demo/e1_model_event_adapter.dart';
import 'package:students_ui_demo/proctoring_demo/native_vision_bridge.dart';

void main() {
  group('E1ModelEventAdapter', () {
    test('preserves frame timing, class id and canonical taxonomy metadata', () {
      const review = NativeObjectReviewSnapshot(
        detections: <NativeVisionDetectionSnapshot>[
          NativeVisionDetectionSnapshot(
            classId: 67,
            label: 'cell phone',
            confidence: 0.91,
            xCenter: 320,
            yCenter: 240,
            width: 128,
            height: 96,
            xMin: 256,
            yMin: 192,
            xMax: 384,
            yMax: 288,
          ),
        ],
        peopleCount: 0,
        phoneCount: 1,
        bookCount: 0,
        paperCount: 0,
        needsReview: true,
        attentionLevel: 'high_attention_required',
        reason: 'phone-like object may need human review',
      );
      const context = E1FrameInferenceContext(
        sessionId: 'attempt-001',
        sourceFrameId: 42,
        captureTimestampNs: 1_000_000,
        inferenceTimestampNs: 1_120_000,
        modelId: 'e1-yolo-exam-review',
        modelVersion: 'development-baseline-1',
        imageWidth: 640,
        imageHeight: 480,
        quality: 0.85,
        backend: 'directml',
        precision: 'fp16',
      );

      final events = const E1ModelEventAdapter().fromNativeReview(
        review: review,
        context: context,
      );

      expect(events, hasLength(2));
      final event = events.firstWhere((item) => item.classId == 'cell_phone');
      expect(event.sourceFrameId, 42);
      expect(event.captureTimestampNs, 1_000_000);
      expect(event.inferenceTimestampNs, 1_120_000);
      expect(event.trackId, isNull);
      expect(event.modelId, 'e1-yolo-exam-review');
      expect(event.modelVersion, 'development-baseline-1');
      expect(event.classId, 'cell_phone');
      expect(event.metadata['raw_label'], 'cell phone');
      expect(event.metadata['canonical_object_id'], 'phone');
      expect(event.metadata['object_group'], 'communication_device');
      expect(event.metadata['object_coverage'], 'base_detector');
      expect(event.metadata['taxonomy_version'], '1.0');
      final box = event.geometry!.boundingBox!;
      expect(box['x'], closeTo(0.4, 0.0001));
      expect(box['y'], closeTo(0.4, 0.0001));
      expect(box['width'], closeTo(0.2, 0.0001));
      expect(box['height'], closeTo(0.2, 0.0001));
      expect(event.metadata['persistent_tracking_available'], isFalse);

      final count = events.firstWhere((item) => item.classId == 'person_count');
      expect(count.sourceFrameId, 42);
      expect(count.captureTimestampNs, 1_000_000);
      expect(count.metadata['count'], 0);
      expect(count.geometry, isNull);
      expect(count.trackId, isNull);
      expect(count.metadata.containsKey('canonical_object_id'), isFalse);
    });

    test('does not invent persistent track IDs before Rust memory ingress', () {
      const review = NativeObjectReviewSnapshot(
        detections: <NativeVisionDetectionSnapshot>[
          NativeVisionDetectionSnapshot(
            classId: 0,
            label: 'person',
            confidence: 0.95,
            xCenter: 100,
            yCenter: 100,
            width: 50,
            height: 100,
            xMin: 75,
            yMin: 50,
            xMax: 125,
            yMax: 150,
          ),
        ],
        peopleCount: 1,
        phoneCount: 0,
        bookCount: 0,
        paperCount: 0,
        needsReview: false,
        attentionLevel: 'normal',
        reason: 'object review complete',
      );
      const context = E1FrameInferenceContext(
        sessionId: 'attempt-001',
        sourceFrameId: 1,
        captureTimestampNs: 10,
        inferenceTimestampNs: 11,
        modelId: 'e1-yolo-exam-review',
        modelVersion: 'development-baseline-1',
        imageWidth: 200,
        imageHeight: 200,
      );

      final events = const E1ModelEventAdapter().fromNativeReview(
        review: review,
        context: context,
      );
      final person = events.firstWhere((item) => item.classId == 'person');
      final count = events.firstWhere((item) => item.classId == 'person_count');
      expect(person.trackId, isNull);
      expect(person.metadata['canonical_object_id'], 'person');
      expect(person.metadata['object_coverage'], 'base_detector');
      expect(count.metadata['count'], 1);
    });

    test('keeps unknown detector labels explicit rather than inventing taxonomy', () {
      const review = NativeObjectReviewSnapshot(
        detections: <NativeVisionDetectionSnapshot>[
          NativeVisionDetectionSnapshot(
            classId: 999,
            label: 'mystery device',
            confidence: 0.70,
            xCenter: 50,
            yCenter: 50,
            width: 20,
            height: 20,
            xMin: 40,
            yMin: 40,
            xMax: 60,
            yMax: 60,
          ),
        ],
        peopleCount: 0,
        phoneCount: 0,
        bookCount: 0,
        paperCount: 0,
        needsReview: false,
        attentionLevel: 'normal',
        reason: 'object review complete',
      );
      const context = E1FrameInferenceContext(
        sessionId: 'attempt-001',
        sourceFrameId: 3,
        captureTimestampNs: 30,
        inferenceTimestampNs: 31,
        modelId: 'test-model',
        modelVersion: '1',
        imageWidth: 100,
        imageHeight: 100,
      );

      final event = const E1ModelEventAdapter()
          .fromNativeReview(review: review, context: context)
          .firstWhere((item) => item.classId == 'mystery_device');

      expect(event.metadata['canonical_object_id'], 'unknown');
      expect(event.metadata['object_coverage'], 'unknown');
    });

    test('emits explicit zero-person observation when no detections exist', () {
      const review = NativeObjectReviewSnapshot(
        detections: <NativeVisionDetectionSnapshot>[],
        peopleCount: 0,
        phoneCount: 0,
        bookCount: 0,
        paperCount: 0,
        needsReview: false,
        attentionLevel: 'normal',
        reason: 'object review complete',
      );
      const context = E1FrameInferenceContext(
        sessionId: 'attempt-001',
        sourceFrameId: 9,
        captureTimestampNs: 900,
        inferenceTimestampNs: 950,
        modelId: 'e1-yolo-exam-review',
        modelVersion: 'development-baseline-1',
        imageWidth: 640,
        imageHeight: 480,
      );

      final events = const E1ModelEventAdapter().fromNativeReview(
        review: review,
        context: context,
      );
      expect(events, hasLength(1));
      expect(events.single.classId, 'person_count');
      expect(events.single.metadata['count'], 0);
    });
  });
}

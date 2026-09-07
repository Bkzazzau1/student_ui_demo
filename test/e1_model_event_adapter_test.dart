import 'package:flutter_test/flutter_test.dart';
import 'package:students_ui_demo/proctoring_demo/e1_model_event_adapter.dart';
import 'package:students_ui_demo/proctoring_demo/native_vision_bridge.dart';

void main() {
  group('E1ModelEventAdapter', () {
    test('preserves timing and emits canonical normalized detection geometry', () {
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

      expect(events, hasLength(1));
      final event = events.single;
      expect(event.sourceFrameId, 42);
      expect(event.captureTimestampNs, 1_000_000);
      expect(event.inferenceTimestampNs, 1_120_000);
      expect(event.classId, 'phone');
      expect(event.trackId, isNull);
      expect(event.modelId, 'e1-yolo-exam-review');
      expect(event.modelVersion, 'development-baseline-1');
      final box = event.geometry!.boundingBox!;
      expect(box['x'], closeTo(0.4, 0.0001));
      expect(box['y'], closeTo(0.4, 0.0001));
      expect(box['width'], closeTo(0.2, 0.0001));
      expect(box['height'], closeTo(0.2, 0.0001));
      expect(event.metadata['raw_label'], 'cell phone');
      expect(event.metadata['canonical_taxonomy_id'], 'e1-exam-object-taxonomy');
      expect(event.metadata['canonical_taxonomy_version'], '1.0.0');
      expect(event.metadata['taxonomy_known_class'], isTrue);
      expect(event.metadata['required_detector_class'], isTrue);
      expect(event.metadata['tracking_assignment_stage'], 'not_applicable');
    });

    test('does not invent persistent track IDs before Rust ingress', () {
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

      final event = const E1ModelEventAdapter()
          .fromNativeReview(review: review, context: context)
          .single;
      expect(event.classId, 'person');
      expect(event.trackId, isNull);
      expect(event.metadata['tracking_assignment_stage'], 'rust_memory_ingress');
    });

    test('does not accept detector context wording as derived policy state', () {
      const review = NativeObjectReviewSnapshot(
        detections: <NativeVisionDetectionSnapshot>[
          NativeVisionDetectionSnapshot(
            classId: 0,
            label: 'additional person',
            confidence: 0.8,
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
        sessionId: 'attempt-002',
        sourceFrameId: 2,
        captureTimestampNs: 20,
        inferenceTimestampNs: 21,
        modelId: 'test-detector',
        modelVersion: '1.0.0',
        imageWidth: 200,
        imageHeight: 200,
      );

      final event = const E1ModelEventAdapter()
          .fromNativeReview(review: review, context: context)
          .single;
      expect(event.classId, 'person');
      expect(event.metadata['raw_label'], 'additional person');
      expect(event.metadata['tracking_assignment_stage'], 'rust_memory_ingress');
    });
  });
}

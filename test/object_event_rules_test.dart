import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:students_ui_demo/proctoring_demo/native_vision_bridge.dart';
import 'package:students_ui_demo/proctoring_demo/object_event_persistence_gate.dart';
import 'package:students_ui_demo/proctoring_demo/object_review_event_mapper.dart';
import 'package:students_ui_demo/proctoring_demo/optimized_vision_object_event_adapter.dart';
import 'package:students_ui_demo/proctoring_demo/person_count_policy.dart';
import 'package:students_ui_demo/proctoring_demo/proctoring_risk_policy.dart';
import 'package:students_ui_demo/proctoring_demo/visual_reflection_shadow_service.dart';

PersonBox _person(
  double confidence,
  double x1,
  double y1,
  double x2,
  double y2,
) => PersonBox(confidence: confidence, x1: x1, y1: y1, x2: x2, y2: y2);

void main() {
  group('ObjectEventPersistenceGate', () {
    test('one frame is never enough', () {
      final gate = ObjectEventPersistenceGate();
      expect(gate.observe(['yolo_phone_detected']), isEmpty);
      expect(gate.observe(<String>[]), isEmpty);
      expect(gate.observe(<String>[]), isEmpty);
      expect(gate.observe(['yolo_phone_detected']), isEmpty);
    });

    test('two of the last three frames raise the event', () {
      final gate = ObjectEventPersistenceGate();
      expect(gate.observe(['yolo_phone_detected']), isEmpty);
      expect(gate.observe(<String>[]), isEmpty);
      expect(gate.observe(['yolo_phone_detected']), {'yolo_phone_detected'});
      expect(gate.hits('yolo_phone_detected'), 2);
    });

    test('event types are tracked separately', () {
      final gate = ObjectEventPersistenceGate();
      gate.observe(['yolo_phone_detected']);
      expect(gate.observe(['yolo_extra_screen_detected']), isEmpty);
      expect(
        gate.observe(['yolo_phone_detected', 'yolo_extra_screen_detected']),
        {'yolo_phone_detected', 'yolo_extra_screen_detected'},
      );
    });
  });

  group('PersonCountPolicy', () {
    test('the most confident person always counts', () {
      expect(PersonCountPolicy.count([_person(0.9, 0, 0.1, 1, 1)]), 1);
    });

    test('hands at the bottom edge are not a second person', () {
      final people = [
        _person(0.92, 0.2, 0.05, 0.8, 0.9),
        _person(0.87, 0.0, 0.85, 0.25, 1.0), // a hand at the edge, 4% of frame
      ];
      expect(PersonCountPolicy.count(people), 1);
    });

    test('a real second person counts, even at the edge', () {
      final people = [
        _person(0.93, 0.0, 0.0, 0.54, 0.83),
        _person(0.90, 0.58, 0.0, 1.0, 0.88), // 37% of frame
      ];
      expect(PersonCountPolicy.count(people), 2);
    });

    test('faint detections are present but not counted', () {
      final people = [_person(0.5, 0.2, 0.2, 0.6, 0.9)];
      expect(PersonCountPolicy.count(people), 0);
      expect(PersonCountPolicy.anyonePresent(people), isTrue);
    });

    test('a person without a box is always counted', () {
      final people = PersonBox.fromObjects([
        {'label': 'person', 'confidence': 0.9},
        {'label': 'person', 'confidence': 0.85},
      ]);
      expect(PersonCountPolicy.count(people), 2);
    });
  });

  group('object labels', () {
    test('a remote is a handheld-device note that never pauses', () {
      final decisions = const ObjectReviewEventMapper().mapLabels(['remote']);
      expect(decisions.single.eventType, 'yolo_handheld_device_detected');
      final risk = ProctoringRiskPolicy.decisionFor(
        'yolo_handheld_device_detected',
      );
      expect(risk.points, greaterThan(0));
      expect(risk.shouldPause, isFalse);
    });

    test('extra screens need 0.55, other objects the model threshold', () {
      const adapter = OptimizedVisionObjectEventAdapter();
      final labels = adapter.extractObjectLabels(<String, Object?>{
        'objects': [
          {'label': 'tv', 'confidence': 0.50},
          {'label': 'laptop', 'confidence': 0.60},
          {'label': 'cell phone', 'confidence': 0.46},
        ],
      }, includeHeuristicFlags: false);
      expect(labels, ['cell phone', 'laptop']);
      expect(adapter.minimumConfidenceFor('TV'), 0.55);
    });

    test('YOLO results never use the substring flags', () {
      final labels = const OptimizedVisionObjectEventAdapter()
          .extractObjectLabels(<String, Object?>{
            'objects': const <Object?>[],
            'screen_glow': true,
          }, includeHeuristicFlags: false);
      expect(labels, isEmpty);
    });
  });

  group('VisualReflectionShadowService orientation', () {
    setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.android);
    tearDown(() => debugDefaultTargetPlatformOverride = null);

    // A 64x48 Android luma frame whose raw RIGHT columns (top two-thirds)
    // change between frames. With the sensor at 90 degrees the raw right
    // side is the bottom of the upright scene, the desk in front of the
    // student; unrotated, that strip never reaches the bottom rows.
    CameraImage frame(int value) {
      const width = 64;
      const height = 48;
      final luma = Uint8List(width * height)..fillRange(0, width * height, 90);
      for (var y = 0; y < height * 2 ~/ 3; y++) {
        for (var x = width - 16; x < width; x++) {
          luma[y * width + x] = value;
        }
      }
      // ignore: deprecated_member_use
      return CameraImage.fromPlatformData(<String, Object?>{
        'format': 35, // YUV_420_888
        'width': width,
        'height': height,
        'planes': [
          {
            'bytes': luma,
            'bytesPerRow': width,
            'bytesPerPixel': 1,
            'width': width,
            'height': height,
          },
        ],
      });
    }

    double lowerActivity(int rotation) {
      final service = VisualReflectionShadowService(
        nativeVision: const DisabledNativeVisionBridge(),
      );
      VisualReflectionShadowResult? last;
      for (var i = 0; i < 24; i++) {
        last =
            service.analyse(
              frame((i ~/ 6).isEven ? 40 : 220),
              rotationDegrees: rotation,
            ) ??
            last;
      }
      return last!.lowerFrameActivity;
    }

    test('motion on the upright desk area is seen as lower-frame', () {
      // The service analyses every 6th frame; the changing columns are the
      // raw right side, which is the upright bottom only at 90 degrees.
      expect(lowerActivity(90), greaterThan(0.1));
      expect(lowerActivity(0), lessThan(0.01));
    });
  });
}

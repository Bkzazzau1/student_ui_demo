import 'package:flutter_test/flutter_test.dart';
import 'package:students_ui_demo/proctoring_demo/proctoring_risk_policy.dart';

void main() {
  group('ProctoringRiskPolicy', () {
    test('maps official scores to levels', () {
      expect(ProctoringRiskPolicy.levelForScore(0), 'low');
      expect(ProctoringRiskPolicy.levelForScore(20), 'low');
      expect(ProctoringRiskPolicy.levelForScore(21), 'medium');
      expect(ProctoringRiskPolicy.levelForScore(50), 'medium');
      expect(ProctoringRiskPolicy.levelForScore(51), 'high');
      expect(ProctoringRiskPolicy.levelForScore(80), 'high');
      expect(ProctoringRiskPolicy.levelForScore(81), 'critical');
    });

    test('assigns points to major exam monitoring events', () {
      expect(ProctoringRiskPolicy.pointsFor('camera_unavailable'), 50);
      expect(ProctoringRiskPolicy.pointsFor('microphone_unavailable'), 35);
      expect(ProctoringRiskPolicy.pointsFor('multiple_people_detected'), 55);
      expect(ProctoringRiskPolicy.pointsFor('audio_voice_isolation_alert'), 35);
      expect(
        ProctoringRiskPolicy.pointsFor('audio_environment_noise_warning'),
        10,
      );
      expect(ProctoringRiskPolicy.pointsFor('gaze_head_pose_deviation'), 20);
      expect(
        ProctoringRiskPolicy.pointsFor('sustained_gaze_head_pose_deviation'),
        50,
      );
      expect(ProctoringRiskPolicy.pointsFor('exam_screen_focus_changed'), 15);
      expect(
        ProctoringRiskPolicy.decisionFor(
          'gaze_head_pose_deviation',
        ).shouldPause,
        isFalse,
      );
      expect(
        ProctoringRiskPolicy.decisionFor(
          'sustained_gaze_head_pose_deviation',
        ).shouldPause,
        isTrue,
      );
    });

    test('keeps monitor health warnings below pause level', () {
      final decision = ProctoringRiskPolicy.decisionFor(
        'gaze_head_pose_monitor_unavailable',
      );
      expect(decision.points, 10);
      expect(decision.level, 'low');
      expect(decision.shouldPause, isFalse);
    });

    test('scores camera runtime coordination without pausing the exam', () {
      final busy = ProctoringRiskPolicy.decisionFor('camera_runtime_busy');
      final deferred = ProctoringRiskPolicy.decisionFor(
        'review_clip_deferred_to_live_camera',
      );
      expect(busy.points, 10);
      expect(busy.shouldPause, isFalse);
      expect(deferred.points, 0);
      expect(deferred.shouldPause, isFalse);
    });

    test('keeps model gate status events informational only', () {
      final missing = ProctoringRiskPolicy.decisionFor(
        'object_model_asset_missing',
      );
      final ready = ProctoringRiskPolicy.decisionFor(
        'object_model_frame_gate_ready',
      );
      expect(missing.points, 0);
      expect(missing.shouldPause, isFalse);
      expect(ready.points, 0);
      expect(ready.shouldPause, isFalse);
    });

    test('prepares object detection event policy before adding the model', () {
      final phone = ProctoringRiskPolicy.decisionFor('yolo_phone_detected');
      final extraScreen = ProctoringRiskPolicy.decisionFor(
        'yolo_extra_screen_detected',
      );
      final bookOrPaper = ProctoringRiskPolicy.decisionFor(
        'yolo_book_or_paper_detected',
      );
      final calculator = ProctoringRiskPolicy.decisionFor(
        'yolo_calculator_detected',
      );

      expect(phone.points, 30);
      expect(phone.level, 'medium');
      expect(phone.shouldPause, isTrue);

      expect(extraScreen.points, 35);
      expect(extraScreen.level, 'medium');
      expect(extraScreen.shouldPause, isTrue);

      expect(bookOrPaper.points, 25);
      expect(bookOrPaper.level, 'medium');
      expect(bookOrPaper.shouldPause, isFalse);

      expect(calculator.points, 20);
      expect(calculator.level, 'low');
      expect(calculator.shouldPause, isFalse);
    });
  });
}

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

    test('assigns high-value points to major exam monitoring events', () {
      expect(ProctoringRiskPolicy.pointsFor('multiple_people_detected'), 55);
      expect(ProctoringRiskPolicy.pointsFor('audio_voice_isolation_alert'), 35);
      expect(ProctoringRiskPolicy.pointsFor('gaze_head_pose_deviation'), 20);
      expect(ProctoringRiskPolicy.pointsFor('exam_screen_focus_changed'), 15);
    });

    test('prepares first YOLO event policy before adding the model', () {
      final decision = ProctoringRiskPolicy.decisionFor('yolo_phone_detected');
      expect(decision.points, 30);
      expect(decision.level, 'medium');
      expect(decision.shouldPause, isTrue);
    });
  });
}

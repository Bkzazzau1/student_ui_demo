import 'package:flutter_test/flutter_test.dart';
import 'package:students_ui_demo/proctoring_demo/live_monitoring_profile.dart';

void main() {
  group('LiveMonitoringProfile', () {
    test('exam profile keeps strict pause behaviour', () {
      final profile = LiveMonitoringProfile.forAssessmentType('exam');

      expect(profile.mode, LiveMonitoringMode.strictExam);
      expect(profile.reviewAudience, 'invigilator');
      expect(profile.needsSystemChecks, isTrue);
      expect(profile.shouldPauseForEventType('camera_reconnect_timeout'), isTrue);
      expect(profile.shouldPauseForEventType('audio_voice_isolation_alert'), isTrue);
      expect(profile.shouldPauseForEventType('yolo_phone_detected'), isTrue);
      expect(profile.shouldPauseForEventType('gaze_head_pose_deviation'), isTrue);
      expect(profile.shouldPauseForEventType('system_monitoring_unavailable'), isTrue);
    });

    test('graded assessment profile sends issues to lecturer without pausing', () {
      final profile = LiveMonitoringProfile.forAssessmentType(
        'graded_assessment',
      );

      expect(profile.mode, LiveMonitoringMode.gradedAssessmentLight);
      expect(profile.reviewAudience, 'lecturer');
      expect(profile.needsSystemChecks, isFalse);
      expect(profile.shouldPauseForEventType('camera_reconnect_timeout'), isFalse);
      expect(profile.shouldPauseForEventType('audio_voice_isolation_alert'), isFalse);
      expect(profile.shouldPauseForEventType('yolo_phone_detected'), isFalse);
      expect(profile.shouldPauseForEventType('gaze_head_pose_deviation'), isFalse);
      expect(profile.shouldPauseForEventType('system_monitoring_unavailable'), isFalse);
    });

    test('standard profile does not pause attempts', () {
      final profile = LiveMonitoringProfile.forAssessmentType('practice');

      expect(profile.mode, LiveMonitoringMode.standard);
      expect(profile.strictPauseEnabled, isFalse);
      expect(profile.shouldPauseForEventType('multiple_people_detected'), isFalse);
    });

    test('review audience can be overridden', () {
      final profile = LiveMonitoringProfile.forAssessmentType(
        'graded_assessment',
        reviewAudience: 'course_lecturer',
      );

      expect(profile.reviewAudience, 'course_lecturer');
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:students_ui_demo/exam_demo/exam_lockdown_service.dart';
import 'package:students_ui_demo/proctoring_demo/proctoring_risk_policy.dart';

Map<Object?, Object?> _ipad({
  bool guidedAccess = true,
  bool captured = false,
  bool microphoneDenied = false,
}) => <Object?, Object?>{
  'supported': true,
  'platform': 'ios',
  'screen_capture_blocked': !captured,
  'screen_capture_active': captured,
  'clipboard_cleared': true,
  'output_muted': false,
  'microphone_muted': microphoneDenied,
  'lock_task_active': guidedAccess,
  'guided_access_required': true,
  'lock_mode': 'guided_access',
};

void main() {
  group('ExamDeviceReadiness on iPad', () {
    test('ready with Guided Access on and nothing capturing the screen', () {
      final readiness = ExamDeviceReadiness.fromMap(_ipad());
      expect(readiness.ready, isTrue);
      expect(readiness.usesGuidedAccess, isTrue);
      expect(readiness.lockTaskActive, isTrue);
    });

    test('asks for Guided Access when it is off', () {
      final readiness = ExamDeviceReadiness.fromMap(_ipad(guidedAccess: false));
      expect(readiness.ready, isTrue);
      expect(readiness.lockTaskActive, isFalse);
      expect(readiness.message, 'Turn on Guided Access to start the exam.');
    });

    test('screen recording or mirroring blocks the exam', () {
      final readiness = ExamDeviceReadiness.fromMap(_ipad(captured: true));
      expect(readiness.ready, isFalse);
      expect(readiness.screenCaptureActive, isTrue);
      expect(readiness.message, contains('screen recording'));
    });

    test('denied microphone access points to Settings', () {
      final readiness = ExamDeviceReadiness.fromMap(
        _ipad(microphoneDenied: true),
      );
      expect(readiness.ready, isFalse);
      expect(readiness.message, contains('Settings'));
    });

    test('Android maps are read as before', () {
      final readiness = ExamDeviceReadiness.fromMap(<Object?, Object?>{
        'supported': true,
        'screen_capture_blocked': true,
        'clipboard_cleared': true,
        'output_muted': false,
        'microphone_muted': false,
        'lock_task_active': true,
      });
      expect(readiness.ready, isTrue);
      expect(readiness.usesGuidedAccess, isFalse);
      expect(readiness.screenCaptureActive, isFalse);
    });
  });

  group('ExamLockdownEvent', () {
    test('Guided Access turned off', () {
      final event = ExamLockdownEvent.fromMap(<Object?, Object?>{
        'type': 'guided_access_changed',
        'enabled': false,
        'timestamp_ms': 1,
        'readiness': _ipad(guidedAccess: false),
      });
      expect(event.guidedAccessEnded, isTrue);
      expect(event.guidedAccessStarted, isFalse);
      expect(event.readiness.lockTaskActive, isFalse);
      expect(event.details.containsKey('readiness'), isFalse);
    });

    test('Guided Access turned back on', () {
      final event = ExamLockdownEvent.fromMap(<Object?, Object?>{
        'type': 'guided_access_changed',
        'enabled': true,
        'readiness': _ipad(),
      });
      expect(event.guidedAccessStarted, isTrue);
      expect(event.guidedAccessEnded, isFalse);
    });

    test('screen capture and screenshots', () {
      final started = ExamLockdownEvent.fromMap(<Object?, Object?>{
        'type': 'screen_capture_changed',
        'captured': true,
        'readiness': _ipad(captured: true),
      });
      expect(started.screenCaptureStarted, isTrue);
      final stopped = ExamLockdownEvent.fromMap(<Object?, Object?>{
        'type': 'screen_capture_changed',
        'captured': false,
        'readiness': _ipad(),
      });
      expect(stopped.screenCaptureStopped, isTrue);
      final shot = ExamLockdownEvent.fromMap(<Object?, Object?>{
        'type': 'screenshot_taken',
      });
      expect(shot.screenshotTaken, isTrue);
      expect(shot.readiness.supported, isFalse);
    });
  });

  test('iPad lockdown events are scored and pause the exam', () {
    for (final type in [
      'exam_guided_access_ended',
      'exam_screen_capture_started',
    ]) {
      final decision = ProctoringRiskPolicy.decisionFor(type);
      expect(decision.points, 55, reason: type);
      expect(decision.shouldPause, isTrue, reason: type);
    }
    expect(
      ProctoringRiskPolicy.decisionFor('exam_screenshot_taken').points,
      35,
    );
    expect(
      ProctoringRiskPolicy.decisionFor('exam_lockdown_restored').points,
      0,
    );
  });
}

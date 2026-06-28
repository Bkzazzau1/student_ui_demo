import 'package:flutter_test/flutter_test.dart';
import 'package:students_ui_demo/proctoring_demo/audio_event_evidence_policy.dart';

void main() {
  group('AudioEventEvidencePolicy', () {
    test('captures environment noise warnings as audio evidence', () {
      const policy = AudioEventEvidencePolicy();

      expect(
        policy.shouldCapture(
          eventType: 'audio_environment_noise_warning',
          severity: 'warning',
        ),
        isTrue,
      );
    });
  });
}

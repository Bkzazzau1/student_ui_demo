import 'package:flutter_test/flutter_test.dart';
import 'package:students_ui_demo/proctoring_demo/audio_fingerprint_isolation_service.dart';
import 'package:students_ui_demo/proctoring_demo/audio_live_event_mapper.dart';

void main() {
  group('AudioLiveEventMapper', () {
    const mapper = AudioLiveEventMapper();

    test('maps close and multiple voice labels to voice alert', () {
      expect(
        mapper.map(_result(label: 'near_voice'))?.eventType,
        'audio_voice_isolation_alert',
      );
      expect(
        mapper.map(_result(label: 'possible_multiple_voices'))?.eventType,
        'audio_voice_isolation_alert',
      );
    });

    test('maps far and whisper labels to background voice warning', () {
      expect(
        mapper.map(_result(label: 'far_or_background_voice'))?.eventType,
        'background_voice_environment_warning',
      );
      expect(
        mapper.map(_result(label: 'whisper_or_low_voice'))?.eventType,
        'background_voice_environment_warning',
      );
    });

    test('maps selected environment sounds to noise warning', () {
      for (final label in const <String>[
        'phone_ringtone_like_sound',
        'keyboard_or_tapping_sound',
        'vehicle_or_motorcycle_ambient',
        'unclear_environment_sound',
      ]) {
        expect(
          mapper.map(_result(label: label))?.eventType,
          'audio_environment_noise_warning',
        );
      }
    });

    test('keeps allowed ambient labels calm by default', () {
      for (final label in const <String>[
        'fan_ambient_sound',
        'generator_or_engine_ambient',
        'quiet_or_low_noise',
        'steady_allowed_ambient_noise',
      ]) {
        expect(mapper.map(_result(label: label)), isNull);
        expect(mapper.isAllowedAmbient(_result(label: label)), isTrue);
      }
    });
  });
}

AudioIsolationResult _result({
  required String label,
  bool nearVoiceLikely = false,
  bool possibleFarVoiceLikely = false,
  bool allowedAmbientLikely = false,
}) {
  return AudioIsolationResult(
    rms: 0.01,
    peak: 0.04,
    zeroCrossingRate: 0.08,
    dynamicVariation: 0.01,
    voiceConfidence: 0.5,
    repeatedFingerprint: false,
    fingerprint: 'test',
    label: label,
    humanVoiceLikely: nearVoiceLikely,
    nearVoiceLikely: nearVoiceLikely,
    possibleFarVoiceLikely: possibleFarVoiceLikely,
    allowedAmbientLikely: allowedAmbientLikely,
  );
}

import 'audio_fingerprint_isolation_service.dart';

class AudioLiveEventDecision {
  const AudioLiveEventDecision({
    required this.eventType,
    required this.severity,
    required this.message,
  });

  final String eventType;
  final String severity;
  final String message;
}

class AudioLiveEventMapper {
  const AudioLiveEventMapper();

  AudioLiveEventDecision? map(AudioIsolationResult result) {
    final label = _normalize(result.label);
    if (_nearVoiceLabels.contains(label) || result.nearVoiceLikely) {
      return const AudioLiveEventDecision(
        eventType: 'audio_voice_isolation_alert',
        severity: 'high',
        message: 'Voice was noticed close to the exam audio environment.',
      );
    }
    if (_backgroundVoiceLabels.contains(label) ||
        result.possibleFarVoiceLikely) {
      return const AudioLiveEventDecision(
        eventType: 'background_voice_environment_warning',
        severity: 'warning',
        message:
            'Background voice was noticed. Please improve your environment.',
      );
    }
    if (_environmentNoiseLabels.contains(label)) {
      return const AudioLiveEventDecision(
        eventType: 'audio_environment_noise_warning',
        severity: 'warning',
        message:
            'Environment sound was noticed. Please keep the exam area quiet.',
      );
    }
    return null;
  }

  bool isAllowedAmbient(AudioIsolationResult result) {
    final label = _normalize(result.label);
    return result.allowedAmbientLikely || _allowedAmbientLabels.contains(label);
  }

  static const Set<String> _nearVoiceLabels = <String>{
    'near_voice',
    'near_voice_noticed',
    'possible_multiple_voices',
    'multiple_voices',
  };

  static const Set<String> _backgroundVoiceLabels = <String>{
    'far_or_background_voice',
    'possible_far_or_background_voice',
    'whisper_or_low_voice',
  };

  static const Set<String> _environmentNoiseLabels = <String>{
    'phone_ringtone_like_sound',
    'keyboard_or_tapping_sound',
    'vehicle_or_motorcycle_ambient',
    'unclear_environment_sound',
  };

  static const Set<String> _allowedAmbientLabels = <String>{
    'fan_ambient_sound',
    'generator_or_engine_ambient',
    'quiet_or_low_noise',
    'steady_allowed_ambient_noise',
  };

  String _normalize(String label) {
    return label.trim().toLowerCase().replaceAll(RegExp(r'[\s\-]+'), '_');
  }
}

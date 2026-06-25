class AudioEventEvidencePolicy {
  const AudioEventEvidencePolicy();

  static const Set<String> defaultAudioEvidenceEvents = <String>{
    'audio_voice_isolation_alert',
    'background_voice_environment_warning',
    'audio_repeated_fingerprint_detected',
    'microphone_reconnect_timeout',
  };

  bool shouldCapture({
    required String eventType,
    required String severity,
  }) {
    final type = eventType.trim().toLowerCase();
    if (defaultAudioEvidenceEvents.contains(type)) return true;

    final level = severity.trim().toLowerCase();
    return type.contains('audio') &&
        (level == 'warning' || level == 'high' || level == 'critical');
  }
}

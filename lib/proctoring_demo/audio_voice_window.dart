/// Decides "sustained voice" from how long voice was heard, not from how
/// many audio chunks arrived.
///
/// Platforms deliver microphone audio in chunks of 40-100 ms. Counting three
/// voice chunks meant 0.1-0.3 s of sound (one word, a cough, typing) paused
/// a strict exam, and the same sound gave different results on different
/// devices. Here near voice must add up to [nearVoiceMs] within the last
/// [nearWindowMs], and background voice to [backgroundVoiceMs] within
/// [backgroundWindowMs].
class AudioVoiceWindow {
  AudioVoiceWindow({
    this.nearVoiceMs = 600,
    this.nearWindowMs = 3000,
    this.backgroundVoiceMs = 1500,
    this.backgroundWindowMs = 5000,
  });

  final double nearVoiceMs;
  final int nearWindowMs;
  final double backgroundVoiceMs;
  final int backgroundWindowMs;

  final List<_VoiceSpan> _spans = <_VoiceSpan>[];

  /// Records one chunk ending at [atMs] lasting [durationMs].
  AudioVoiceState add({
    required int atMs,
    required double durationMs,
    required bool nearVoice,
    required bool backgroundVoice,
  }) {
    if (nearVoice || backgroundVoice) {
      _spans.add(_VoiceSpan(atMs, durationMs, nearVoice: nearVoice));
    }
    final oldest =
        atMs -
        (nearWindowMs > backgroundWindowMs ? nearWindowMs : backgroundWindowMs);
    _spans.removeWhere((span) => span.atMs < oldest);
    var near = 0.0;
    var anyVoice = 0.0;
    for (final span in _spans) {
      if (span.nearVoice && span.atMs >= atMs - nearWindowMs) {
        near += span.durationMs;
      }
      if (span.atMs >= atMs - backgroundWindowMs) {
        anyVoice += span.durationMs;
      }
    }
    return AudioVoiceState(
      nearVoiceMs: near,
      voiceMs: anyVoice,
      nearVoiceSustained: near >= nearVoiceMs,
      backgroundVoiceSustained:
          near < nearVoiceMs && anyVoice >= backgroundVoiceMs,
    );
  }

  void reset() => _spans.clear();
}

class AudioVoiceState {
  const AudioVoiceState({
    required this.nearVoiceMs,
    required this.voiceMs,
    required this.nearVoiceSustained,
    required this.backgroundVoiceSustained,
  });

  /// Near voice heard in the near window.
  final double nearVoiceMs;

  /// Any voice (near or background) heard in the background window.
  final double voiceMs;
  final bool nearVoiceSustained;
  final bool backgroundVoiceSustained;

  Map<String, Object?> toJson() => <String, Object?>{
    'near_voice_ms': nearVoiceMs.round(),
    'voice_ms': voiceMs.round(),
  };
}

class _VoiceSpan {
  const _VoiceSpan(this.atMs, this.durationMs, {required this.nearVoice});

  final int atMs;
  final double durationMs;
  final bool nearVoice;
}

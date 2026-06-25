import 'dart:typed_data';

class NativeAudioIntelligenceSnapshot {
  const NativeAudioIntelligenceSnapshot({
    required this.ready,
    required this.label,
    required this.rms,
    required this.peak,
    required this.zeroCrossingRate,
    required this.dynamicVariation,
    required this.voiceConfidence,
    required this.nearVoiceLikely,
    required this.possibleFarVoiceLikely,
    required this.allowedAmbientLikely,
    required this.repeatedFingerprint,
    required this.fingerprint,
  });

  final bool ready;
  final String label;
  final double rms;
  final double peak;
  final double zeroCrossingRate;
  final double dynamicVariation;
  final double voiceConfidence;
  final bool nearVoiceLikely;
  final bool possibleFarVoiceLikely;
  final bool allowedAmbientLikely;
  final bool repeatedFingerprint;
  final String fingerprint;
}

abstract class NativeAudioIntelligenceBridge {
  NativeAudioIntelligenceSnapshot? analysePcm16({
    required Uint8List bytes,
    required int sampleRate,
    String? previousFingerprint,
  });
}

class DisabledNativeAudioIntelligenceBridge implements NativeAudioIntelligenceBridge {
  const DisabledNativeAudioIntelligenceBridge();

  @override
  NativeAudioIntelligenceSnapshot? analysePcm16({
    required Uint8List bytes,
    required int sampleRate,
    String? previousFingerprint,
  }) {
    return null;
  }
}

/// Temporary non-breaking bridge while FRB bindings are regenerated for
/// `native/brain_core/src/api/audio_intelligence.rs`.
///
/// After codegen, replace the body of [analysePcm16] with a call to the
/// generated Rust API:
///
/// `audio_intelligence.analyzeAudioPcm16(...)`
class GeneratedNativeAudioIntelligenceBridge implements NativeAudioIntelligenceBridge {
  const GeneratedNativeAudioIntelligenceBridge();

  @override
  NativeAudioIntelligenceSnapshot? analysePcm16({
    required Uint8List bytes,
    required int sampleRate,
    String? previousFingerprint,
  }) {
    return null;
  }
}

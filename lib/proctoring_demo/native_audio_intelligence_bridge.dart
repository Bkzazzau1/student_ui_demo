import 'dart:typed_data';

import '../rust/api/audio_intelligence.dart' as native_audio;
import '../rust/frb_generated.dart';

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

class DisabledNativeAudioIntelligenceBridge
    implements NativeAudioIntelligenceBridge {
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

class GeneratedNativeAudioIntelligenceBridge
    implements NativeAudioIntelligenceBridge {
  const GeneratedNativeAudioIntelligenceBridge();

  static Future<void>? _nativeInit;
  static bool _nativeReady = false;
  static bool _nativeFailed = false;

  @override
  NativeAudioIntelligenceSnapshot? analysePcm16({
    required Uint8List bytes,
    required int sampleRate,
    String? previousFingerprint,
  }) {
    if (!_nativeReady) {
      if (!_nativeFailed) {
        _nativeInit ??= _ensureNativeReady().then((ready) {
          _nativeReady = ready;
          _nativeFailed = !ready;
        });
      }
      return null;
    }

    try {
      final result = native_audio.analyzeAudioPcm16(
        bytes: bytes,
        sampleRate: sampleRate,
        previousFingerprint: previousFingerprint,
      );
      if (result == null) return null;
      return NativeAudioIntelligenceSnapshot(
        ready: result.ready,
        label: result.label,
        rms: result.rms,
        peak: result.peak,
        zeroCrossingRate: result.zeroCrossingRate,
        dynamicVariation: result.dynamicVariation,
        voiceConfidence: result.voiceConfidence,
        nearVoiceLikely: result.nearVoiceLikely,
        possibleFarVoiceLikely: result.possibleFarVoiceLikely,
        allowedAmbientLikely: result.allowedAmbientLikely,
        repeatedFingerprint: result.repeatedFingerprint,
        fingerprint: result.fingerprint,
      );
    } catch (_) {
      return null;
    }
  }

  static Future<bool> _ensureNativeReady() async {
    try {
      await BrainCoreApi.init();
      return true;
    } catch (_) {
      return false;
    }
  }
}

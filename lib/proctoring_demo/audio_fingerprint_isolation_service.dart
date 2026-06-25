import 'dart:math' as math;
import 'dart:typed_data';

import 'native_audio_intelligence_bridge.dart';

class AudioIsolationResult {
  const AudioIsolationResult({
    required this.rms,
    required this.peak,
    required this.zeroCrossingRate,
    required this.dynamicVariation,
    required this.voiceConfidence,
    required this.repeatedFingerprint,
    required this.fingerprint,
    required this.label,
    required this.humanVoiceLikely,
    required this.nearVoiceLikely,
    required this.possibleFarVoiceLikely,
    required this.allowedAmbientLikely,
  });

  final double rms;
  final double peak;
  final double zeroCrossingRate;
  final double dynamicVariation;
  final double voiceConfidence;
  final bool repeatedFingerprint;
  final String fingerprint;
  final String label;
  final bool humanVoiceLikely;
  final bool nearVoiceLikely;
  final bool possibleFarVoiceLikely;
  final bool allowedAmbientLikely;

  Map<String, Object?> toJson() => <String, Object?>{
        'rms': rms,
        'peak': peak,
        'zero_crossing_rate': zeroCrossingRate,
        'dynamic_variation': dynamicVariation,
        'voice_confidence': voiceConfidence,
        'repeated_fingerprint': repeatedFingerprint,
        'fingerprint': fingerprint,
        'label': label,
        'human_voice_likely': humanVoiceLikely,
        'near_voice_likely': nearVoiceLikely,
        'possible_far_voice_likely': possibleFarVoiceLikely,
        'allowed_ambient_likely': allowedAmbientLikely,
      };
}

class AudioFingerprintIsolationService {
  AudioFingerprintIsolationService({
    NativeAudioIntelligenceBridge nativeBridge =
        const GeneratedNativeAudioIntelligenceBridge(),
    this.sampleRate = 44100,
  }) : _nativeBridge = nativeBridge;

  final NativeAudioIntelligenceBridge _nativeBridge;
  final int sampleRate;

  final List<double> _recentRms = <double>[];
  final List<double> _recentPeak = <double>[];
  final List<double> _recentZcr = <double>[];
  final List<double> _recentSlope = <double>[];
  final List<String> _recentFingerprints = <String>[];
  String? _lastNativeFingerprint;

  AudioIsolationResult? analysePcm16(Uint8List chunk) {
    if (chunk.length < 128) return null;

    final nativeResult = _nativeBridge.analysePcm16(
      bytes: chunk,
      sampleRate: sampleRate,
      previousFingerprint: _lastNativeFingerprint,
    );
    if (nativeResult != null && nativeResult.ready) {
      _lastNativeFingerprint = nativeResult.fingerprint;
      return _fromNative(nativeResult);
    }

    final data = ByteData.sublistView(chunk);
    var totalSquares = 0.0;
    var peak = 0.0;
    var zeroCrossings = 0;
    var count = 0;
    var previous = 0.0;
    var previousSet = false;
    var slopeEnergy = 0.0;

    for (var i = 0; i + 1 < chunk.length; i += 2) {
      final sample = data.getInt16(i, Endian.little) / 32768.0;
      final absSample = sample.abs();
      peak = math.max(peak, absSample);
      totalSquares += sample * sample;
      if (previousSet) {
        if ((sample >= 0 && previous < 0) || (sample < 0 && previous >= 0)) {
          zeroCrossings++;
        }
        final diff = sample - previous;
        slopeEnergy += diff * diff;
      }
      previous = sample;
      previousSet = true;
      count++;
    }

    if (count == 0) return null;
    final rms = math.sqrt(totalSquares / count).clamp(0.0, 1.0);
    final zcr = (zeroCrossings / count).clamp(0.0, 1.0);
    final slope = math.sqrt(slopeEnergy / math.max(1, count - 1)).clamp(0.0, 1.0);

    _pushRecent(_recentRms, rms, 32);
    _pushRecent(_recentPeak, peak, 32);
    _pushRecent(_recentZcr, zcr, 32);
    _pushRecent(_recentSlope, slope, 32);

    final variation = _variation(_recentRms);
    final peakVariation = _variation(_recentPeak);
    final recentPeak = _recentPeak.isEmpty ? peak : _recentPeak.reduce(math.max);
    final avgPeak = _average(_recentPeak);
    final avgZcr = _average(_recentZcr);
    final avgSlope = _average(_recentSlope);
    final voiceConfidence = _voiceConfidence(
      rms: rms,
      peak: peak,
      recentPeak: recentPeak,
      avgPeak: avgPeak,
      zcr: zcr,
      avgZcr: avgZcr,
      variation: variation,
      peakVariation: peakVariation,
      slope: slope,
      avgSlope: avgSlope,
    );
    final fingerprint = _fingerprint(
      rms: rms,
      peak: peak,
      zcr: zcr,
      slope: slope,
      variation: variation,
    );
    final repeated = _recentFingerprints.contains(fingerprint);
    _recentFingerprints.add(fingerprint);
    if (_recentFingerprints.length > 48) {
      _recentFingerprints.removeRange(0, _recentFingerprints.length - 48);
    }

    final steadyNoise = rms > 0.006 && variation < 0.006 && zcr < 0.20 && peakVariation < 0.025;
    final quiet = rms < 0.008 && peak < 0.050;
    final voiceTexture = voiceConfidence >= 0.40;
    final nearVoiceLikely = voiceConfidence >= 0.52 &&
        (rms >= 0.018 || peak >= 0.075 || recentPeak >= 0.100);
    final possibleFarVoiceLikely = !nearVoiceLikely &&
        voiceTexture &&
        !steadyNoise &&
        (rms < 0.024 || peak < 0.095 || recentPeak < 0.120);
    final humanVoiceLikely = nearVoiceLikely;
    final allowedAmbientLikely = !nearVoiceLikely && !possibleFarVoiceLikely && (quiet || steadyNoise);
    final label = nearVoiceLikely
        ? 'near_voice_noticed'
        : possibleFarVoiceLikely
            ? 'possible_far_or_background_voice'
            : quiet
                ? 'quiet_or_low_noise'
                : steadyNoise
                    ? 'steady_allowed_ambient_noise'
                    : 'unclear_environment_sound';

    return AudioIsolationResult(
      rms: rms,
      peak: peak,
      zeroCrossingRate: zcr,
      dynamicVariation: variation,
      voiceConfidence: voiceConfidence,
      repeatedFingerprint: repeated,
      fingerprint: fingerprint,
      label: label,
      humanVoiceLikely: humanVoiceLikely,
      nearVoiceLikely: nearVoiceLikely,
      possibleFarVoiceLikely: possibleFarVoiceLikely,
      allowedAmbientLikely: allowedAmbientLikely,
    );
  }

  AudioIsolationResult _fromNative(NativeAudioIntelligenceSnapshot native) {
    final nearVoiceLikely = native.nearVoiceLikely;
    final possibleFarVoiceLikely = native.possibleFarVoiceLikely;
    final allowedAmbientLikely = native.allowedAmbientLikely;
    final label = nearVoiceLikely
        ? 'near_voice_noticed'
        : possibleFarVoiceLikely
            ? 'possible_far_or_background_voice'
            : allowedAmbientLikely
                ? 'steady_allowed_ambient_noise'
                : native.label;

    return AudioIsolationResult(
      rms: native.rms,
      peak: native.peak,
      zeroCrossingRate: native.zeroCrossingRate,
      dynamicVariation: native.dynamicVariation,
      voiceConfidence: native.voiceConfidence,
      repeatedFingerprint: native.repeatedFingerprint,
      fingerprint: native.fingerprint,
      label: label,
      humanVoiceLikely: nearVoiceLikely,
      nearVoiceLikely: nearVoiceLikely,
      possibleFarVoiceLikely: possibleFarVoiceLikely,
      allowedAmbientLikely: allowedAmbientLikely,
    );
  }

  void _pushRecent(List<double> values, double value, int maxLength) {
    values.add(value);
    if (values.length > maxLength) {
      values.removeRange(0, values.length - maxLength);
    }
  }

  double _voiceConfidence({
    required double rms,
    required double peak,
    required double recentPeak,
    required double avgPeak,
    required double zcr,
    required double avgZcr,
    required double variation,
    required double peakVariation,
    required double slope,
    required double avgSlope,
  }) {
    var score = 0.0;
    final peakToRms = peak / math.max(rms, 0.0008);
    final recentPeakToAvgPeak = recentPeak / math.max(avgPeak, 0.0008);
    final speechZcr = (zcr >= 0.018 && zcr <= 0.28) || (avgZcr >= 0.018 && avgZcr <= 0.28);
    final speechTexture = slope >= 0.0025 || avgSlope >= 0.0025;

    if (rms >= 0.0012 && rms <= 0.60) score += 0.10;
    if (peak >= 0.018) score += 0.16;
    if (recentPeak >= 0.030) score += 0.12;
    if (peakToRms >= 3.0) score += 0.12;
    if (recentPeakToAvgPeak >= 1.8) score += 0.10;
    if (speechZcr) score += 0.18;
    if (speechTexture) score += 0.18;
    if (variation >= 0.0007) score += 0.08;
    if (peakVariation >= 0.0025) score += 0.10;
    if (rms > 0.75 || zcr > 0.50) score -= 0.16;
    return score.clamp(0.0, 1.0);
  }

  String _fingerprint({
    required double rms,
    required double peak,
    required double zcr,
    required double slope,
    required double variation,
  }) {
    final parts = <int>[
      (rms * 1000).round().clamp(0, 999),
      (peak * 1000).round().clamp(0, 999),
      (zcr * 1000).round().clamp(0, 999),
      (slope * 1000).round().clamp(0, 999),
      (variation * 1000).round().clamp(0, 999),
    ];
    var hash = 0xcbf29ce484222325;
    const prime = 0x100000001b3;
    for (final part in parts) {
      hash ^= part;
      hash = (hash * prime) & 0xFFFFFFFFFFFFFFFF;
    }
    return hash.toRadixString(16).padLeft(16, '0');
  }

  double _variation(List<double> samples) {
    if (samples.length < 2) return 0;
    var total = 0.0;
    for (var i = 1; i < samples.length; i++) {
      total += (samples[i] - samples[i - 1]).abs();
    }
    return total / (samples.length - 1);
  }

  double _average(List<double> samples) {
    if (samples.isEmpty) return 0;
    return samples.fold<double>(0, (sum, value) => sum + value) / samples.length;
  }
}

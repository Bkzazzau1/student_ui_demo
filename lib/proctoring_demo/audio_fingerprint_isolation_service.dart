import 'dart:math' as math;
import 'dart:typed_data';

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
        'allowed_ambient_likely': allowedAmbientLikely,
      };
}

class AudioFingerprintIsolationService {
  final List<double> _recentRms = <double>[];
  final List<String> _recentFingerprints = <String>[];

  AudioIsolationResult? analysePcm16(Uint8List chunk) {
    if (chunk.length < 128) return null;
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

    _recentRms.add(rms);
    if (_recentRms.length > 32) {
      _recentRms.removeRange(0, _recentRms.length - 32);
    }
    final variation = _variation(_recentRms);
    final voiceConfidence = _voiceConfidence(rms: rms, zcr: zcr, variation: variation, slope: slope);
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

    final steadyNoise = rms > 0.03 && variation < 0.025 && zcr < 0.24;
    final quiet = rms < 0.025 && peak < 0.11;
    final humanVoiceLikely = voiceConfidence >= 0.68;
    final allowedAmbientLikely = !humanVoiceLikely && (quiet || steadyNoise);
    final label = humanVoiceLikely
        ? 'human_voice_likely'
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
      allowedAmbientLikely: allowedAmbientLikely,
    );
  }

  double _voiceConfidence({
    required double rms,
    required double zcr,
    required double variation,
    required double slope,
  }) {
    var score = 0.0;
    if (rms >= 0.055 && rms <= 0.55) score += 0.32;
    if (zcr >= 0.035 && zcr <= 0.24) score += 0.26;
    if (variation >= 0.035 && variation <= 0.24) score += 0.26;
    if (slope >= 0.018 && slope <= 0.32) score += 0.16;
    if (rms > 0.65 || zcr > 0.42) score -= 0.18;
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
      (rms * 100).round().clamp(0, 99),
      (peak * 100).round().clamp(0, 99),
      (zcr * 100).round().clamp(0, 99),
      (slope * 100).round().clamp(0, 99),
      (variation * 100).round().clamp(0, 99),
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
}

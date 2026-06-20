import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import '../rust/api/proctoring.dart' as native_proctoring;
import '../rust/frb_generated.dart';
import 'microphone_stream_recording_service.dart';

class AudioSecurityCheckResult {
  const AudioSecurityCheckResult({
    required this.microphoneAvailable,
    required this.permissionGranted,
    required this.inputLevelOk,
    required this.averageRms,
    required this.peakRms,
    required this.noiseFloorRms,
    required this.zeroCrossingRate,
    required this.dynamicVariation,
    required this.voiceConfidence,
    required this.environmentLabel,
    required this.dominantNoiseClass,
    required this.soundProfile,
    required this.environmentDescription,
    required this.recommendedAction,
    required this.humanVoiceDetected,
    required this.phoneRingDetected,
    required this.notificationDetected,
    required this.tvOrRadioVoiceDetected,
    required this.ambientNoiseAllowed,
    required this.sampleDurationSeconds,
    this.clipPath,
    this.message,
  });

  final bool microphoneAvailable;
  final bool permissionGranted;
  final bool inputLevelOk;
  final double averageRms;
  final double peakRms;
  final double noiseFloorRms;
  final double zeroCrossingRate;
  final double dynamicVariation;
  final double voiceConfidence;
  final String environmentLabel;
  final String dominantNoiseClass;
  final String soundProfile;
  final String environmentDescription;
  final String recommendedAction;
  final bool humanVoiceDetected;
  final bool phoneRingDetected;
  final bool notificationDetected;
  final bool tvOrRadioVoiceDetected;
  final bool ambientNoiseAllowed;
  final int sampleDurationSeconds;
  final String? clipPath;
  final String? message;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'microphone_available': microphoneAvailable,
        'permission_granted': permissionGranted,
        'input_level_ok': inputLevelOk,
        'average_rms': averageRms,
        'peak_rms': peakRms,
        'noise_floor_rms': noiseFloorRms,
        'zero_crossing_rate': zeroCrossingRate,
        'dynamic_variation': dynamicVariation,
        'voice_confidence': voiceConfidence,
        'environment_label': environmentLabel,
        'dominant_noise_class': dominantNoiseClass,
        'sound_profile': soundProfile,
        'environment_description': environmentDescription,
        'recommended_action': recommendedAction,
        'human_voice_detected': humanVoiceDetected,
        'phone_ring_detected': phoneRingDetected,
        'notification_detected': notificationDetected,
        'tv_or_radio_voice_detected': tvOrRadioVoiceDetected,
        'ambient_noise_allowed': ambientNoiseAllowed,
        'sample_duration_seconds': sampleDurationSeconds,
        'environment_learning_completed': sampleDurationSeconds >= 15,
        if (clipPath != null) 'clip_path': clipPath,
        if (message != null) 'message': message,
      };
}

class AudioSecurityCheckService {
  AudioSecurityCheckService({MicrophoneStreamRecordingService? microphone})
      : _microphone = microphone ?? MicrophoneStreamRecordingService();

  static Future<bool>? _nativeReady;

  final MicrophoneStreamRecordingService _microphone;

  Future<AudioSecurityCheckResult> captureBaseline({
    Duration duration = const Duration(seconds: 15),
  }) async {
    final hasPermission = await _microphone.hasPermission();
    if (!hasPermission) {
      return const AudioSecurityCheckResult(
        microphoneAvailable: false,
        permissionGranted: false,
        inputLevelOk: false,
        averageRms: 0,
        peakRms: 0,
        noiseFloorRms: 0,
        zeroCrossingRate: 0,
        dynamicVariation: 0,
        voiceConfidence: 0,
        environmentLabel: 'microphone_unavailable',
        dominantNoiseClass: 'unclassified',
        soundProfile: 'microphone_unavailable',
        environmentDescription: 'Microphone permission is not available.',
        recommendedAction: 'Allow microphone access and run the sound review again.',
        humanVoiceDetected: false,
        phoneRingDetected: false,
        notificationDetected: false,
        tvOrRadioVoiceDetected: false,
        ambientNoiseAllowed: false,
        sampleDurationSeconds: 0,
        message: 'Microphone access is required for the security check.',
      );
    }

    final samples = <double>[];
    final peakSamples = <double>[];
    final zcrSamples = <double>[];
    final slopeSamples = <double>[];
    final chunkSpeechSignals = <bool>[];
    final nativeSpeechSignals = <bool>[];
    final nativeNoiseSignals = <double>[];
    var nativeSpeechStreak = 0;
    var nativeLossStreak = 0;
    var nativeLastSpeechStrikeAtMs = 0;
    final nativeReady = await _ensureNativeReady();
    String? clipPath;
    final startedAt = DateTime.now();
    try {
      await _microphone.start(
        sampleRate: 44100,
        maxBufferSeconds: math.max(15, duration.inSeconds),
        onPcmChunk: (chunk) {
          final features = _chunkFeatures(chunk);
          if (features.rms >= 0) samples.add(features.rms);
          if (features.peak >= 0) peakSamples.add(features.peak);
          if (features.zeroCrossingRate >= 0) {
            zcrSamples.add(features.zeroCrossingRate);
          }
          if (features.slopeEnergy >= 0) slopeSamples.add(features.slopeEnergy);
          if (features.rms >= 0 && features.peak >= 0) {
            chunkSpeechSignals.add(_speechLikeChunk(features));
          }
          if (nativeReady) {
            try {
              final nowMs = DateTime.now().millisecondsSinceEpoch;
              final decision = native_proctoring.analyzeAcousticChunk(
                pcm16Bytes: chunk,
                lossThresholdDbfs: -50,
                lossStreak: nativeLossStreak,
                lossSamplesToTrigger: 10,
                speechThresholdDbfs: -36,
                speechStreak: nativeSpeechStreak,
                speechSamplesToTrigger: 3,
                lastSpeechStrikeAtMs: nativeLastSpeechStrikeAtMs,
                speechCooldownMs: 3000,
                nowMs: nowMs,
              );
              nativeLossStreak = decision.updatedLossStreak;
              nativeSpeechStreak = decision.updatedSpeechStreak;
              nativeLastSpeechStrikeAtMs = decision.updatedLastSpeechStrikeAtMs;
              nativeSpeechSignals.add(decision.shouldTriggerSpeech);
              nativeNoiseSignals.add(decision.normalizedTetherSignal);
            } catch (_) {
              nativeSpeechSignals.add(false);
            }
          }
        },
      );
      await Future<void>.delayed(duration);
    } catch (e) {
      return AudioSecurityCheckResult(
        microphoneAvailable: true,
        permissionGranted: true,
        inputLevelOk: false,
        averageRms: 0,
        peakRms: 0,
        noiseFloorRms: 0,
        zeroCrossingRate: 0,
        dynamicVariation: 0,
        voiceConfidence: 0,
        environmentLabel: 'microphone_check_failed',
        dominantNoiseClass: 'unclassified',
        soundProfile: 'microphone_check_failed',
        environmentDescription: 'The app could not complete the room sound learning process.',
        recommendedAction: 'Check microphone access and run the sound review again.',
        humanVoiceDetected: false,
        phoneRingDetected: false,
        notificationDetected: false,
        tvOrRadioVoiceDetected: false,
        ambientNoiseAllowed: false,
        sampleDurationSeconds: DateTime.now().difference(startedAt).inSeconds,
        message: 'Microphone check could not be completed: $e',
      );
    } finally {
      clipPath = await _microphone.stopAndSaveWav(
        filePrefix: 'pre_exam_audio_baseline_15s',
      );
    }

    final average = _average(samples);
    final peak = samples.isEmpty ? 0.0 : samples.reduce(math.max);
    final rawPeak = peakSamples.isEmpty ? peak : peakSamples.reduce(math.max);
    final sortedRms = List<double>.from(samples)..sort();
    final noiseFloor = sortedRms.isEmpty
        ? 0.0
        : sortedRms[(sortedRms.length * 0.20)
            .floor()
            .clamp(0, sortedRms.length - 1)];
    final zcr = _average(zcrSamples);
    final slope = _average(slopeSamples);
    final inputLevelOk = rawPeak > 0.006 || peak > 0.006;
    final rmsVariation = _variation(samples);
    final nativeVoiceConfidence = _nativeVoiceConfidence(nativeSpeechSignals);
    final chunkVoiceConfidence = _chunkSpeechConfidence(chunkSpeechSignals);
    final nativeActivitySignal = nativeNoiseSignals.isEmpty
        ? 0.0
        : nativeNoiseSignals.reduce(math.max).clamp(0.0, 1.0);
    final acousticVoiceConfidence = _acousticVoiceConfidence(
      averageRms: average,
      peakRms: rawPeak,
      noiseFloorRms: noiseFloor,
      zcr: zcr,
      slope: slope,
      variation: rmsVariation,
      chunkSpeechConfidence: chunkVoiceConfidence,
      nativeSpeechConfidence: nativeVoiceConfidence,
      nativeActivitySignal: nativeActivitySignal,
    );
    final voiceConfidence = math.max(
      _voiceConfidence(samples),
      math.max(nativeVoiceConfidence, acousticVoiceConfidence),
    );
    final humanVoiceDetected = voiceConfidence >= 0.45;
    final phoneRingDetected = _phoneRingLikely(
      peakRms: rawPeak,
      zcr: zcr,
      variation: rmsVariation,
      slope: slope,
    );
    final notificationDetected = _notificationLikely(
      peakRms: rawPeak,
      zcr: zcr,
      variation: rmsVariation,
      slope: slope,
    );
    final tvOrRadioVoiceDetected = humanVoiceDetected &&
        rmsVariation < 0.065 &&
        (average > 0.02 || nativeActivitySignal > 0.55);
    final soundProfile = _soundProfile(
      averageRms: average,
      peakRms: rawPeak,
      noiseFloorRms: noiseFloor,
      zcr: zcr,
      slope: slope,
      variation: rmsVariation,
      humanVoiceDetected: humanVoiceDetected,
      phoneRingDetected: phoneRingDetected,
      notificationDetected: notificationDetected,
      inputLevelOk: inputLevelOk,
    );
    final dominantNoiseClass = _dominantNoiseClass(
      soundProfile: soundProfile,
      inputLevelOk: inputLevelOk,
    );
    final ambientAllowed = inputLevelOk &&
        !humanVoiceDetected &&
        !phoneRingDetected &&
        !notificationDetected &&
        !tvOrRadioVoiceDetected;
    final measuredSeconds = DateTime.now().difference(startedAt).inSeconds;
    final description = _environmentDescription(
      soundProfile: soundProfile,
      averageRms: average,
      peakRms: rawPeak,
      noiseFloorRms: noiseFloor,
      zcr: zcr,
      variation: rmsVariation,
    );
    final action = _recommendedAction(
      inputLevelOk: inputLevelOk,
      ambientAllowed: ambientAllowed,
      humanVoiceDetected: humanVoiceDetected,
      phoneRingDetected: phoneRingDetected,
      notificationDetected: notificationDetected,
      soundProfile: soundProfile,
    );

    return AudioSecurityCheckResult(
      microphoneAvailable: true,
      permissionGranted: true,
      inputLevelOk: inputLevelOk,
      averageRms: average,
      peakRms: rawPeak,
      noiseFloorRms: noiseFloor,
      zeroCrossingRate: zcr,
      dynamicVariation: rmsVariation,
      voiceConfidence: voiceConfidence,
      environmentLabel: _environmentLabel(
        averageRms: average,
        peakRms: rawPeak,
        voiceConfidence: voiceConfidence,
      ),
      dominantNoiseClass: dominantNoiseClass,
      soundProfile: soundProfile,
      environmentDescription: description,
      recommendedAction: action,
      humanVoiceDetected: humanVoiceDetected,
      phoneRingDetected: phoneRingDetected,
      notificationDetected: notificationDetected,
      tvOrRadioVoiceDetected: tvOrRadioVoiceDetected,
      ambientNoiseAllowed: ambientAllowed,
      sampleDurationSeconds: measuredSeconds,
      clipPath: clipPath,
      message: inputLevelOk
          ? 'Room sound learned for $measuredSeconds seconds: $description'
          : 'Microphone input level is too low for the security check.',
    );
  }

  Future<void> dispose() => _microphone.dispose();

  static Future<bool> _ensureNativeReady() {
    return _nativeReady ??= () async {
      try {
        await BrainCoreApi.init();
        return true;
      } catch (_) {
        return false;
      }
    }();
  }

  _AudioChunkFeatures _chunkFeatures(Uint8List bytes) {
    if (bytes.length < 2) return const _AudioChunkFeatures();
    final data = ByteData.sublistView(bytes);
    var total = 0.0;
    var peak = 0.0;
    var zeroCrossings = 0;
    var count = 0;
    var previous = 0.0;
    var previousSet = false;
    var slopeEnergy = 0.0;
    for (var i = 0; i + 1 < bytes.length; i += 2) {
      final sample = data.getInt16(i, Endian.little) / 32768.0;
      final absSample = sample.abs();
      peak = math.max(peak, absSample);
      total += sample * sample;
      if (previousSet) {
        if ((sample >= 0 && previous < 0) ||
            (sample < 0 && previous >= 0)) {
          zeroCrossings++;
        }
        final diff = sample - previous;
        slopeEnergy += diff * diff;
      }
      previous = sample;
      previousSet = true;
      count++;
    }
    if (count == 0) return const _AudioChunkFeatures();
    return _AudioChunkFeatures(
      rms: math.sqrt(total / count).clamp(0.0, 1.0),
      peak: peak.clamp(0.0, 1.0),
      zeroCrossingRate: (zeroCrossings / count).clamp(0.0, 1.0),
      slopeEnergy:
          math.sqrt(slopeEnergy / math.max(1, count - 1)).clamp(0.0, 1.0),
    );
  }

  double _average(List<double> values) {
    if (values.isEmpty) return 0;
    return values.fold<double>(0, (sum, value) => sum + value) / values.length;
  }

  double _voiceConfidence(List<double> samples) {
    if (samples.length < 4) return 0;
    final active = samples.where((value) => value >= 0.018).length;
    final speechLevel = samples.where((value) => value >= 0.008).length;
    final varied = _variation(samples) >= 0.0007;
    final ratio = (active + (speechLevel * 0.45)) / samples.length;
    return (ratio * (varied ? 1.35 : 0.75)).clamp(0.0, 1.0);
  }

  double _nativeVoiceConfidence(List<bool> speechSignals) {
    if (speechSignals.isEmpty) return 0;
    final speechCount = speechSignals.where((value) => value).length;
    return (speechCount / speechSignals.length).clamp(0.0, 1.0);
  }

  double _chunkSpeechConfidence(List<bool> speechSignals) {
    if (speechSignals.isEmpty) return 0;
    final speechCount = speechSignals.where((value) => value).length;
    return (speechCount / speechSignals.length).clamp(0.0, 1.0);
  }

  bool _speechLikeChunk(_AudioChunkFeatures features) {
    final speechZcr = features.zeroCrossingRate >= 0.018 &&
        features.zeroCrossingRate <= 0.26;
    final speechTexture = features.slopeEnergy >= 0.0025;
    final speechBurst = features.peak >= 0.018 && features.rms >= 0.0012;
    final strongBurst = features.peak >= 0.035 && features.slopeEnergy >= 0.0014;
    return speechZcr && speechTexture && (speechBurst || strongBurst);
  }

  double _acousticVoiceConfidence({
    required double averageRms,
    required double peakRms,
    required double noiseFloorRms,
    required double zcr,
    required double slope,
    required double variation,
    required double chunkSpeechConfidence,
    required double nativeSpeechConfidence,
    required double nativeActivitySignal,
  }) {
    var score = 0.0;
    final peakToAverage = peakRms / math.max(averageRms, 0.0008);
    final peakToFloor = peakRms / math.max(noiseFloorRms, 0.0008);
    final speechZcr = zcr >= 0.018 && zcr <= 0.26;
    final speechTexture = slope >= 0.0025;

    if (peakRms >= 0.018) score += 0.16;
    if (peakRms >= 0.032) score += 0.10;
    if (averageRms >= 0.0012) score += 0.08;
    if (peakToAverage >= 5.0) score += 0.14;
    if (peakToFloor >= 6.0) score += 0.14;
    if (speechZcr) score += 0.14;
    if (speechTexture) score += 0.14;
    if (variation >= 0.0007) score += 0.08;
    if (chunkSpeechConfidence >= 0.18) score += 0.18;
    if (nativeSpeechConfidence >= 0.18) score += 0.18;
    if (nativeActivitySignal >= 0.50 && speechZcr) score += 0.10;

    return score.clamp(0.0, 1.0);
  }

  double _variation(List<double> samples) {
    if (samples.length < 2) return 0;
    var total = 0.0;
    for (var i = 1; i < samples.length; i++) {
      total += (samples[i] - samples[i - 1]).abs();
    }
    return total / (samples.length - 1);
  }

  bool _phoneRingLikely({
    required double peakRms,
    required double zcr,
    required double variation,
    required double slope,
  }) {
    return peakRms >= 0.20 && zcr >= 0.18 && variation >= 0.010 && slope >= 0.020;
  }

  bool _notificationLikely({
    required double peakRms,
    required double zcr,
    required double variation,
    required double slope,
  }) {
    return peakRms >= 0.14 && zcr >= 0.22 && variation >= 0.008 && slope >= 0.026;
  }

  String _soundProfile({
    required double averageRms,
    required double peakRms,
    required double noiseFloorRms,
    required double zcr,
    required double slope,
    required double variation,
    required bool humanVoiceDetected,
    required bool phoneRingDetected,
    required bool notificationDetected,
    required bool inputLevelOk,
  }) {
    if (!inputLevelOk) return 'microphone_input_too_low';
    if (humanVoiceDetected) return 'human_voice_or_conversation';
    if (phoneRingDetected) return 'phone_ring_like_sound';
    if (notificationDetected) return 'notification_or_sharp_beep';
    if (averageRms < 0.025 && peakRms < 0.11) return 'quiet_room';
    if (variation < 0.025 && zcr < 0.20 && noiseFloorRms > 0.018) {
      return 'steady_fan_ac_generator_hum';
    }
    if (variation >= 0.025 && variation < 0.11 && peakRms < 0.60 && zcr < 0.28) {
      return 'traffic_or_open_environment_noise';
    }
    if (peakRms >= 0.65 && variation >= 0.060) {
      return 'sudden_loud_environment_noise';
    }
    if (averageRms >= 0.35) return 'loud_allowed_ambient_noise';
    return 'mixed_ambient_noise';
  }

  String _environmentDescription({
    required String soundProfile,
    required double averageRms,
    required double peakRms,
    required double noiseFloorRms,
    required double zcr,
    required double variation,
  }) {
    final levels =
        'avg ${(averageRms * 100).toStringAsFixed(1)}%, peak ${(peakRms * 100).toStringAsFixed(1)}%, floor ${(noiseFloorRms * 100).toStringAsFixed(1)}%';
    switch (soundProfile) {
      case 'microphone_input_too_low':
        return 'Microphone input is too low or muted. $levels.';
      case 'human_voice_or_conversation':
        return 'Voice or conversation pattern noticed. $levels.';
      case 'phone_ring_like_sound':
        return 'Phone ring or ringtone-like sound noticed. $levels.';
      case 'notification_or_sharp_beep':
        return 'Notification, beep, keyboard click, or sharp intermittent sound noticed. $levels.';
      case 'quiet_room':
        return 'Quiet room learned with low background sound. $levels.';
      case 'steady_fan_ac_generator_hum':
        return 'Steady ambient hum learned, likely fan, AC, or generator. $levels.';
      case 'traffic_or_open_environment_noise':
        return 'Variable ambient noise learned, likely traffic, open window, or outdoor activity. $levels.';
      case 'sudden_loud_environment_noise':
        return 'Sudden loud environmental sound noticed. $levels.';
      case 'loud_allowed_ambient_noise':
        return 'Loud but non-voice ambient noise learned. $levels.';
      default:
        return 'Mixed ambient room noise learned. $levels.';
    }
  }

  String _recommendedAction({
    required bool inputLevelOk,
    required bool ambientAllowed,
    required bool humanVoiceDetected,
    required bool phoneRingDetected,
    required bool notificationDetected,
    required String soundProfile,
  }) {
    if (!inputLevelOk) {
      return 'Unmute microphone or move closer to the device and run the sound review again.';
    }
    if (humanVoiceDetected) {
      return 'Voice was noticed. Keep the room quiet and run the sound review again.';
    }
    if (phoneRingDetected || notificationDetected) {
      return 'Silence phones, notifications, TV, and radio, then run the sound review again.';
    }
    if (ambientAllowed) {
      return 'Ambient room sound is acceptable. Keep the room stable until submission.';
    }
    return 'Repeat the sound review if this sound is not normal for the room.';
  }

  String _environmentLabel({
    required double averageRms,
    required double peakRms,
    required double voiceConfidence,
  }) {
    if (voiceConfidence >= 0.45) return 'human_voice';
    if (peakRms > 0.75) return 'very_noisy_environment';
    if (averageRms > 0.45) return 'noisy_environment';
    if (averageRms > 0.20) return 'moderate_environment';
    return 'quiet_environment';
  }

  String _dominantNoiseClass({
    required String soundProfile,
    required bool inputLevelOk,
  }) {
    if (!inputLevelOk) return 'unclassified';
    switch (soundProfile) {
      case 'human_voice_or_conversation':
        return 'human_voice';
      case 'phone_ring_like_sound':
        return 'phone_ring';
      case 'notification_or_sharp_beep':
        return 'notification';
      case 'steady_fan_ac_generator_hum':
        return 'fan_ac_generator';
      case 'traffic_or_open_environment_noise':
        return 'traffic_or_open_environment';
      case 'quiet_room':
        return 'quiet_room';
      default:
        return 'allowed_ambient_noise';
    }
  }
}

class _AudioChunkFeatures {
  const _AudioChunkFeatures({
    this.rms = -1,
    this.peak = -1,
    this.zeroCrossingRate = -1,
    this.slopeEnergy = -1,
  });

  final double rms;
  final double peak;
  final double zeroCrossingRate;
  final double slopeEnergy;
}

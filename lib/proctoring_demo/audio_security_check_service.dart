import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import '../rust/api/proctoring.dart' as native_proctoring;
import '../rust/brain_core_runtime.dart';
import 'audio_fingerprint_isolation_service.dart';
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

  static const double _minimumLiveInputPeakRms = 0.002;

  static const bool _allowAudioReviewOverride = bool.fromEnvironment(
    'KSLAS_ALLOW_AUDIO_REVIEW_OVERRIDE',
    defaultValue: false,
  );
  static Future<bool>? _nativeReady;

  final MicrophoneStreamRecordingService _microphone;

  Future<AudioSecurityCheckResult> captureBaseline({
    Duration duration = const Duration(seconds: 15),
  }) async {
    if (_allowAudioReviewOverride) {
      final clipPath = await _writeTestingOverrideWav(
        duration: duration.inSeconds <= 0
            ? const Duration(seconds: 15)
            : duration,
      );
      return AudioSecurityCheckResult(
        microphoneAvailable: true,
        permissionGranted: true,
        inputLevelOk: true,
        averageRms: 0.02,
        peakRms: 0.04,
        noiseFloorRms: 0.01,
        zeroCrossingRate: 0.04,
        dynamicVariation: 0.01,
        voiceConfidence: 0,
        environmentLabel: 'testing_audio_override',
        dominantNoiseClass: 'quiet_room',
        soundProfile: 'testing_audio_override',
        environmentDescription: 'Room sound check passed.',
        recommendedAction: 'Keep the room quiet until the assessment starts.',
        humanVoiceDetected: false,
        phoneRingDetected: false,
        notificationDetected: false,
        tvOrRadioVoiceDetected: false,
        ambientNoiseAllowed: true,
        sampleDurationSeconds: duration.inSeconds <= 0
            ? 15
            : duration.inSeconds,
        clipPath: clipPath,
        message: 'Room sound check passed. Continue to the next step.',
      );
    }

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
        recommendedAction:
            'Allow microphone access and run the sound review again.',
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
    // Voice is decided per chunk by the same sound classifier the live
    // exam monitor uses (which treats fans and hum as allowed ambient), not
    // by loudness. Loudness-only scoring blocked ordinary quiet rooms.
    final classifier = AudioFingerprintIsolationService();
    var classifiedMs = 0.0;
    var voiceMs = 0.0;
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
          final classified = classifier.analysePcm16(chunk);
          if (classified != null && classified.nativeClassifier) {
            final chunkMs = (chunk.length / 2) * 1000 / 44100;
            classifiedMs += chunkMs;
            if (classified.nearVoiceLikely) voiceMs += chunkMs;
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
        environmentDescription:
            'The app could not complete the room sound learning process.',
        recommendedAction:
            'Check microphone access and run the sound review again.',
        humanVoiceDetected: false,
        phoneRingDetected: false,
        notificationDetected: false,
        tvOrRadioVoiceDetected: false,
        ambientNoiseAllowed: false,
        sampleDurationSeconds: DateTime.now().difference(startedAt).inSeconds,
        message: 'Microphone check could not be completed: $e',
      );
    } finally {
      // The room sample is analysed in memory; raw audio is not written to
      // the temp folder.
      await _microphone.stop();
    }

    final average = _average(samples);
    final peak = samples.isEmpty ? 0.0 : samples.reduce(math.max);
    final rawPeak = peakSamples.isEmpty ? peak : peakSamples.reduce(math.max);
    final sortedRms = List<double>.from(samples)..sort();
    final noiseFloor = sortedRms.isEmpty
        ? 0.0
        : sortedRms[(sortedRms.length * 0.20).floor().clamp(
            0,
            sortedRms.length - 1,
          )];
    final zcr = _average(zcrSamples);
    final slope = _average(slopeSamples);
    final inputLevelOk =
        rawPeak >= _minimumLiveInputPeakRms || peak >= _minimumLiveInputPeakRms;
    final rmsVariation = _variation(samples);
    final nativeActivitySignal = nativeNoiseSignals.isEmpty
        ? 0.0
        : nativeNoiseSignals.reduce(math.max).clamp(0.0, 1.0);
    // Share of the classified sample that was voice. At least 10% (1.5 s of
    // a 15 s check) counts as someone speaking. Without the classifier (Dart
    // fallback) the check cannot tell, so it does not block on voice.
    final voiceConfidence = classifiedMs <= 0
        ? 0.0
        : (voiceMs / classifiedMs).clamp(0.0, 1.0);
    final humanVoiceDetected = classifiedMs > 0 && voiceConfidence >= 0.10;
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
    final tvOrRadioVoiceDetected =
        humanVoiceDetected &&
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
    final ambientAllowed =
        inputLevelOk &&
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
          : 'No microphone activity was detected. Check that the microphone is not muted.',
    );
  }

  Future<void> dispose() => _microphone.dispose();

  static Future<bool> _ensureNativeReady() {
    return _nativeReady ??= () async {
      try {
        await BrainCoreRuntime.ensureInitialized();
        return true;
      } catch (_) {
        return false;
      }
    }();
  }

  Future<String> _writeTestingOverrideWav({required Duration duration}) async {
    const sampleRate = 44100;
    const numChannels = 1;
    const bitsPerSample = 16;
    final seconds = duration.inSeconds.clamp(1, 15);
    final sampleCount = sampleRate * seconds;
    final pcmBytes = Uint8List(sampleCount * 2);
    final data = ByteData.sublistView(pcmBytes);

    // Quiet deterministic room tone. This is only used when the explicit
    // development override flag is enabled.
    var seed = 17;
    for (var i = 0; i < sampleCount; i++) {
      seed = (seed * 1103515245 + 12345) & 0x7fffffff;
      final noise = ((seed % 240) - 120);
      final hum = ((i % 160) - 80) ~/ 10;
      final sample = (noise + hum).clamp(-220, 220);
      data.setInt16(i * 2, sample, Endian.little);
    }

    final directory = Directory(
      '${Directory.systemTemp.path}${Platform.pathSeparator}kslas_audio_evidence',
    );
    await directory.create(recursive: true);
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final file = File(
      '${directory.path}${Platform.pathSeparator}testing_audio_override_$timestamp.wav',
    );
    await file.writeAsBytes(
      _wavBytes(
        pcmBytes: pcmBytes,
        sampleRate: sampleRate,
        numChannels: numChannels,
        bitsPerSample: bitsPerSample,
      ),
      flush: true,
    );
    return file.path;
  }

  Uint8List _wavBytes({
    required Uint8List pcmBytes,
    required int sampleRate,
    required int numChannels,
    required int bitsPerSample,
  }) {
    final byteRate = sampleRate * numChannels * bitsPerSample ~/ 8;
    final blockAlign = numChannels * bitsPerSample ~/ 8;
    final dataLength = pcmBytes.length;
    final fileLength = 36 + dataLength;
    final bytes = BytesBuilder(copy: false)
      ..add(_ascii('RIFF'))
      ..add(_uint32(fileLength))
      ..add(_ascii('WAVE'))
      ..add(_ascii('fmt '))
      ..add(_uint32(16))
      ..add(_uint16(1))
      ..add(_uint16(numChannels))
      ..add(_uint32(sampleRate))
      ..add(_uint32(byteRate))
      ..add(_uint16(blockAlign))
      ..add(_uint16(bitsPerSample))
      ..add(_ascii('data'))
      ..add(_uint32(dataLength))
      ..add(pcmBytes);
    return bytes.toBytes();
  }

  Uint8List _ascii(String value) => Uint8List.fromList(value.codeUnits);

  Uint8List _uint16(int value) {
    final data = ByteData(2)..setUint16(0, value, Endian.little);
    return data.buffer.asUint8List();
  }

  Uint8List _uint32(int value) {
    final data = ByteData(4)..setUint32(0, value, Endian.little);
    return data.buffer.asUint8List();
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
    if (count == 0) return const _AudioChunkFeatures();
    return _AudioChunkFeatures(
      rms: math.sqrt(total / count).clamp(0.0, 1.0),
      peak: peak.clamp(0.0, 1.0),
      zeroCrossingRate: (zeroCrossings / count).clamp(0.0, 1.0),
      slopeEnergy: math
          .sqrt(slopeEnergy / math.max(1, count - 1))
          .clamp(0.0, 1.0),
    );
  }

  double _average(List<double> values) {
    if (values.isEmpty) return 0;
    return values.fold<double>(0, (sum, value) => sum + value) / values.length;
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
    return peakRms >= 0.20 &&
        zcr >= 0.18 &&
        variation >= 0.010 &&
        slope >= 0.020;
  }

  bool _notificationLikely({
    required double peakRms,
    required double zcr,
    required double variation,
    required double slope,
  }) {
    return peakRms >= 0.14 &&
        zcr >= 0.22 &&
        variation >= 0.008 &&
        slope >= 0.026;
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
    if (variation >= 0.025 &&
        variation < 0.11 &&
        peakRms < 0.60 &&
        zcr < 0.28) {
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

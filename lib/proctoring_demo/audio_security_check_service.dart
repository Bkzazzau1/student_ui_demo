import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:record/record.dart';

import '../rust/api/proctoring.dart' as native_proctoring;
import '../rust/frb_generated.dart';

class AudioSecurityCheckResult {
  const AudioSecurityCheckResult({
    required this.microphoneAvailable,
    required this.permissionGranted,
    required this.inputLevelOk,
    required this.averageRms,
    required this.peakRms,
    required this.voiceConfidence,
    required this.environmentLabel,
    this.message,
  });

  final bool microphoneAvailable;
  final bool permissionGranted;
  final bool inputLevelOk;
  final double averageRms;
  final double peakRms;
  final double voiceConfidence;
  final String environmentLabel;
  final String? message;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'microphone_available': microphoneAvailable,
    'permission_granted': permissionGranted,
    'input_level_ok': inputLevelOk,
    'average_rms': averageRms,
    'peak_rms': peakRms,
    'voice_confidence': voiceConfidence,
    'environment_label': environmentLabel,
    if (message != null) 'message': message,
  };
}

class AudioSecurityCheckService {
  AudioSecurityCheckService({AudioRecorder? recorder})
    : _recorder = recorder ?? AudioRecorder();

  static Future<bool>? _nativeReady;

  final AudioRecorder _recorder;

  Future<AudioSecurityCheckResult> captureBaseline({
    Duration duration = const Duration(seconds: 4),
  }) async {
    final hasPermission = await _recorder.hasPermission();
    if (!hasPermission) {
      return const AudioSecurityCheckResult(
        microphoneAvailable: false,
        permissionGranted: false,
        inputLevelOk: false,
        averageRms: 0,
        peakRms: 0,
        voiceConfidence: 0,
        environmentLabel: 'microphone_unavailable',
        message: 'Microphone access is required for the security check.',
      );
    }

    final samples = <double>[];
    final nativeSpeechSignals = <bool>[];
    final nativeNoiseSignals = <double>[];
    var nativeSpeechStreak = 0;
    var nativeLossStreak = 0;
    var nativeLastSpeechStrikeAtMs = 0;
    final nativeReady = await _ensureNativeReady();
    StreamSubscription<Uint8List>? subscription;
    try {
      final stream = await _recorder.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: 16000,
          numChannels: 1,
          autoGain: false,
          echoCancel: false,
          noiseSuppress: false,
        ),
      );
      subscription = stream.listen((chunk) {
        final rms = _rms(chunk);
        if (rms >= 0) samples.add(rms);
        if (nativeReady) {
          try {
            final nowMs = DateTime.now().millisecondsSinceEpoch;
            final decision = native_proctoring.analyzeAcousticChunk(
              pcm16Bytes: chunk,
              lossThresholdDbfs: -50,
              lossStreak: nativeLossStreak,
              lossSamplesToTrigger: 10,
              speechThresholdDbfs: -28,
              speechStreak: nativeSpeechStreak,
              speechSamplesToTrigger: 4,
              lastSpeechStrikeAtMs: nativeLastSpeechStrikeAtMs,
              speechCooldownMs: 3000,
              nowMs: nowMs,
            );
            nativeLossStreak = decision.updatedLossStreak;
            nativeSpeechStreak = decision.updatedSpeechStreak;
            nativeLastSpeechStrikeAtMs =
                decision.updatedLastSpeechStrikeAtMs;
            nativeSpeechSignals.add(decision.shouldTriggerSpeech);
            nativeNoiseSignals.add(decision.normalizedTetherSignal);
          } catch (_) {
            nativeSpeechSignals.add(false);
          }
        }
      });
      await Future<void>.delayed(duration);
    } catch (e) {
      return AudioSecurityCheckResult(
        microphoneAvailable: true,
        permissionGranted: true,
        inputLevelOk: false,
        averageRms: 0,
        peakRms: 0,
        voiceConfidence: 0,
        environmentLabel: 'microphone_check_failed',
        message: 'Microphone check could not be completed: $e',
      );
    } finally {
      await subscription?.cancel();
      try {
        if (await _recorder.isRecording()) {
          await _recorder.stop();
        }
      } catch (_) {}
    }

    final average = samples.isEmpty
        ? 0.0
        : samples.fold<double>(0, (sum, value) => sum + value) / samples.length;
    final peak = samples.isEmpty ? 0.0 : samples.reduce(math.max);
    final inputLevelOk = peak > 0.01;
    final voiceConfidence = nativeSpeechSignals.isEmpty
        ? _voiceConfidence(samples)
        : _nativeVoiceConfidence(nativeSpeechSignals);
    final nativeNoisePeak = nativeNoiseSignals.isEmpty
        ? 0.0
        : nativeNoiseSignals.reduce(math.max);
    return AudioSecurityCheckResult(
      microphoneAvailable: true,
      permissionGranted: true,
      inputLevelOk: inputLevelOk,
      averageRms: average,
      peakRms: peak,
      voiceConfidence: voiceConfidence,
      environmentLabel: _environmentLabel(
        averageRms: average,
        peakRms: math.max(peak, nativeNoisePeak),
        voiceConfidence: voiceConfidence,
      ),
      message: inputLevelOk
          ? null
          : 'Microphone input level is too low for the security check.',
    );
  }

  Future<void> dispose() => _recorder.dispose();

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

  double _rms(Uint8List bytes) {
    if (bytes.length < 2) return -1;
    final data = ByteData.sublistView(bytes);
    var total = 0.0;
    var count = 0;
    for (var i = 0; i + 1 < bytes.length; i += 2) {
      final sample = data.getInt16(i, Endian.little) / 32768.0;
      total += sample * sample;
      count++;
    }
    if (count == 0) return -1;
    return math.sqrt(total / count).clamp(0.0, 1.0);
  }

  double _voiceConfidence(List<double> samples) {
    if (samples.length < 4) return 0;
    final active = samples.where((value) => value >= 0.12).length;
    final varied = _variation(samples) >= 0.08;
    final ratio = active / samples.length;
    return (ratio * (varied ? 1.2 : 0.6)).clamp(0.0, 1.0);
  }

  double _nativeVoiceConfidence(List<bool> speechSignals) {
    if (speechSignals.isEmpty) return 0;
    final speechCount = speechSignals.where((value) => value).length;
    return (speechCount / speechSignals.length).clamp(0.0, 1.0);
  }

  double _variation(List<double> samples) {
    if (samples.length < 2) return 0;
    var total = 0.0;
    for (var i = 1; i < samples.length; i++) {
      total += (samples[i] - samples[i - 1]).abs();
    }
    return total / (samples.length - 1);
  }

  String _environmentLabel({
    required double averageRms,
    required double peakRms,
    required double voiceConfidence,
  }) {
    if (voiceConfidence >= 0.70) return 'human_voice';
    if (peakRms > 0.75) return 'very_noisy_environment';
    if (averageRms > 0.45) return 'noisy_environment';
    if (averageRms > 0.20) return 'moderate_environment';
    return 'quiet_environment';
  }
}

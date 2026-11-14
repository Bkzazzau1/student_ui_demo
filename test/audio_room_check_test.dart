// The pre-exam room check on ordinary quiet rooms, through the real Rust
// classifier. Before the fix, loudness-only scoring called a real -47 dBFS
// laptop room and a fan "human voice" and blocked the exam from starting.

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:record/record.dart';
import 'package:students_ui_demo/proctoring_demo/audio_security_check_service.dart';
import 'package:students_ui_demo/proctoring_demo/microphone_stream_recording_service.dart';
import 'package:students_ui_demo/rust/brain_core_runtime.dart';

const int _rate = 44100;

class _UnusedRecorder implements AudioRecorder {
  @override
  dynamic noSuchMethod(Invocation invocation) => Future<void>.value();
}

/// A microphone that delivers prepared PCM in 50 ms chunks.
class _ScriptedMicrophone extends MicrophoneStreamRecordingService {
  _ScriptedMicrophone(this.pcm) : super(recorder: _UnusedRecorder());

  final Uint8List pcm;
  bool stopped = false;

  @override
  Future<bool> hasPermission() async => true;

  @override
  Future<void> start({
    required void Function(Uint8List chunk) onPcmChunk,
    int sampleRate = 44100,
    int maxBufferSeconds = 15,
  }) async {
    const chunkBytes = _rate ~/ 20 * 2;
    for (var o = 0; o + chunkBytes <= pcm.length; o += chunkBytes) {
      onPcmChunk(Uint8List.sublistView(pcm, o, o + chunkBytes));
    }
  }

  @override
  Future<void> stop() async => stopped = true;

  @override
  Future<String?> stopAndSaveWav({
    String filePrefix = 'microphone_clip',
  }) async => fail('the room check must not write audio to disk');
}

Uint8List _noise(double seconds, double dbfs, {bool lowFrequency = false}) {
  final random = math.Random(3);
  final n = (seconds * _rate).round();
  final target = math.pow(10, dbfs / 20).toDouble();
  final bytes = ByteData(n * 2);
  var smooth = 0.0;
  final values = List<double>.filled(n, 0);
  var sumSquares = 0.0;
  for (var i = 0; i < n; i++) {
    final white = random.nextDouble() * 2 - 1;
    // A fan: mostly low-frequency rumble plus a 50 Hz hum.
    smooth = lowFrequency ? 0.97 * smooth + 0.03 * white : white;
    final hum = lowFrequency ? 0.4 * math.sin(2 * math.pi * 50 * i / _rate) : 0;
    values[i] = smooth + hum;
    sumSquares += values[i] * values[i];
  }
  final scale = target / math.max(math.sqrt(sumSquares / n), 1e-12);
  for (var i = 0; i < n; i++) {
    bytes.setInt16(
      i * 2,
      (values[i] * scale * 32767).round().clamp(-32768, 32767),
      Endian.little,
    );
  }
  return bytes.buffer.asUint8List();
}

Future<AudioSecurityCheckResult> _check(Uint8List pcm) {
  final microphone = _ScriptedMicrophone(pcm);
  return AudioSecurityCheckService(
    microphone: microphone,
  ).captureBaseline(duration: const Duration(milliseconds: 10));
}

void main() {
  setUpAll(BrainCoreRuntime.ensureInitialized);

  test('a quiet room is not "voice" and its sound is allowed', () async {
    final result = await _check(_noise(15, -47));
    expect(result.humanVoiceDetected, isFalse);
    expect(result.tvOrRadioVoiceDetected, isFalse);
    expect(result.ambientNoiseAllowed, isTrue);
    expect(result.clipPath, isNull);
  });

  test('a fan is allowed ambient sound', () async {
    for (final level in const [-40.0, -35.0]) {
      final result = await _check(_noise(15, level, lowFrequency: true));
      expect(result.humanVoiceDetected, isFalse, reason: '$level dBFS');
      expect(result.tvOrRadioVoiceDetected, isFalse, reason: '$level dBFS');
    }
  });
}

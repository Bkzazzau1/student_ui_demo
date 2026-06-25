import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:record/record.dart';

class MicrophoneStreamRecordingService {
  MicrophoneStreamRecordingService({AudioRecorder? recorder})
    : _recorder = recorder ?? AudioRecorder();

  final AudioRecorder _recorder;
  final List<Uint8List> _chunks = <Uint8List>[];

  StreamSubscription<Uint8List>? _subscription;
  int _sampleRate = 44100;
  int _maxBufferBytes = 44100 * 2 * 15;
  bool _running = false;

  bool get isRunning => _running;
  int get sampleRate => _sampleRate;
  int get bufferedBytes => _chunks.fold<int>(0, (sum, item) => sum + item.length);
  double get bufferedSeconds => bufferedBytes / math.max(1, _sampleRate * 2);

  Future<bool> hasPermission() => _recorder.hasPermission();

  Future<void> start({
    required void Function(Uint8List chunk) onPcmChunk,
    int sampleRate = 44100,
    int maxBufferSeconds = 15,
  }) async {
    if (_running) return;

    _chunks.clear();
    _sampleRate = sampleRate;
    _maxBufferBytes = sampleRate * 2 * maxBufferSeconds;

    final stream = await _recorder.startStream(
      RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: sampleRate,
        numChannels: 1,
        autoGain: false,
        echoCancel: false,
        noiseSuppress: false,
      ),
    );

    _subscription = stream.listen(
      (chunk) {
        if (chunk.isEmpty) return;
        _appendChunk(chunk);
        onPcmChunk(chunk);
      },
      onError: (_) {
        // Best effort stream; the caller reports the final readiness result.
      },
      cancelOnError: false,
    );
    _running = true;
  }

  Uint8List? snapshotPcmBytes({int? maxSeconds}) {
    if (_chunks.isEmpty) return null;
    final joined = _joinChunks();
    if (maxSeconds == null || maxSeconds <= 0) return joined;

    final maxBytes = _sampleRate * 2 * maxSeconds;
    if (joined.length <= maxBytes) return joined;
    return Uint8List.fromList(joined.sublist(joined.length - maxBytes));
  }

  Uint8List? snapshotWavBytes({int? maxSeconds}) {
    final pcmBytes = snapshotPcmBytes(maxSeconds: maxSeconds);
    if (pcmBytes == null || pcmBytes.isEmpty) return null;
    return _wavBytes(
      pcmBytes: pcmBytes,
      sampleRate: _sampleRate,
      numChannels: 1,
      bitsPerSample: 16,
    );
  }

  Future<String?> saveBufferedWavFile({
    String filePrefix = 'microphone_snapshot',
    int? maxSeconds,
  }) async {
    final wavBytes = snapshotWavBytes(maxSeconds: maxSeconds);
    if (wavBytes == null || wavBytes.isEmpty) return null;

    final directory = Directory(
      '${Directory.systemTemp.path}${Platform.pathSeparator}kslas_audio_evidence',
    );
    await directory.create(recursive: true);

    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final file = File(
      '${directory.path}${Platform.pathSeparator}${filePrefix}_$timestamp.wav',
    );
    await file.writeAsBytes(wavBytes, flush: true);
    return file.path;
  }

  Future<String?> stopAndSaveWav({
    String filePrefix = 'microphone_clip',
  }) async {
    await _subscription?.cancel();
    _subscription = null;
    _running = false;

    try {
      if (await _recorder.isRecording()) {
        await _recorder.stop();
      }
    } catch (_) {
      // Best effort shutdown.
    }

    return saveBufferedWavFile(filePrefix: filePrefix);
  }

  Future<void> dispose() async {
    await stopAndSaveWav(filePrefix: 'discarded_microphone_clip');
    await _recorder.dispose();
  }

  void _appendChunk(Uint8List chunk) {
    _chunks.add(Uint8List.fromList(chunk));
    var totalBytes = _chunks.fold<int>(0, (sum, item) => sum + item.length);
    while (totalBytes > _maxBufferBytes && _chunks.isNotEmpty) {
      totalBytes -= _chunks.removeAt(0).length;
    }
  }

  Uint8List _joinChunks() {
    final totalBytes = _chunks.fold<int>(0, (sum, item) => sum + item.length);
    final out = Uint8List(totalBytes);
    var offset = 0;
    for (final chunk in _chunks) {
      out.setRange(offset, offset + chunk.length, chunk);
      offset += chunk.length;
    }
    return out;
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
}

import 'microphone_stream_recording_service.dart';
import 'local_evidence_vault_service.dart';

class AudioEvidenceCaptureService {
  const AudioEvidenceCaptureService({
    this.vault = const LocalEvidenceVaultService(),
    this.clipSeconds = 15,
  });

  final LocalEvidenceVaultService vault;
  final int clipSeconds;

  Future<Map<String, Object?>?> saveRecentAudioEvidence({
    required MicrophoneStreamRecordingService microphone,
    required String studentId,
    required String examId,
    required String attemptId,
    required String eventType,
    required String reviewReason,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) async {
    try {
      final wavBytes = microphone.snapshotWavBytes(maxSeconds: clipSeconds);
      if (wavBytes == null || wavBytes.isEmpty) return null;

      final record = await vault.saveBytesEvidence(
        studentId: studentId,
        examId: examId,
        attemptId: attemptId,
        eventType: eventType,
        fileType: 'wav',
        reviewReason: reviewReason,
        bytes: wavBytes,
        metadata: <String, Object?>{
          ...metadata,
          'source': 'audio_evidence_capture_service',
          'clip_seconds': clipSeconds,
          'sample_rate': microphone.sampleRate,
          'buffered_seconds': microphone.bufferedSeconds,
          'format': 'pcm16_mono_wav',
        },
      );
      return record.toJson();
    } catch (_) {
      return null;
    }
  }
}

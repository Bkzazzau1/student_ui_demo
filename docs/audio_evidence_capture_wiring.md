# Audio Evidence Capture Wiring

Working branch: `codex/onnx-directml-smoke-inference`.

## Completed

`MicrophoneStreamRecordingService` now supports non-destructive snapshots from the live PCM buffer:

- `snapshotPcmBytes`
- `snapshotWavBytes`
- `saveBufferedWavFile`
- `sampleRate`
- `bufferedBytes`
- `bufferedSeconds`

This means the microphone stream can keep running while the app saves the latest buffered audio for review.

`AudioEvidenceCaptureService` now saves recent microphone audio through:

`LocalEvidenceVaultService.saveBytesEvidence(...)`

Because `LocalEvidenceVaultService` already tries Rust native first, audio evidence also follows the native-first evidence flow.

## Target Events

Attach audio evidence to these events in `LiveExamMonitor._raiseEvent` or directly around audio event creation:

- `audio_voice_isolation_alert`
- `background_voice_environment_warning`
- `audio_repeated_fingerprint_detected`
- `microphone_reconnect_timeout`

## Recommended Wiring Pattern

Add a field in `LiveExamMonitor`:

```dart
final AudioEvidenceCaptureService _audioEvidence =
    const AudioEvidenceCaptureService();
```

Before sending serious audio events, save a recent audio record:

```dart
final audioRecord = await _audioEvidence.saveRecentAudioEvidence(
  microphone: _microphone,
  studentId: widget.studentId,
  examId: widget.examId,
  attemptId: widget.attemptId,
  eventType: eventType,
  reviewReason: message,
  metadata: enrichedMetadata,
);
if (audioRecord != null) {
  enrichedMetadata['local_audio_record'] = audioRecord;
}
```

## Important

This captures the recent buffered room audio only. It does not stop the microphone stream.

## Validation

```bash
flutter analyze --no-pub lib/proctoring_demo/microphone_stream_recording_service.dart lib/proctoring_demo/audio_evidence_capture_service.dart
```

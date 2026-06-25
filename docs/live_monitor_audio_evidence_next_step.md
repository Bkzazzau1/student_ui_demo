# Live Monitor Audio Evidence Next Step

Working branch: `codex/onnx-directml-smoke-inference`.

## Ready Files

- `lib/proctoring_demo/microphone_stream_recording_service.dart`
- `lib/proctoring_demo/audio_evidence_capture_service.dart`
- `lib/proctoring_demo/audio_event_evidence_policy.dart`

## Target File

- `lib/proctoring_demo/live_exam_monitor.dart`

## Required Wiring

Add `AudioEvidenceCaptureService` and `AudioEventEvidencePolicy` to `_LiveExamMonitorState`.

Inside `_raiseEvent()`, after the event metadata is enriched and before sending the event, check whether the event is an audio evidence event. When it is, save the recent microphone WAV buffer through `AudioEvidenceCaptureService`, then attach the returned record to the event metadata as `local_audio_record`.

## Events Covered By Policy

- audio voice isolation alert
- background voice environment warning
- repeated audio fingerprint
- microphone reconnect timeout

The policy also captures other warning, high, or critical event types that include the word audio.

## Validation

Run Flutter analyze on the changed proctoring demo files, then run native Rust tests from `native/brain_core`.

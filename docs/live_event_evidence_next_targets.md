# Live Event Evidence Targets

Working branch: `codex/onnx-directml-smoke-inference`.

## Current Completed Evidence Wiring

The local evidence vault now uses Rust first and Dart fallback:

- `lib/proctoring_demo/native_evidence_vault_bridge.dart`
- `lib/proctoring_demo/local_evidence_vault_service.dart`

Live lockdown/system review events now save local records before sending events:

- `lib/proctoring_demo/live_event_local_record_service.dart`
- `lib/proctoring_demo/live_system_lockdown_monitor.dart`

## Next Components To Wire

The same `LiveEventLocalRecordService` should be wired into:

1. `lib/proctoring_demo/live_exam_monitor.dart`
   - camera runtime busy
   - camera reconnect timeout
   - microphone reconnect timeout
   - gaze/head pose review
   - multiple people review
   - object/reflection/shadow review
   - liveness/spoof review
   - voice/audio review

2. `lib/proctoring_demo/review_clip_sampler.dart`
   - review clip captured
   - review clip camera unavailable
   - review clip setup failed
   - review clip capture failed

## Recommended Pattern

Before sending a `LiveProctoringEvent`, create the event, save it locally, add the returned record to metadata, then send the final event.

```dart
final event = LiveProctoringEvent(...);
final localRecord = await _localRecords.saveEvent(event);
if (localRecord != null) {
  enrichedMetadata['local_record'] = localRecord;
}
await _events.send(LiveProctoringEvent(... metadata: enrichedMetadata));
```

## Important

The local record service stores event JSON evidence. Media evidence such as captured review clips should later be copied into the native evidence vault as binary evidence using `saveBytesEvidence`.

## Validation

After each component is wired:

```bash
flutter analyze --no-pub <changed file>
```

For native vault confidence:

```bash
cd native/brain_core
cargo test
```

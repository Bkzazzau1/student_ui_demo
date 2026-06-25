# Camera Evidence Capture Wiring

Working branch: `codex/onnx-directml-smoke-inference`.

## Completed

The following files are ready:

- `lib/proctoring_demo/camera_event_evidence_policy.dart`
- `lib/proctoring_demo/camera_evidence_capture_service.dart`

## What The Service Does

`CameraEvidenceCaptureService` tries to save visual evidence in this order:

1. JPEG snapshot from `CameraController.takePicture()` when the camera is initialized and not streaming images.
2. Latest raw camera frame plane from `LiveCameraFrameBus.latestFrame` when JPEG capture is not safe during live image streaming.

Both paths save through `LocalEvidenceVaultService`, so the evidence flow remains native-first:

`CameraEvidenceCaptureService -> LocalEvidenceVaultService -> Rust native evidence vault -> Dart fallback`

## Events Covered By Policy

- multiple people detected
- camera view needs review
- gaze or head pose deviation
- sustained gaze or head pose deviation
- continuous liveness risk
- object/reflection/shadow risk
- low light guidance
- camera reconnect timeout
- camera runtime busy

The policy also captures other warning, high, or critical event types related to camera, gaze, liveness, object, reflection, shadow, light, people, or person.

## Target File To Wire

`lib/proctoring_demo/live_exam_monitor.dart`

Add fields:

- `CameraEvidenceCaptureService`
- `CameraEventEvidencePolicy`

Inside `_raiseEvent()`, after audio evidence capture and before creating the final `LiveProctoringEvent`, save camera evidence when the policy approves the event. Attach the returned record as `local_camera_record` in event metadata.

## Validation

Run Flutter analyze on:

- `lib/proctoring_demo/camera_event_evidence_policy.dart`
- `lib/proctoring_demo/camera_evidence_capture_service.dart`
- `lib/proctoring_demo/live_exam_monitor.dart`

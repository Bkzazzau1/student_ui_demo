# Secure Exam Lockdown Notes

This branch is the working branch for the student proctoring UI: `codex/onnx-directml-smoke-inference`.

## What is already strong

- Strict exam setup uses Face ID, room scan, audio review, system review, and backend start approval.
- Room scan captures guided views before an exam attempt starts.
- Live exam monitoring already handles camera, audio, gaze/head-pose, liveness, visual integrity, review clips, companion camera, and live event delivery.
- Live event delivery supports backend posting and local queueing when the backend is unavailable.
- Assessment policies separate strict exams, graded assessments, and practice access.

## New lockdown work added

### `lib/proctoring_demo/secure_lockdown_session_service.dart`

Adds a reusable secure exam session service that can:

- start and end a secure session state;
- clear the clipboard at session start;
- collect desktop platform readiness;
- detect prohibited process names such as remote desktop, virtual camera, recorder, VM, messaging, browser, and AI assistant tools;
- detect multiple active displays where the platform allows it;
- return a structured `SecureLockdownSnapshot` for evidence and backend review.

### `lib/proctoring_demo/secure_lockdown_status_panel.dart`

Adds a standalone panel for strict exams. It starts the secure session, repeats checks every few seconds, sends structured live proctoring events, and requests review when the secure session is not ready.

### `lib/proctoring_demo/live_system_lockdown_monitor.dart`

Adds a combined monitor that joins the existing `SystemSecurityReviewService` with the new secure lockdown session. This is intended to replace or sit beside `LiveSystemSecurityMonitor` inside strict exams.

## Recommended next wiring

In `lib/exam_demo/demo_exam_attempt_view.dart`, replace the strict exam system monitor panel with `LiveSystemLockdownMonitor`:

```dart
LiveSystemLockdownMonitor(
  studentId: widget.studentId,
  examId: widget.assessment.id,
  attemptId: widget.attemptId,
  onReviewRequired: _handleCriticalMonitoringEvent,
  assessmentType: widget.assessment.assessmentType,
  reviewAudience: _monitoringProfile.reviewAudience,
),
```

Then import:

```dart
import '../proctoring_demo/live_system_lockdown_monitor.dart';
```

## Next phase

- Add true full-screen desktop shell control.
- Add encrypted answer autosave.
- Add screen evidence capture or periodic screenshots.
- Add final integrity report after submission.
- Move deeper OS-level operations into Rust/FFI where Flutter/Dart cannot enforce them reliably.

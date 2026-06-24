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

Adds a combined monitor that joins the existing `SystemSecurityReviewService` with the new secure lockdown session. It checks system devices and secure exam state together, then sends review events when the session is not ready.

### `lib/proctoring_demo/live_system_security_monitor.dart`

The existing system security monitor now delegates to `LiveSystemLockdownMonitor`. This means the current strict exam attempt UI receives the secure lockdown checks through its existing system-monitor panel without rewriting `demo_exam_attempt_view.dart`.

## New recovery work added

### `lib/exam_demo/secure_attempt_autosave_service.dart`

Adds a secure attempt autosave service for exam recovery. It stores local attempt snapshots with:

- student ID, exam ID, and attempt ID;
- answer map;
- current question index;
- remaining exam seconds;
- start/update timestamps;
- SHA-256 checksum for tamper-evident recovery validation.

This is a recovery MVP. It is not full encrypted secure storage yet. The next step is to wire it into `DemoExamAttemptView`, then replace local plain storage with OS secure storage or a Rust-backed encrypted store.

## Current behavior

When a strict exam uses the system security panel, the UI now runs both:

- the existing system device review; and
- the new secure exam session review.

If either review fails, the monitor sends a live proctoring event and calls the exam attempt's review handler so the exam can pause or enter invigilator review according to the existing risk policy.

## Next phase

- Wire `SecureAttemptAutosaveService` into `DemoExamAttemptView`.
- Add true full-screen desktop shell control.
- Add screen evidence capture or periodic screenshots.
- Add final integrity report after submission.
- Move deeper OS-level operations into Rust/FFI where Flutter/Dart cannot enforce them reliably.

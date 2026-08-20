# Debug exam-start override

The exam-start override exists only for local development and hardware/AI
integration testing. Never distribute an override build for a real exam.

Run from the repository root:

```powershell
powershell -ExecutionPolicy Bypass -File .\tool\run_exam_override.ps1
```

The script enables exam, audio, system, local-start, and monitoring review
overrides, relieves lockdown, and explicitly disables real-exam mode. The
application remains a debug build so `RuntimeSafetyPolicy` can reject strict
exam overrides in release builds.

Expected flow:

1. Sign in and select an exam.
2. The setup page displays testing-ready messaging.
3. Start approval uses a local development token when the backend is absent.
4. The attempt opens with monitoring in warn-only mode.
5. Camera, gaze, object, and audio signals still generate review events.
6. Each live event is sent to Python for temporal review.
7. Python action proposals must still pass the Rust allow-list.
8. Local evidence remains managed by Rust/device services.


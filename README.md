# K-SLAS Student Portal

Professional student-facing presentation UI for secure assessments.

The student screens must use plain language only: identity check, room scan, security review, evidence record, and invigilator review.

## Run

```bash
flutter clean
flutter pub get
flutter run -d windows
```

## Recommended presentation path

1. Open the app.
2. Select the proctored examination.
3. Complete Face ID enrolment.
4. Run the 360 room scan.
5. Start the exam after review approval.
6. Submit and show the result summary.

## Before real testing

- Keep camera monitoring active during the whole live exam.
- Add real microphone streaming.
- Add app/window, clipboard, multiple-monitor, and remote-desktop detection.
- Capture real screenshot, audio, and camera evidence files.
- Send live events to the backend staging API.
- Calibrate detection using Nigerian exam-room conditions.

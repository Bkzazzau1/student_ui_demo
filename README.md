# K-SLAS Student Portal

Student-facing secure assessment app for K-SLAS proctored examinations.

This repository is no longer treated as a static presentation mockup. It is the foundation for the real student exam flow: assessment selection, Face ID setup, 360 room scan, security review, live exam attempt, continuous camera monitoring, submission, and result summary.

The student screens must use plain language only: identity check, room scan, security review, evidence record, and invigilator review.

## Run

```bash
flutter clean
flutter pub get
flutter analyze
flutter test
flutter run -d windows
```

## Student exam flow

1. Open the app.
2. Select the proctored examination.
3. Complete Face ID enrolment.
4. Run the 360 room scan.
5. Start the exam after review approval.
6. Keep camera monitoring active during the exam.
7. Submit and show the result summary.

## Production requirements still pending

- Send live camera monitoring events to the backend.
- Keep microphone monitoring active during the exam.
- Add app/window, clipboard, multiple-monitor, and remote-desktop detection.
- Capture real screenshot, audio, and camera evidence files.
- Send live events to the backend staging API.
- Display live exam events on the invigilator/reviewer dashboard.
- Calibrate detection using Nigerian exam-room conditions.

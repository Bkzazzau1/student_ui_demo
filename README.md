# K-SLAS Student Portal

Dedicated student-facing presentation UI.

This repo is intentionally focused on the student-facing presentation flows:

- Examinations
- Face ID setup
- Pre-exam security check

The proctoring flow captures the guided scan, stores an evidence manifest, and shows a security review decision without changing the production local AI models in the main student app.

## Run

```bash
flutter clean
flutter pub get
flutter run -d windows
```

For web preview:

```bash
flutter run -d chrome
```

## Student Path

1. Open the app.
2. Choose an examination.
3. Set up Face ID if the exam is graded.
4. Run the pre-exam security check for remote proctored exams.
5. Start the exam.
6. Submit and view the result summary.

# K-SLAS Student UI Demo

Dedicated presentation UI for the demo.

This repo is intentionally focused on the student-facing presentation flows:

- Examinations
- Face ID setup
- Agentic AI pre-exam proctoring gate

The proctoring shown here is a controlled presentation flow for the demo. It captures the guided scan, stores an evidence manifest, and shows an agentic review decision without changing the production local AI models in the main student app.

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

## Demo path

1. Open the app.
2. Choose an examination.
3. Set up Face ID if the exam is graded.
4. Run the proctoring gate for remote proctored exams.
5. Start the exam demo.
6. Submit and view the result summary.

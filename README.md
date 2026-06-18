# K-SLAS Student UI Demo

Dedicated presentation UI for the demo.

This repo is intentionally focused on only two student-facing flows:

- Examinations
- Face ID setup

The full local AI proctoring flow is not loaded in this presentation shell. This keeps the demo clean and stable while we prepare the production student app separately.

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
4. Start the exam demo.
5. Submit and view the result summary.

# K-SLAS Student Portal

Professional student-facing presentation UI for the K-SLAS secure assessment experience.

This repository is a presentation build, but it is structured like a real product flow instead of a static mockup. It demonstrates how a student moves from assessment selection into Face ID enrolment, pre-exam security scanning, backend review, exam attempt, submission, and result summary.

## What this demo shows

- Student examination and continuous assessment dashboard
- Face ID enrolment for graded assessments
- Pre-exam 360 room scan for remote-proctored exams
- Evidence image capture and local manifest generation
- Multipart backend submission for security review
- Agentic review decision: approved, rescan required, or human review required
- Exam attempt screen with objective, fill-in-the-blank, and theory questions
- Submission summary with proctoring manifest reference

## Agentic AI flow

The student UI presents the same operating model intended for the full K-SLAS proctoring engine:

1. Identity Agent verifies the registered student.
2. Environment Agent checks the student room and desk area.
3. Backend Review receives the evidence manifest and captured images.
4. Risk / Evidence decision returns whether the student can start, must rescan, or needs human review.

The current repo does not replace the production local AI models in the main student application. It is a polished, backend-ready presentation layer for demonstrating the student journey.

## Backend integration

The proctoring review client posts to:

```text
POST /api/proctoring/pre-exam-review
```

Runtime backend URL can be supplied with:

```bash
flutter run -d windows --dart-define=KSLAS_API_BASE_URL=http://127.0.0.1:8080
```

If the backend review service is unavailable, the UI moves the attempt into a review-required state instead of silently approving the student.

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

## Recommended presentation path

1. Open the app.
2. Select the mid-semester proctored examination.
3. Complete Face ID enrolment.
4. Run the pre-exam security centre scan.
5. Allow the backend review result to approve, request rescan, or require invigilator review.
6. Start the exam.
7. Submit and show the result summary.

## What must still be added before real testing

- Keep local camera AI active during the whole live exam, not only during startup.
- Add real microphone streaming for baseline noise, sound classification, and voice detection.
- Add real app/window, clipboard, multiple-monitor, and remote-desktop detection.
- Capture actual evidence files for screenshots, audio, and camera events.
- Send live proctoring events to the backend staging API and display them on invigilator/reviewer dashboards.
- Calibrate face, phone, paper/book, and audio detection using Nigerian exam-room conditions.

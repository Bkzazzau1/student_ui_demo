# K-SLAS Smart Exam Monitoring: Pilot-Ready Institutional Scope

This branch is no longer framed as a small MVP. The target is a pilot-ready institutional product that can impress university leadership, support real examination testing, and show a credible path to production.

## Product Position

K-SLAS Smart Exam Monitoring is a local-first secure examination platform. It should run continuous monitoring on the student device, send structured activity records to the backend, support invigilator review, and prepare evidence-backed review cases for exam officers and HoDs.

The system must look and behave like a serious university product, not a prototype.

## Pilot-Ready Standard

The first serious release should include more than basic login and exam-taking. It should show a complete controlled-exam journey:

1. Student secure exam setup
2. Identity check
3. Camera check
4. Microphone check
5. Room scan
6. Secure exam mode
7. Screen/app activity checks
8. Local camera monitoring during the whole exam
9. Local microphone monitoring during the whole exam
10. Local activity records and offline queue
11. Attempt autosave and recovery
12. Attention-level calculation
13. Invigilator live alerts
14. Evidence file creation for important events
15. Review case timeline
16. Final review report

## More Than MVP Student App

The student app should support:

- desktop-first secure exam mode;
- device-sensitive access rules for final exams and graded assessments;
- guided setup before the exam starts;
- full exam attempt screen with question navigation and timer;
- live camera and microphone monitoring;
- system and secure exam checks;
- clipboard and app activity records;
- local answer autosave with tamper-evident checksum;
- offline event queue;
- calm student warnings using approved UI wording;
- selected evidence capture when review is needed;
- clean submission and recovery behaviour.

## More Than MVP Local Monitoring

The local device should handle continuous checks for:

- face clearly visible;
- another person may be visible;
- student leaving the camera view;
- camera blocked;
- repeated looking away;
- phone or paper may be visible;
- voice noticed;
- more than one voice noticed;
- voice may be coming from outside student area;
- sound from another device may be present;
- exam screen left;
- opening another app;
- paste control;
- remote access not allowed;
- extra screen may be connected.

## More Than MVP Backend/Dashboard Expectations

The backend and dashboard should support:

- live student exam sessions;
- incoming activity records;
- attention level per student;
- live alert feed;
- student activity timeline;
- invigilator warning action;
- mark incorrect alert;
- send for review;
- review case generation;
- exam officer comments;
- HoD final decision path;
- activity history and audit log;
- evidence storage period settings.

## Evidence Standard

Clean students should keep minimal records only. Students with review activity should keep selected evidence:

- activity timeline;
- screenshot around important screen events;
- short audio clip around important sound events;
- short camera clip or image around important camera events;
- invigilator notes;
- review summary;
- final decision.

## UI Wording Standard

Student screens must avoid harsh or final-judgement language. Use calm wording:

- Smart exam monitoring
- Secure exam mode
- Activity noticed
- Review may be required
- Record saved for review
- Attention level
- Please return to the exam screen
- A phone may be visible
- Voice noticed

Avoid student-facing words such as violation, cheating detected, misconduct confirmed, AI proved, risk score, suspicious, endpoint, metadata, payload, and model binding.

## Build Priority After Current Branch Work

1. Wire attempt autosave into `DemoExamAttemptView`.
2. Attach live local camera checks during the whole exam.
3. Add real microphone stream and sound baseline.
4. Add stronger screen/app/clipboard/display checks.
5. Produce real evidence files, not only pending manifests.
6. Send activity records to backend staging endpoints.
7. Build invigilator live dashboard event display.
8. Add review case timeline and report screen.
9. Calibrate camera, phone, paper, and audio checks using Nigerian exam-room conditions.
10. Prepare a polished demo flow for university leadership.

## Final Standard

This project should be presented as a pilot-ready institutional examination monitoring platform, not as an MVP. The first release must be strong enough to demonstrate security, fairness, local AI cost-control, human review, evidence records, and administrative workflow.

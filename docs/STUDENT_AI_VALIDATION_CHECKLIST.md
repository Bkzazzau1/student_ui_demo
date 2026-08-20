# Student AI validation checklist

Run these checks on the release build. The AI reports observable signals for
human review; it must never make a final misconduct decision.

## 1. Runtime gate

- Open a strict supervised exam and confirm **Edge AI runtime** completes.
- Temporarily remove one model in a copied test package and confirm exam start
  remains locked with a useful error.
- Disconnect the network and confirm all local checks continue to operate.

## 2. Face enrollment and 1:1 verification

- Enroll six guided captures in even daylight, dim light, with glasses, and
  without glasses where applicable.
- Verify the enrolled student at least 20 times across supported cameras.
- Try at least 20 non-matching people and confirm no automatic accusation is
  produced.
- Test printed-photo and replay attempts; confirm liveness failure requests
  another capture or review.
- Measure false acceptance and false rejection by device, lighting, skin tone,
  glasses, and accessibility cohort before choosing a production threshold.

## 3. Gaze and head calibration

- Complete all five targets with at least three accepted samples per target.
- Confirm a profile is scoped to the current attempt and expires as designed.
- Look naturally at the question, answer choices, and keyboard; these should
  remain near the student's baseline.
- Look away left/right/up/down for 1, 3, 5, and 10 seconds and verify zone,
  duration, confidence, and signal quality are reported.
- Cover the eyes, leave frame, and use poor lighting; low-quality data must be
  marked unavailable rather than treated as suspicious behavior.

## 4. Audio calibration and observation

- Calibrate in quiet, fan noise, traffic noise, and low-quality microphones.
- Test silence, the enrolled speaker, a second speaker, overlapping speech,
  music, and sudden noise.
- Confirm decisions use deviations from the local baseline and include duration
  and confidence; audio alone must not trigger a final misconduct label.

## 5. Object and device observation

- Test allowed desk items and configured prohibited objects from multiple
  distances and angles.
- Test phone, second screen, paper, calculator, partial objects, reflections,
  and background posters.
- Confirm repeated detections use cooldowns and low-confidence detections only
  create reviewable observations.

## 6. Temporal fusion and policy

- Reproduce single weak signals and confirm they do not escalate by themselves.
- Reproduce sustained or correlated face, gaze, audio, and object signals and
  verify Python returns an explainable temporal observation.
- Confirm Rust independently authorizes any device action and fails closed when
  Python is unavailable or sends malformed data.
- Confirm every event records timestamps, signal quality, contributing signals,
  model/runtime version, and policy reason.

## 7. Recovery, privacy, and security

- Kill and restart the app during an attempt; verify encrypted recovery and no
  duplicate event upload.
- Test offline event queuing followed by authenticated synchronization.
- Confirm raw frames/audio are not retained unless the configured evidence
  policy explicitly permits it.
- Verify encrypted templates cannot be used on another account or altered
  without detection, and test consent withdrawal/deletion workflows.
- Confirm students can see required disclosures and reviewers can correct or
  dismiss observations.

## Release gates

- Zero analyzer, Flutter, Rust, and Python test failures.
- Signed model manifest and reproducible model hashes.
- Measured latency, CPU, memory, battery, and thermal behavior on every minimum
  supported device class.
- Documented FAR/FRR and subgroup performance with an approved threshold.
- Completed privacy impact assessment, retention schedule, accessibility review,
  security review, and human appeal workflow.

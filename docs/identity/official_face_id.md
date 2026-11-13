# Official Face ID

How K-SLAS confirms that the person writing an exam is the registered
student. This replaces the earlier device-only enrollment, where a Face ID
was approved and stored only on the device that captured it.

## Design in one paragraph

A student registers their face once. The school approves it, and it becomes
the student's **official Face ID**. The student can then sign in on any
approved laptop or tablet. Before an exam, the app downloads the student's
official Face ID, checks it, and compares the live camera with it **on the
device** (edge AI, 1:1 only). The questions download only after that check
passes. During the exam, unannounced checks repeat the comparison. The device
sends only the **results** to the school, as evidence. A "no" pauses the exam
and asks for a full recheck. Nothing is submitted automatically because of a
face result; a person decides.

## Who does what

| Step | Where | Notes |
|---|---|---|
| Registration photos | Student device | Consent, then 7 guided poses. Front first, the other 6 in a random order per session. Each pose must still match the first front photo. |
| Approval | School system | Staff review the photos and approve or reject them. On approval the school **rebuilds** the template from the approved photos and signs it. |
| Template download | Exam device | Downloaded for the signed-in student only, verified on the device, and kept encrypted for in-exam rechecks. |
| Pre-exam check | Exam device | Random liveness challenge. Identity is matched on the **same frames** that proved liveness. 3 tries, then "contact your invigilator". |
| Questions | School system → device | Released only with a fresh identity pass for this student, exam and attempt. |
| In-exam checks | Exam device | Silent, at random times, on Windows (stills) and Android (stream). |
| Evidence | Device → school | Sealed, hash-chained records. A photo is kept only for a failed check, for 30 days. |

## Trust model

- **The device never makes a Face ID official.** It accepts a template only
  if its Ed25519 signature verifies against a key the build trusts
  (`IdentityTrustPolicy`).
- **Every 1:1 match re-checks the template.** `match_official_face_template_1_to_1`
  (Rust, `native/brain_core/src/api/official_face_id.rs`) verifies the
  signature, the student id, the model id and hash, the preprocessing
  version, and the expiry on every call.
- **The signature covers the exact payload bytes** in the envelope, so any
  issuer can produce templates. The envelope format is
  `kslas.signed_official_face_template.v1`; the signed message is
  `"kslas.official_face_template.v2\n" + payload`.
- **The school rebuilds templates from photos.** A modified app could
  otherwise send genuine photos with another person's embeddings. The device
  embeddings are kept only to detect a mismatched submission (cosine < 0.90
  for any photo refuses approval). Storing the photos also lets the school
  rebuild every template when the face model is upgraded, without asking
  students to register again.
- **Matching score:** the mean of the two best reference similarities
  (references are the approved poses). Centroid similarity is recorded for
  evidence and calibration only.

## Exam-time policy

| Rule | Value | Where |
|---|---|---|
| Match threshold | 0.55 (not yet calibrated) | `FaceIdentityVerificationService` |
| Minimum sample quality | 0.65 | same |
| Samples per pre-exam try | up to 3 reliable, a majority of at least 2 must agree | `FaceIdentityCheckView` |
| A pass needs | at least 1 matching frame from inside the liveness challenge | same |
| Pre-exam tries | 3, then locked for this exam until the invigilator releases it | `IdentityAttemptLock` |
| First in-exam check | random, 20–90 s after start | `IdentityCheckScheduler` |
| Later in-exam checks | random, 60–360 s apart | same |
| After one "no" | silent follow-up in 8–20 s | `ContinuousIdentityPolicy` |
| Pause the exam | 2 "no" results in a row, or 6 checks in a row that cannot see the face | same |
| Recheck after a pause | full check with liveness, 3 tries; on failure the exam stays paused, answers are saved, and the student is told to contact the invigilator | `DemoExamAttemptView` |
| Frozen camera | byte-identical frames inside one check count as a failed check | `InExamIdentityChecker` |
| Timer during an identity pause | paused (existing exam behaviour) | `DemoExamAttemptView` |

"Uncertain", "too blurred" and "AI unavailable" never count as a "no".

## Evidence records

Schema `kslas.identity_evidence.v1` (`IdentityEvidenceOutbox`):

- `check_kind`: `pre_exam`, `in_exam_random`, `in_exam_follow_up` or
  `pause_recheck`.
- `decision` and `reason`.
- `similarity`, `centroid_similarity` and `threshold`.
- `matched_samples`, `reliable_samples` and `samples_attempted`.
- The liveness summary.
- The template id and envelope hash.
- The model id, model hash and preprocessing version.
- The device class and the policy used.

Each record carries `record_sha256`, a SHA-256 over sorted-key JSON (excluding
the seal and photo bytes), and `previous_record_sha256` for the same student
and attempt. A deleted or edited record therefore breaks the chain.

Photos are kept only for a mismatch or a liveness failure, as
`review_photo_jpeg_b64` with `review_photo_sha256`. They are removed after 30
days; the hash stays, so the seal remains valid. Records stay encrypted on
the device until the school accepts them.

## What the university system must provide

The app talks to the school only through `SchoolIdentityService`
(`lib/face_demo/school_identity_service.dart`):

| Call | Purpose |
|---|---|
| `fetchStatus(studentId)` | Active template id and approval time, pending submission, last rejection reason. |
| `submitRegistration(submission)` | Accepts photos, device embeddings, consent version, capture device and pose order (`kslas.official_face_id_submission.v1`). |
| `downloadOfficialTemplate(studentId)` | The signed envelope for the signed-in student only. Must require that student's own authentication. |
| `uploadIdentityEvidence(records)` | Stores sealed records and returns the ids it accepted. |
| (questions) | Release exam questions only for a valid identity pass whose evidence record it has received. |

The school system must also:

- review the photos (staff),
- rebuild references with the same model and preprocessing,
- sign them with its own key (never shipped to devices), and
- publish the public key so it can be pinned in
  `IdentityTrustPolicy.productionTrustedKeysJson`.

## Local sample school (testing only)

Until the university system is connected,
`LocalSampleSchoolIdentityService` plays the school on the device:

- storage is encrypted (DPAPI on Windows, Keystore on Android) under
  `KSLAS/sample_school`;
- it uses a per-install sample signing key;
- **Face ID → Sample school admin (testing only)** approves or rejects
  registrations and shows the evidence it received.

Release builds do not trust the sample school unless they are built with
`--dart-define=KSLAS_ALLOW_SAMPLE_SCHOOL=true`. **A production release must
not set that flag.**

Test flow:

1. Sign in.
2. Open **Face ID** and register.
3. Approve the registration in the sample admin.
4. Start a graded exam.

## Devices

- Exams run only on laptops and tablets; phones can take quizzes and graded
  assessments (`AssessmentDeviceAccessPolicy`).
- The face runtime is implemented for Windows and Android.
- iPad is allowed by the device policy, but the iOS face runtime is not
  built yet, so identity checks report "AI unavailable" there.

## Known limits and next steps

- **Thresholds are not calibrated.** 0.55 and 0.65 are conservative guesses.
  They must be set from a volunteer study with genuine and impostor pairs, on
  the target laptops and tablets.
- **Liveness is challenge/motion based.** It stops printed photos and
  "liveness then photo" swaps. A screen replay of a pre-recorded video of the
  right challenge, or a live deepfake, may still pass; a dedicated
  presentation-attack model is future work.
- **Passive in-exam liveness** is limited to frozen-frame detection. The
  pause recheck carries the full liveness challenge.
- **Face pipeline (`sface-5pt-ls-bilinear-rgb255-v2`).** On Windows, YuNet
  finds the face, the face mesh runs on a crop around it, five points are
  aligned with a least-squares similarity, and SFace receives raw RGB.
  Android uses MediaPipe's own face detector. The previous pipeline accepted
  almost anyone; see `face_pipeline_benchmark.md`. Templates made with
  earlier preprocessing no longer verify; the school rebuilds them from the
  stored photos (**Sample school admin → Rebuild approved Face IDs**).
- **Android native library is out of date.** The committed
  `android/app/src/main/jniLibs/arm64-v8a/libbrain_core.so` predates the
  current Rust bindings, so the bridge's content-hash check fails at startup
  on Android. It must be rebuilt from `native/brain_core` for
  `aarch64-linux-android` before Android testing.
- **Sample-only stand-ins:** the invigilator release buttons, and the
  question gate's local check of the pass, are stand-ins for the school
  system.
- **Consent text** (`OfficialFaceIdConsent`) is a draft for the school's data
  protection officer to review.

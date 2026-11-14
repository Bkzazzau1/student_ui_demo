# K-SLAS on iPad

iPads run the full exam: Face ID registration and the 1:1 identity checks,
liveness, the proctoring camera with object detection, sound checks, and
exam lockdown. iPhones stay limited to quizzes and graded assessments, the
same as Android phones.

## What runs on the iPad

Everything runs on the device; only check results are sent to the school.

| Part | iPad implementation | Same as |
|---|---|---|
| Rust core (`brain_core`) | `brain_core.framework`, loaded by Flutter Rust Bridge | Windows and Android |
| Face landmarks | MediaPipe Face Landmarker 0.10.35, `face_landmarker.task` | Android (same model and version) |
| Face ID embedding | SFace via ONNX Runtime 1.22 on the CPU | Android (same runtime version) |
| Object detection | Exam YOLO via ONNX Runtime on the CPU | Android |
| Protected storage | AES-256-GCM; key in the Keychain, this device only | Android Keystore |
| Exam lockdown | Guided Access | Android screen pinning |

The Swift code is in `ios/Runner/Kslas*.swift`. Minimum version: iPadOS 15.1
(ONNX Runtime needs it), which covers the iPad 5th generation and newer.

### Camera frames

The iOS camera plugin delivers stream frames already upright, and mirrors
front-camera frames to match the preview, while photos are not mirrored. The
app undoes the mirror (`CameraFrameOrientation`), so live checks and
registration photos show the face the same way on every platform.

## Exam lockdown: Guided Access

iPadOS does not let an ordinary app lock itself to the screen, so the exam
uses Guided Access:

1. Before the questions open, the app asks the student to turn on Guided
   Access: triple-click the top (or Home) button, then tap Start. The exam
   opens as soon as it is on. If Guided Access was never set up, the student
   turns it on in Settings > Accessibility > Guided Access and sets a
   passcode.
2. During the exam, the app watches for changes:
   - **Guided Access turned off:** the exam pauses (answers saved, timer
     stopped) until it is back on. The school receives an
     `exam_guided_access_ended` event.
   - **Screen recording or mirroring:** the exam pauses until it stops
     (`exam_screen_capture_started`).
   - **Screenshot:** recorded for review (`exam_screenshot_taken`). iOS cannot
     block screenshots, but with Guided Access on the buttons that take them
     are disabled by default.
3. Leaving the app ends the exam the same way as on Android: graded exams are
   submitted.

Limits to know:

- The student sets the Guided Access passcode, so they can end it. They
  cannot hide that: the exam pauses and the school gets the event.
- On **school-managed iPads** (MDM, supervised) with Autonomous Single App
  Mode allowed for K-SLAS, the app turns Guided Access on and off by itself
  and the student cannot leave. No code change is needed.

## How it is checked without a Mac

`.github/workflows/ios.yml` runs on a GitHub macOS machine for every change to
the app:

1. builds the Rust core for iOS (`scripts/ios/build_brain_core.sh`);
2. builds the app for iPad devices (unsigned), which compiles all Swift code;
3. starts an iPad simulator and runs
   `integration_test/native_runtime_parity_test.dart`. That test runs the
   real native code and compares it with the Python/ONNX Runtime reference
   (`ai_runtime/tools/build_native_parity_fixture.py`):
   - the Face ID embedding must match the reference (cosine above 0.9999);
   - face landmarks must match the reference points;
   - mirrored, rotated and YUV camera frames must give the same landmarks;
   - the full Face ID pipeline must embed the test face like the reference;
   - YOLO must find the same person box;
   - protected storage must round-trip and refuse the wrong student;
   - Guided Access status must be reported.

The same test also runs on Windows and Android:
`flutter test integration_test/native_runtime_parity_test.dart -d <device>`.

The simulator has no camera, so the live camera, Guided Access and real iPad
speed still need a test on an iPad (see below).

## Installing on an iPad: Codemagic and TestFlight

`codemagic.yaml` builds the signed app on Codemagic's Macs and uploads it to
TestFlight. Students and testers install it with the TestFlight app.

One-time setup:

1. **Bundle ID.** Choose the app's bundle ID (for example
   `ng.edu.<school>.kslas`; `com.example...` is not accepted by Apple).
   Register it in the Apple Developer account under Certificates,
   Identifiers & Profiles, and set `BUNDLE_ID` in `codemagic.yaml`.
2. **App Store Connect.** Create the app with that bundle ID. Create an API
   key (Users and Access > Integrations > App Store Connect API, role App
   Manager) and download the `.p8` file.
3. **Codemagic.** Sign in with GitHub, add this repository, and create the
   environment group `app_store_connect` with `APP_STORE_CONNECT_ISSUER_ID`,
   `APP_STORE_CONNECT_KEY_IDENTIFIER`, `APP_STORE_CONNECT_PRIVATE_KEY` (the
   `.p8` contents) and `CERTIFICATE_PRIVATE_KEY` (an RSA key Codemagic uses to
   create the distribution certificate).
4. Start the `ipad-testflight` workflow from Codemagic, or push a tag such as
   `ios-v1.0.0`.
5. In App Store Connect > TestFlight, add testers. They install TestFlight on
   the iPad and accept the invitation.

When uploading, App Store Connect asks about encryption. The app uses only
the encryption built into iOS (HTTPS and the Keychain); answer the export
compliance question for your institution.

## Building on a Mac (optional)

```sh
bash scripts/ios/build_brain_core.sh
flutter pub get
flutter run -d <ipad>
```

## First iPad test

1. Register a Face ID (front camera, 7 photos) and approve it in the sample
   school admin.
2. Start an exam: allow the camera and microphone, turn on Guided Access when
   asked, and pass the identity check.
3. During the exam, turn Guided Access off (triple-click and passcode): the
   exam must pause, and resume when it is back on.
4. Start screen recording from Control Center before starting an exam: the
   app must refuse to start until it stops. During the exam (Control Center is
   blocked by Guided Access), connect a display adapter to mirror the screen:
   the exam must pause.
5. Hold the iPad in landscape and portrait: identity checks must pass in both.

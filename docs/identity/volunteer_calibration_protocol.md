# Volunteer calibration study for Face ID

The match threshold that decides "same person" must come from real people on
the laptops and tablets students will use. A public benchmark only shows the
pipeline works in principle; see `face_pipeline_benchmark.md`. This study
sets the number the app enforces.

## What the study decides

- **The match threshold:** `FaceIdentityVerificationService.matchThreshold`.
- **Whether the minimum sample quality is right:** `minSignalQuality`.
- **Error rates per device class**, reported for the institution's records:
  - how often a real student is asked to retry (FRR);
  - how often another person is accepted (FAR).

## Who

- **At least 30 volunteers; 50 or more is better.** Each volunteer is compared
  against every other one. With 50 volunteers and 18 exam photos each, that
  gives about 44,000 impostor comparisons, enough to show a FAR below 0.1%
  with 95% confidence.
- **Include the student population's variety:**
  - skin tones, women and men, ages;
  - glasses, headscarves and hijabs, beards and make-up.
  - Siblings or look-alikes are especially useful, if they agree to take part.
- **Everyone signs the consent form first** (`volunteer_study_consent.md`,
  approved by the data protection officer). It says that:
  - the photos are used only for this study;
  - they are stored encrypted and never shared;
  - they are deleted within 30 days of the final report.

## Devices

Use the device types students really have:

- at least two typical student laptops (built-in webcams, including a
  low-end one),
- at least one Android tablet, and
- at least one iPad.

Take the exam photos with the app's own camera settings (front camera, medium
resolution, about 640×480), not a phone's best camera.

## Capturing with the app

Take every photo with the app's **Volunteer study** screen (sample school
admin > *Volunteer study (Face ID threshold)*), on each study device. It uses
the same camera settings and face pipeline as the real checks, keeps the
photos encrypted on the device, and exports them in the layout below. Only
study codes are entered, never names.

1. **Approval and consent.** Get the data protection officer's (and ethics
   committee's) approval of `volunteer_study_consent.md`. Each volunteer signs
   the paper form; staff write the study code (`v001`, ...) on it.
2. **Label the device** once, for example `laptop-dell-3520`,
   `tablet-samsung-a8` or `ipad-10`.
3. **Add the volunteer:** enter the study code and confirm the signed form
   (and the optional spoofing test, if agreed).
4. **Registration**, once per volunteer, on one device, in good, even light:
   the same guided 7-pose screen students use.
5. **Exam photos, on every study device.** Each session takes 3 photos
   automatically while the volunteer looks at the screen as when writing:
   - **Session A:** normal room light.
   - **Session B:** harder light (dim room, or a window or lamp behind).
   - **Session C:** on a different day from registration; change glasses or
     headscarf (on or off) if the volunteer wears them.

   A photo the app would reject for quality (no face, blur, framing) is not
   kept, as in a real check, but it is counted in the capture log.
6. **Spoofing check** (only with the optional consent; not used for the
   threshold). Try the pre-exam check with a printed photo, a photo on a phone
   screen and a video of the volunteer on a phone. Record whether the liveness
   step stopped each one.

**Withdrawal:** open the volunteer and choose *Delete this volunteer* on every
study device, and delete their folders from any exports.

## Exporting and merging

On each device, choose **Export study photos**. The app writes plain JPEGs and
a `capture_log_<device>.json` (codes, consent versions, dates and how many
photos were not usable; no names) to:

- **Windows:** `Documents\KSLAS study exports\`
- **Android:** `Android/data/<app id>/files/study_exports/` (reach it over USB)
- **iPad:** the app's Documents folder (Files app > On My iPad > the app's
  folder)

Copy each export's contents into one `study/` folder on the analysis computer.
Paths from different devices never collide. Move the files only on encrypted
drives, and delete the copies once the report is made.

## Folder layout

```
study/
  v001/
    registration/  front_face.jpg left_angle.jpg ... (the 7 poses)
    probes/
      laptop-dell-3520/  a1.jpg a2.jpg a3.jpg b1.jpg ... c3.jpg
      tablet-samsung-a8/ a1.jpg ...
  v002/
    ...
  capture_log_laptop-dell-3520.json
```

The tool groups each device's photos in threes, in name order, to simulate the
pre-exam "two of three" check, so keep the app's names.

## Running the tool

```
python -m ai_runtime.face_identity_calibration --study study --out report.json --target-far 0.001
```

It needs the `ai_runtime/requirements-e1-numerical.txt` packages and the model
files (Git LFS). It reads the photos in place. The report contains scores and
counts only, no photos or embeddings.

## Reading the report

`recommended` holds the lowest threshold whose 95% upper bound on FAR meets
the target, together with:

- the single-photo FRR;
- the pre-exam "two of three" session FRR and FAR.

If `meets_target` is false, the study is too small for the target: add
volunteers or exam photos. Do not lower the target to make it pass.

- **`per_device`:** if one device class has a much higher FRR, check its
  camera and lighting before accepting the threshold.
- **`curve`:** FAR/FRR from 0.20 to 0.90, for the institution's records.

## After the study

1. Set `matchThreshold` to the recommended value. Record the study id and
   date in `docs/identity/official_face_id.md`.
2. Keep `report.json` with the institution's model-validation records.
3. Delete the photos within the promised period.
4. Run the study again after any change to the face model, to
   `preprocessingVersion`, or to the target devices.

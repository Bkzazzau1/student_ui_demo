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
- **Everyone signs a consent form first.** It says that:
  - the photos are used only for this study;
  - they are stored encrypted and never shared;
  - they are deleted within 30 days of the final report.

## Devices

Use the device types students really have:

- at least two typical student laptops (built-in webcams, including a
  low-end one), and
- at least one Android tablet.

Take the exam photos with the app's own camera settings (front camera, medium
resolution, about 640×480), not a phone's best camera.

## What to capture per volunteer

1. **Registration.** Take the seven guided poses in good, even light: front,
   left, right, down, up, smile, mouth open. Use the app's Face ID
   registration flow (or follow the same instructions with the study laptop).
2. **Exam photos, on every study device:**
   - **Session A** (normal room light): 3 photos, looking at the screen as
     when writing.
   - **Session B** (harder light: dim room, or a window behind): 3 photos.
   - **Session C** (glasses or headscarf changed, if applicable): 3 photos.
   - At least one session on a different day from registration.
3. **Spoofing check.** This is separate and not used for the threshold. Try
   the pre-exam check with:
   - a printed photo,
   - a photo on a phone screen, and
   - a video of the volunteer played on a phone.

   Record whether the liveness step stopped each one.

## Folder layout

```
study/
  v001/
    registration/  front.jpg left.jpg ... (the 7 poses)
    probes/
      laptop-dell-3520/  a1.jpg a2.jpg a3.jpg b1.jpg ...
      tablet-samsung-a8/ a1.jpg ...
  v002/
    ...
```

Use study codes (`v001`), never names, for folders.

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

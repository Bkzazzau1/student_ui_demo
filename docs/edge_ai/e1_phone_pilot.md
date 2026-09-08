# E1 Phone Detection — First Real Capture Pilot

## Purpose

This is the first hands-on E1 data-collection exercise.

It is intentionally small. Its goal is to teach and verify the real collection workflow before K-SLAS scales to all E1 classes.

This pilot does **not** constitute a trainable production dataset and must not be reported as model evidence.

The live E1 runtime remains frozen. No live exam architecture changes are part of this exercise.

## 1. What we are learning

This pilot introduces four core ideas using one easy-to-understand object: `phone`.

### Sample

One retained image, together with its source provenance, becomes one dataset sample.

Example:

```text
images/base-pilot-p001-phone-hand-001/frame-0001.jpg
```

After annotation, that image may contain a `phone` bounding box and a `person` bounding box.

### Positive sample

A positive sample contains the target object.

For this pilot:

```text
phone visible -> positive for `phone`
```

### Negative sample

A negative sample contains no `phone`.

For this pilot:

```text
empty hand -> negative for `phone`
```

### Hard negative

A hard negative does not contain the target object, but contains something that may visually confuse the detector.

For this pilot:

```text
remote control -> hard negative for phone confusion
```

The remote itself is still a valid canonical E1 base class: `remote`. It must never be mislabeled as `phone`.

## 2. The three source groups

Capture exactly three independent source groups for this first exercise.

### Source Group A — Phone positive

Recommended ID:

```text
base-pilot-p001-phone-hand-001
```

Scene:

- one participant seated as if taking an exam;
- phone naturally visible in one hand;
- camera placed approximately as a normal K-SLAS laptop/webcam would be;
- no need for studio-perfect lighting.

During one short recording, slowly vary the phone naturally:

- upright;
- slightly rotated;
- partly covered by fingers;
- closer to desk level;
- slightly toward the left or right side of the frame.

Do not stop and create a new source group for every position. This whole uninterrupted sequence remains one source group.

Expected annotation later:

- `person` where valid;
- `phone` where visible enough for a defensible bounding box.

### Source Group B — Remote hard negative

Recommended ID:

```text
base-pilot-p001-remote-hand-001
```

Reset the scene and start a separate recording.

Scene:

- same or similar exam posture;
- hold a TV/other ordinary remote approximately where the phone was held;
- vary angle and partial finger occlusion naturally.

This is a new source group because it is an independently staged scenario.

Expected annotation later:

- `person` where valid;
- `remote` where visible enough;
- **no `phone` annotation**.

Why this matters:

The detector needs examples that teach:

```text
remote is remote
remote is not phone
```

That reduces a future false-positive failure mode.

### Source Group C — Empty-hand negative

Recommended ID:

```text
base-pilot-p001-empty-hand-001
```

Reset again and start a third recording.

Scene:

- similar participant/camera setup;
- no phone and no remote;
- naturally place or move the hand in positions similar to Source Groups A and B.

Expected annotation later:

- `person` where valid;
- no `phone` or `remote` annotation unless another real target object is actually visible.

Why this matters:

The model must learn that a hand pose alone is not evidence of a phone.

## 3. Why these must be three source groups

Source Group A, B and C are different staged scenarios, so they must not share one source-group identity.

Within Source Group A, however, every extracted image stays under:

```text
base-pilot-p001-phone-hand-001
```

Do not assign each frame a new source group.

The same rule applies to B and C.

This prevents future train/validation/test leakage.

## 4. Recording procedure

For each of the three source groups:

1. Place the camera in the intended exam-view position.
2. Confirm the scene is usable and the participant is visible.
3. Start one short recording.
4. Perform only the scripted scenario for that source group.
5. Make natural, slow changes in object angle/hand position.
6. Stop the recording.
7. Do not mix the next scenario into the same recording.
8. Record the exact source-group ID in the private capture log.
9. Preserve the original recording as provenance until the retained frames have been checked.

There is deliberately no scientific recording-duration requirement in this pilot.

The goal is to produce enough visual change to understand the workflow, not to maximize frame count.

## 5. Frame extraction rule

Do not save every video frame.

Choose a small set of visibly different, usable frames from each source group.

Prefer frames showing meaningful differences such as:

- object angle;
- object scale;
- partial finger occlusion;
- left/right position;
- hand pose;
- slight lighting/exposure changes naturally present in the recording.

Avoid retaining many nearly identical consecutive frames.

All frames extracted from one recording keep that recording's source-group ID.

## 6. File layout

Raw participant media should stay outside Git history.

A recommended private dataset workspace is:

```text
data/
  raw/
    e1/
      base/
        base-pilot-p001-phone-hand-001/
          frame-0001.jpg
          frame-0002.jpg
          ...
        base-pilot-p001-remote-hand-001/
          frame-0001.jpg
          frame-0002.jpg
          ...
        base-pilot-p001-empty-hand-001/
          frame-0001.jpg
          frame-0002.jpg
          ...
```

Canonical dataset-relative paths should later look like:

```text
images/base-pilot-p001-phone-hand-001/frame-0001.jpg
```

not a machine-specific path such as `C:\Users\...`.

## 7. What a bounding box means

A **bounding box** is the rectangle used to tell the detector where an object is in an image.

For a phone image, the box should surround the visible phone as consistently and tightly as the annotation policy requires.

Simple idea:

```text
image
+-------------------------------+
|                               |
|        person                 |
|            +------+           |
|            |phone |           |
|            +------+           |
|                               |
+-------------------------------+
```

The box does not mean misconduct.

It means only:

```text
an object labelled `phone` is visible here
```

Policy, temporal context and later Rust intelligence decide what that observation means in an examination context.

## 8. Annotation truth rules for this pilot

Use only canonical labels.

For Source Group A:

- annotate visible `phone` objects as `phone`;
- annotate valid people as `person`.

For Source Group B:

- annotate visible remote controls as `remote`;
- never label the remote `phone` just because it has a rectangular shape;
- annotate valid people as `person`.

For Source Group C:

- do not invent a phone box around a hand;
- annotate valid people as `person`;
- leave phone absent when no phone is visible.

If an object is too blurred, too occluded or genuinely ambiguous, preserve uncertainty and send the image to human review or exclude it from this learning pilot.

## 9. What we will do after capture

Once real frames exist, the next steps are:

```text
retained frames
    -> collection inventory
    -> source-group-safe split planning when scientifically appropriate
    -> bounding-box annotation
    -> canonical annotation ingest
    -> dataset readiness validation
    -> later YOLO training export
```

Because this first exercise contains only three source groups, it is a workflow-learning pilot. We must not pretend that it is a scientifically meaningful train/validation/test dataset.

## 10. Completion condition

This pilot is complete when we have:

- one real phone-positive recording/source group;
- one real remote hard-negative recording/source group;
- one real empty-hand negative recording/source group;
- a small set of retained frames from each;
- source-group IDs preserved correctly;
- no participant raw media committed to GitHub;
- enough real frames to begin our first annotation lesson.

At that point we move to the next learning step: **annotation and bounding boxes on the actual K-SLAS pilot images**.

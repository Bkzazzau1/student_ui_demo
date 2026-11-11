# E1 Dataset Acquisition Protocol

## Status

This document starts the real E1 data phase after the live E1 runtime architecture was frozen.

It is an operational collection procedure, not a live-exam runtime specification.

Hard rule: all production E1 inference remains local on the candidate device. External foundation models may help later with development-time annotation, consensus, review, distillation, validation, or training support, but they are never required during a live examination.

## 1. What we are collecting

E1 learns visual object observations from images.

For dataset purposes, one **sample** is one source image plus its provenance and, after annotation, zero or more object labels and bounding boxes.

A sample is not automatically a unique learning situation. Ten adjacent frames from the same short recording may look almost identical. Those frames can all be retained, but they belong to the same `source_group_id` and must never be split across train, validation, and test.

### Positive sample

A positive sample contains at least one target object for the model role being trained.

Examples for the base detector:

- candidate holding a phone;
- candidate seated with a laptop visible;
- a book on the desk;
- a remote control beside the keyboard;
- another person entering the frame.

The person example is positive for canonical `person`. `additional_person` is not annotated as a detector class; it is derived later from person observations and tracking/context.

### Negative sample

A negative sample contains no positive target object for the model role being trained.

Examples:

- ordinary candidate seated at a clean desk;
- empty desk with no E1 target object;
- hands visible with no phone;
- background patterns that do not contain a target object.

Negative samples teach the detector when **not** to fire.

### Hard negative

A hard negative is a negative example that visually resembles a target class and is therefore especially useful for reducing false positives.

Examples:

- jewelry bracelet, decorative bracelet, or plain non-device wristband when
  training `wrist_device` (an ordinary analogue/digital watch is now a
  **positive** `wrist_device` example, not a hard negative — see Section 8a);
- earring when training `earbud`;
- remote control when evaluating confusion with `phone`;
- hand-only poses that resemble phone holding;
- printed fabric/pattern when evaluating confusion with `paper_note`;
- ordinary non-relevant background rectangles/screens where policy/context should not be guessed.

Hard-negative tags are training/evaluation metadata only. They are not misconduct evidence.

## 2. Frozen class boundary

### Base detector classes

The base E1 detector may be trained only on:

- `person`
- `phone`
- `laptop`
- `television`
- `keyboard`
- `mouse`
- `remote`
- `book`

### Small-object specialist classes

The specialist may be trained only on:

- `wrist_device`
- `earbud`
- `tablet`
- `paper_note`
- `calculator`

### Derived-only signals

Do not annotate these as detector classes:

- `additional_person`
- `partial_person`
- `screen_signal`

Do not create a separate `monitor` detector class. Generic monitor/tv-monitor semantics must be resolved to canonical `television` before canonical annotation ingest.

Do not merge semantically different objects:

- `remote` is not `phone`;
- `book` is not `paper_note`;
- `remote` is not `calculator`.

If an image is ambiguous, preserve uncertainty and send it to human review. Do not promote the object into a prohibited class merely to increase dataset size.

## 3. Source group: the most important collection identity

A **source group** is the provenance boundary for near-related images.

Use one `source_group_id` for all images that came from the same tightly related capture situation, such as:

- one continuous video recording;
- one camera burst;
- one scripted scenario performed without resetting the scene;
- one participant/object/camera setup captured as a sequence;
- extracted frames from one source video.

Example:

```text
base-pilot-p001-phone-standing-001/frame-0001.jpg
base-pilot-p001-phone-standing-001/frame-0002.jpg
base-pilot-p001-phone-standing-001/frame-0003.jpg
```

All three records receive:

```text
source_group_id = base-pilot-p001-phone-standing-001
```

A new source group should be created when the capture situation is materially reset, for example:

- new participant;
- new room/environment;
- new camera/device;
- substantially new scripted scenario;
- independently staged object arrangement;
- separate recording separated in time and setup.

Do not create a new source group merely because the frame number changed.

The existing `e1_collection_split.py` tool keeps a complete source group inside one split. This is how K-SLAS prevents near-duplicate leakage.

## 4. Why data leakage is dangerous

Suppose a phone video produces 100 very similar frames.

If frame 1 goes to training and frame 2 goes to test, the model may appear excellent because the test image is almost the same scene it already saw during training.

That is **data leakage**.

The model may then fail badly on a genuinely new room, person, camera, or phone while the reported test score still looks impressive.

K-SLAS therefore splits at the source-group level, not at the individual-frame level.

## 5. Capture folder convention

Store raw collected images outside Git history. Do not commit participant image datasets into the application repository.

Recommended dataset-relative structure:

```text
data/
  raw/
    e1/
      base/
        base-pilot-p001-phone-standing-001/
          frame-0001.jpg
          frame-0002.jpg
        base-pilot-p002-clean-desk-001/
          frame-0001.jpg
      specialist/
        specialist-pilot-p003-watch-conventional-001/
          frame-0001.jpg
```

The application repository should contain tooling, contracts, and documentation. Raw training media should live in the controlled dataset workspace/storage selected for the training project.

Dataset inventory paths should be stable dataset-relative paths, for example:

```text
images/base-pilot-p001-phone-standing-001/frame-0001.jpg
```

Do not store machine-specific paths such as `C:\Users\...` inside canonical manifests.

## 6. Capture-session identifier convention

Use source-group IDs that are unique but do not expose participant names.

Recommended structure:

```text
<role>-<campaign>-<participant-code>-<scenario>-<sequence>
```

Examples:

```text
base-pilot-p001-phone-desk-001
base-pilot-p001-phone-hand-002
base-pilot-p002-clean-desk-001
base-pilot-p003-book-reading-001
specialist-pilot-p004-watch-conventional-001
specialist-pilot-p004-watch-smart-002
specialist-pilot-p004-bracelet-negative-003
```

Participant codes should be pseudonymous collection IDs, not names, matric numbers, email addresses, or phone numbers.

## 7. What must vary during collection

A robust detector must learn the object, not memorize one room or one camera.

Across independent source groups, deliberately vary:

- room/background;
- desk type and colour;
- camera model/webcam quality;
- camera height and angle;
- image resolution where the target deployment may vary;
- lighting level and direction;
- daylight versus artificial light;
- object colour/model/shape;
- object distance from camera;
- object scale in the frame;
- object orientation;
- partial occlusion;
- candidate posture;
- object in hand versus on desk;
- one object versus several objects;
- cluttered versus clean workspace.

Variation must remain realistic for K-SLAS examination conditions. Do not create only studio-perfect images.

## 8. Base-detector capture matrix

The first real base collection should cover each class in multiple independent source groups and multiple realistic visual conditions.

### `person`

Capture:

- one seated candidate;
- one standing candidate;
- second person entering from left/right/background;
- partially visible person at image edge;
- person at different distances;
- person under weaker and stronger lighting;
- person partly occluded by chair/desk where realistic.

Do not annotate `additional_person`; annotate every visible person as canonical `person` when annotation policy says the visible extent is sufficient for a valid bounding box.

### `phone`

Capture:

- phone flat on desk;
- phone in hand;
- phone partly hidden by hand;
- phone at left/right edges;
- phone face-up/face-down;
- multiple phone models, colours and cases;
- phone near visually confusing objects such as remote controls and calculators.

### `laptop`

Capture:

- laptop open and closed;
- different screen angles;
- partial laptop visibility;
- secondary laptop in background;
- laptop beside books/tablet-like objects.

### `television`

Capture realistic background televisions/monitors that should map to canonical `television` before ingest.

Vary:

- screen on/off;
- different sizes;
- wall-mounted/desk-mounted;
- partial screen visibility;
- glare/reflection.

### `keyboard`

Capture:

- separate desktop keyboards;
- different sizes/layouts;
- partial occlusion by hands;
- different viewing angles.

Do not annotate a laptop's integrated keyboard as a separate keyboard unless the final annotation policy explicitly establishes that boundary and applies it consistently. Ambiguous boundaries must be reviewed, not improvised per annotator.

### `mouse`

Capture:

- wired/wireless-looking shapes;
- different colours;
- hand covering part of mouse;
- mouse near remote controls and other small objects.

### `remote`

Capture:

- television remotes;
- different sizes/colours;
- remote held in hand;
- remote on desk beside phone and calculator-like objects.

This class is especially important for confusion testing because `remote` must never be silently promoted to `phone`.

### `book`

Capture:

- book open/closed;
- textbook/notebook-like hard-bound examples only where the annotation policy can distinguish them consistently;
- partial book visibility;
- book held/read;
- book mixed with permitted clean desk scenes.

Do not convert loose sheets into `book`. Loose paper belongs to the specialist `paper_note` class only when the specialist annotation policy supports it.

## 8a. Specialist wrist-device capture matrix

Taxonomy `1.1` replaced the specialist class `smartwatch` with `wrist_device`.
`wrist_device` means any visually identifiable wrist-worn timekeeping or
electronic wearable that exam policy prohibits — the annotator does not need
to judge whether a watch is "smart." A jewelry bracelet, decorative bracelet,
or plain non-device wristband is not `wrist_device` merely because it sits on
a wrist.

Cover at least these four controlled scenarios, each its own independent
source group:

### A. Conventional watch positive

An analogue or digital wristwatch, clearly visible on the wrist.

- canonical class: `wrist_device`

### B. Smart wearable positive

A smartwatch, fitness tracker, or smart band, clearly visible on the wrist.

- canonical class: `wrist_device`

### C. Wrist accessory hard negative

A bracelet, decorative wristband, or other jewelry item with no
timekeeping/electronic function.

- no `wrist_device` annotation is added;
- hard-negative tag: `bracelet_or_wristband`.

### D. Empty wrist negative

A comparable pose/framing with no wrist object present at all.

Keep each continuous video/burst/scripted scene inside one `source_group_id`,
exactly as with base-detector collection (Section 3). Do not invent sample
counts or train/validation/test ratios for this matrix; split weights remain
an explicit project decision (Section 13), not something this protocol
presumes. Raw participant media stays outside Git, same as every other
capture (Section 5).

If a wrist object is ambiguous, blurred, or occluded such that it cannot be
reliably distinguished between `wrist_device` and jewelry/accessory, treat it
as UNKNOWN, route it to human review, or exclude it from canonical
annotation. Do not guess.

## 9. Negative and hard-negative collection

Collect negative source groups intentionally, not as leftovers.

### Ordinary negatives

Examples:

- clean exam desk;
- candidate with empty hands;
- candidate typing normally;
- candidate adjusting posture;
- empty room/background;
- common stationery that is not part of the E1 taxonomy.

### Confusion-focused negatives

Examples to preserve as explicit negative scenarios:

- hand pose without phone;
- remote near phone-like orientation;
- calculator-like object when training/evaluating base phone/remote confusion;
- jewelry bracelet or decorative wristband for specialist `wrist_device`
  training (an ordinary analogue/digital watch is a positive `wrist_device`
  example, not a negative — see Section 8a);
- earrings for specialist earbud training;
- printed clothing/patterns for paper-note confusion;
- book pages versus loose paper-note boundary;
- background rectangular objects that are not televisions/screens.

The annotation result for a true negative sample may contain an empty `annotations` list plus appropriate `negative_tags`.

## 10. Capture procedure for one source group

For each new source group:

1. Assign a pseudonymous participant code when a participant is involved.
2. Choose exactly one scripted scenario description.
3. Record the camera/device used in the private collection log.
4. Record room/environment category in the private collection log.
5. Stage the target object(s) naturally.
6. Capture a short sequence or burst.
7. Keep the entire sequence under the same `source_group_id`.
8. Do not manually rename individual frames into new source groups.
9. Review the sequence for unusable files, accidental personal information, corruption, or collection mistakes.
10. Register retained images in the E1 collection inventory with their dataset-relative path, width, height, and the exact source-group ID.
11. Do not add bounding boxes during collection unless the same operator is deliberately performing the later annotation step.
12. Do not assign train/validation/test manually per frame. The existing source-group-safe splitter owns that step.

## 11. Frame selection from videos

Continuous video can generate enormous numbers of nearly identical frames.

Do not treat every frame as equally valuable.

When extracting frames:

- preserve the original video/session as the source-group boundary;
- sample frames that represent meaningful visual change;
- include difficult frames such as partial occlusion, small scale, side angle, motion blur where still interpretable;
- discard corrupt or unusable frames;
- avoid flooding the dataset with hundreds of nearly identical frames from one easy scene.

The goal is diversity of learning evidence, not the largest possible image count.

## 12. Class balance

**Class balance** means the dataset contains enough useful learning evidence across the target classes and important conditions instead of being dominated by one easy class or one repeated scene.

Do not balance only by raw image count.

Also inspect:

- annotation count per class;
- independent source-group count per class;
- object-size distribution;
- lighting/environment coverage;
- occlusion coverage;
- hard-negative coverage;
- participant/session diversity;
- camera/device diversity.

Example problem:

10,000 phone frames from one video are not better evidence than many independent phone source groups collected across different rooms, people, devices and viewing conditions.

Exact scientific collection targets are not frozen in this protocol. They must be chosen from the real pilot inventory and annotation audit rather than invented in advance.

## 13. Train / validation / test meaning

### Train

The model learns its weights from this data.

### Validation

Used during development to compare choices, diagnose overfitting, tune training configuration, and later support calibration decisions when the calibration design is explicitly defined.

### Test

Held back for final unbiased evaluation of a model/configuration that was not selected by looking at the test results.

The current repository requires explicit split weights and an explicit seed. The tooling intentionally does not invent a scientific ratio.

Whatever weights are selected, the invariant remains:

```text
one source_group_id -> one split only
```

## 14. Annotation happens after collection provenance is fixed

Collection establishes the image and its provenance.

Annotation later establishes what is visibly present.

For each visible trainable object, annotation must use:

- canonical class ID;
- valid bounding box;
- original full-image geometry;
- no guessed aliases;
- no fabricated labels.

A **bounding box** is a rectangle that tells the detector where the object is inside the image.

Conceptually:

```text
image
+----------------------------------+
|                                  |
|          +-----------+           |
|          |   phone   |           |
|          +-----------+           |
|                                  |
+----------------------------------+
```

The current ingest tool accepts pixel boxes or normalized boxes and converts them into the frozen canonical full-image representation.

## 15. Pilot execution order

Use this sequence for the first real collection campaign:

```text
A. Base-detector real captures
    -> independent source groups
    -> ordinary negatives
    -> confusion-focused negatives

B. Build collection inventory
    -> exact source_group_id
    -> stable image_path
    -> width + height

C. Freeze one split plan
    -> explicit project-selected split weights
    -> explicit seed
    -> whole source groups only

D. Annotate each assigned split
    -> canonical classes
    -> full-image bounding boxes
    -> hard-negative tags where appropriate

E. Run canonical ingest + readiness gates

F. Audit class/source-group/condition coverage

G. Only then start the first base-model training experiment
```

Do not begin specialist model training merely because specialist runtime infrastructure exists. Specialist collection/training should begin as its own model-role dataset, and the production specialist slot must remain unavailable until a validated local specialist model exists.

## 16. First physical collection session

The first physical session should be a **pilot**, not a production dataset claim.

Its purpose is to prove the end-to-end data workflow with real images:

```text
capture
-> source-group assignment
-> collection inventory
-> source-group-safe split plan
-> annotation
-> canonical ingest
-> dataset readiness validation
-> YOLO training export
```

The pilot should deliberately include:

- at least one real positive scenario for each base class that can be staged correctly;
- clean negative scenes;
- several confusion/hard-negative scenarios;
- more than one independent source group;
- more than one realistic room/camera/lighting condition where available.

This is a workflow-coverage requirement, not a scientific minimum sample count and not an acceptance threshold.

After the pilot passes the tooling end to end, inspect its class/source-group distribution before deciding how to scale the full collection.

## 17. Quality rejection rules during collection

Reject or quarantine a source image when:

- file is corrupt or unreadable;
- declared image dimensions do not match the source image;
- the relevant scene is unusably blurred or dark;
- provenance/source group cannot be established reliably;
- the image was accidentally placed under the wrong source group;
- the image contains unresolved collection/privacy material that should not enter the training workspace;
- the scenario label or object identity is uncertain and requires review.

Do not repair uncertainty by guessing.

## 18. What must never happen

- Do not split frames from one video across train/validation/test.
- Do not use participant names as source-group IDs.
- Do not call derived signals detector classes.
- Do not map ambiguous objects into prohibited classes to increase counts.
- Do not claim the specialist can detect specialist classes before a validated specialist model exists.
- Do not copy example metrics or example split weights and present them as scientific decisions.
- Do not treat detector confidence as calibrated probability.
- Do not use live cloud/foundation-model inference during examinations.
- Do not describe a model or dataset as production-calibrated before held-out evaluation, calibration, device benchmarking, and offline acceptance are complete.

## 19. Operator checklist

Before capture:

- [ ] collection campaign ID chosen;
- [ ] participant/source codes assigned without personal names;
- [ ] model role confirmed (`base` or `specialist`);
- [ ] scripted scenario selected;
- [ ] new `source_group_id` assigned;
- [ ] camera and room condition recorded privately;
- [ ] target object identity is unambiguous.

During capture:

- [ ] realistic object placement;
- [ ] useful variation in distance/orientation/occlusion;
- [ ] same recording/burst remains under one source group;
- [ ] no train/validation/test decision made per frame.

After capture:

- [ ] corrupt/unusable files removed or quarantined;
- [ ] retained paths are stable and dataset-relative;
- [ ] image dimensions recorded accurately;
- [ ] collection inventory updated;
- [ ] source group reviewed for consistency;
- [ ] later annotation required before any training claim.

## 20. What you should understand after this stage

You should now be able to explain:

- a sample is one image plus provenance and later annotation;
- positive means a target object is present;
- negative means no target object for that model role is present;
- a hard negative is a confusing negative used to reduce false positives;
- a bounding box tells the detector where an object is;
- a source group keeps related frames together;
- class balance is broader than raw image count;
- train data teaches the model;
- validation data guides development;
- test data measures final generalization;
- leakage makes weak models look stronger than they really are;
- K-SLAS prevents leakage by splitting complete source groups, not individual frames.

## 21. Next engineering action

After this protocol is merged, the next action is not another architecture document.

Create the first real base-detector pilot capture in the controlled dataset workspace, register those images in a real collection inventory, and run:

```powershell
python -m ai_runtime.e1_collection_split --pretty <real-inventory.json> <real-split-plan.json>
```

Then begin real annotation using the frozen canonical taxonomy.

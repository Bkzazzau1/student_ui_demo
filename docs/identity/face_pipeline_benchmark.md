# Face pipeline benchmark (engineering)

What the face identity pipeline could and could not do before and after the
`sface-5pt-ls-bilinear-rgb255-v2` fixes. This is an engineering check on a
public benchmark. It is **not** the calibration of the exam threshold, which
must come from the volunteer study (`volunteer_calibration_protocol.md`).

## Setup

- **Data:** the 6,000 LFW verification pairs (3,000 same person, 3,000
  different people). LFW is used only as an evaluation benchmark. Nothing was
  trained on it, and no LFW data is stored in this repository.
- **Settings:**
  - `lfw_original`: the 250×250 LFW photos.
  - `webcam_eye65` and `webcam_eye45`: each photo is placed in a 640×480
    laptop-webcam-sized frame, with the eyes about 65 or 45 pixels apart,
    over a blurred background.
  - At 45 px the face is close to the smallest the app accepts (eyes about
    38 px apart in a 640-wide frame).
- **Score:** cosine similarity between the two photos' embeddings (one photo
  against one photo). The app scores a live photo against seven approved
  references, using the mean of the two best, and then needs two of three
  photos to agree. Both make the app's real error rates lower than these
  single-photo numbers.
- **Pipelines:**
  - **current app:** the pipeline before this change, replicated exactly.
    The face mesh runs on the whole frame, alignment uses two eye points
    with nearest-neighbour sampling, and SFace gets BGR pre-normalized
    `(v - 127.5) / 128`.
  - **v2:** this change (`ai_runtime/face_identity_reference.py`). YuNet
    finds the face, the mesh runs on a 1.5× crop, five-point least-squares
    alignment uses bilinear sampling, and SFace gets raw RGB 0..255.
  - **OpenCV reference:** OpenCV's own SFace pipeline (`FaceDetectorYN` with
    `FaceRecognizerSF.alignCrop`), the model authors' intended use.

## Results

Accuracy is the best single-threshold accuracy. TAR@FAR is the share of
same-person pairs accepted when one in 1,000 different-person pairs is
accepted.

| Setting | Pipeline | Accuracy | TAR @ FAR 0.1% | Threshold @ FAR 0.1% | FAR @ 0.55 | FRR @ 0.40 | FAR @ 0.40 | No face / failed |
|---|---|---|---|---|---|---|---|---|
| LFW photos | current app | 0.589 | 0.022 | 0.988 | **99.97%** | 0.0% | 100% | 0 |
| | **v2** | **0.992** | **0.984** | 0.365 | 0% | 2.1% | 0% | 83 pairs |
| | OpenCV reference | 0.990 | 0.976 | 0.359 | 0% | 3.2% | 0.03% | 0 |
| Webcam, eyes 65 px | current app | 0.560 | 0.005 | 0.985 | **98.9%** | 0.1% | 99.8% | 0 |
| | **v2** | **0.991** | **0.982** | 0.360 | 0% | 2.4% | 0% | 155 pairs |
| | OpenCV reference | 0.982 | 0.965 | 0.348 | 0% | 4.5% | 0.03% | 0 |
| Webcam, eyes 45 px | current app | 0.553 | 0.009 | 0.984 | **97.0%** | 0.4% | 99.1% | 0 |
| | **v2** | **0.990** | **0.981** | 0.364 | 0% | 2.5% | 0% | 166 pairs |
| | OpenCV reference | 0.977 | 0.952 | 0.358 | 0% | 5.5% | 0% | 0 |

## What it shows

- **The previous pipeline could not tell people apart.** Same-person pairs
  averaged 0.93 and different-person pairs 0.92. At the app's 0.55
  threshold, 97–100% of different-person pairs were accepted.
  - The main cause was normalizing the SFace input twice: the model
    normalizes internally, so the app squeezed the input range 128 times.
  - On Windows, running the face mesh on the whole frame made it worse.
- **v2 matches or beats OpenCV's reference pipeline** in every setting.
  - v2 declines some photos: 1.4–2.8% of pairs had a photo with no detected
    face or a low face-presence score.
  - In the app those photos become "try again", never a decision.
  - Excluding them helps v2's accuracy slightly compared with the
    reference.
- **Provisional threshold 0.40.**
  - The single-photo threshold for one false accept in 1,000 was at most
    0.365.
  - At 0.40, v2 accepted none of the 9,000 different-person pairs (95% upper
    bound about 0.03%) and rejected 2.1–2.5% of same-person single photos.
  - LFW's different people are random public figures. Classmates can look
    more alike, so the volunteer study must confirm or replace 0.40.

## Parity checks behind these numbers

- **YuNet decoding:** the numpy decoder matched OpenCV's `FaceDetectorYN`
  on 150 frames, within 0.02 px for boxes and keypoints.
- **Windows landmarker:** the native landmarker (`landmark_harness` over the
  real `face_landmarker_runtime_channel.cpp`) matched the Python reference
  exactly on 40 frames, with a maximum point difference of 0.0000 px.
- **Alignment:** Dart (`FaceAlignment`) and Python share a golden fixture,
  `ai_runtime/tests/fixtures/face_alignment_golden.json`.

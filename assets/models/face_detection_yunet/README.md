# YuNet face detector

`face_detection_yunet_2023mar.onnx` is OpenCV Zoo's YuNet face detector.

- Source: https://github.com/opencv/opencv_zoo/tree/main/models/face_detection_yunet
- License: MIT (copied in `LICENSE`)
- SHA-256: `8f2383e4dd3cfbb4553ea8718107fc0423210dc964f9f4280604804ed2552fa4`
- Input: float32 BGR, NCHW, `[1, 3, 640, 640]`, raw values 0..255. The frame
  is shrunk (never enlarged) to fit 640 and padded black at the bottom and
  right.
- Outputs: `cls_*`, `obj_*`, `bbox_*`, `kps_*` for strides 8, 16 and 32,
  decoded as in OpenCV's `FaceDetectorYN`. The score threshold is 0.6 and NMS
  IoU is 0.3.

## Why it is here

The Windows face mesh model expects a face-centred crop. The Windows
landmarker (`windows/runner/face_landmarker_runtime_channel.cpp`) runs YuNet
first and gives the mesh a square crop 1.5 times the largest face box.
Without it, small laptop-webcam faces produced unusable landmarks; see
`docs/identity/face_pipeline_benchmark.md`.

Android does not need it: MediaPipe Tasks runs its own face detector. The
reference implementation is `ai_runtime/face_identity_reference.py`. It
matches the native decoder exactly in `landmark_harness` parity runs.

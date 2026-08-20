# Windows face and iris landmark model

`face_landmarks.onnx` is the 478-point MediaPipe Face Mesh V2 conversion
distributed by `react-native-liveness-kit` 0.1.0.

- Source package: https://www.npmjs.com/package/react-native-liveness-kit/v/0.1.0
- Upstream source: Google MediaPipe `face_landmarker.task`
- Package license: MIT (copied in `THIRD_PARTY_LICENSE.txt`)
- Model family license: Apache-2.0
- Input: float32 RGB NHWC `[1, 256, 256, 3]`, normalized to `[0, 1]`
- Landmark output: 478 xyz points (1,434 float values)
- SHA-256: `404c737f67469726a4b9cddcd5a3f2d05aab65c73e63496c823f53c60de8e269`

The Windows runner executes this model locally with ONNX Runtime. Camera
frames are not sent to Python or any network service.

# Local Hand Landmark Model

This folder is reserved for the local 21-point hand landmark model used by the K-SLAS Air Board.

Expected files:

- `hand_landmark.onnx`
- `manifest.json`

The model receives an RGB crop containing one detected hand and returns at least 21 landmarks in MediaPipe-compatible order:

0. wrist
1-4. thumb
5-8. index finger
9-12. middle finger
13-16. ring finger
17-20. little finger

Supported manifest fields:

- `modelName`
- `inputWidth`
- `inputHeight`
- `inputChannels`
- `landmarkCount`
- `outputLayout`: `flat_xyz` or `flat_xyzc`
- `coordinateMode`: `normalized` or `pixels`
- `confidenceIndex`: optional global confidence output index

The Rust runtime loads the ONNX model locally, resizes the RGB hand crop, decodes the landmark output, and sends the 21 points directly into `analyze_hand_landmarks`.

Gesture mapping:

- Open palm: Air Board ready
- Index finger only: write
- Index and middle fingers: erase
- Closed hand: pause

Installed model:

- Source: `PINTO0309/hand_landmark` release `1.0.0`
- File: `hand_landmark_sparse_Nx3x224x224.onnx`
- URL: `https://github.com/PINTO0309/hand_landmark/releases/tag/1.0.0`
- Local path: `assets/models/hand_landmark/hand_landmark.onnx`
- Input: `N x 3 x 224 x 224`
- Primary output: `xyz_x21`, shape `N x 63`
- Additional outputs: `hand_score`, `lefthand_0_or_righthand_1`

The current Rust runtime reads the first output as a flattened 21-point xyz tensor.

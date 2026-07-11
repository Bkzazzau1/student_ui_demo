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

Do not add a model until its source, licence, input tensor, output tensor, coordinate convention, and redistribution terms are documented.

# Hand Vision Model

`hand_detector.onnx` is exported from `Bingsu/adetailer` `hand_yolov8n.pt`.

The exported model is a YOLOv8 detector with:

- input: `1 x 3 x 320 x 320`
- output: `1 x 5 x 2100`
- classes: `hand`

It detects generic hands. It does not classify left hand versus right hand.

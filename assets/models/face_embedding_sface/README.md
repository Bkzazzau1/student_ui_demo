# SFace embedding model

This folder pins OpenCV Zoo's `face_recognition_sface_2021dec.onnx` for local
1:1 face-verification development. The accompanying `LICENSE` is the upstream
Apache-2.0 license. The exact binary digest is recorded in `manifest.json`.

The runtime accepts only a landmark-aligned 112x112 RGB face (five-point
least-squares similarity to the ArcFace template, bilinear sampling; see
`lib/face_demo/face_alignment.dart`). The tensor carries the raw RGB values
0..255: the graph normalizes internally (`scalar_op1` = 127.5 is subtracted
and the result multiplied by `scalar_op2` = 0.0078125), so normalizing again
outside the model would squeeze the input range 128 times. Embeddings are
L2-normalized before leaving the native runtime. The reference
implementation is `ai_runtime/face_identity_reference.py`.

This model is provisional: `production_enforcement` remains false until the
institution accepts model provenance, validates thresholds on held-out data,
and completes privacy, bias, and presentation-attack reviews. A mismatch is a
request for another sample or human review, never an automatic misconduct
finding.

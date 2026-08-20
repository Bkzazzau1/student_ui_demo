# SFace embedding model

This folder pins OpenCV Zoo's `face_recognition_sface_2021dec.onnx` for local
1:1 face-verification development. The accompanying `LICENSE` is the upstream
Apache-2.0 license. The exact binary digest is recorded in `manifest.json`.

The runtime accepts only a landmark-aligned 112x112 RGB face. It converts RGB
to the model's BGR tensor and applies `(value - 127.5) / 128.0`. Embeddings are
L2-normalized before leaving the native runtime.

This model is provisional: `production_enforcement` remains false until the
institution accepts model provenance, validates thresholds on held-out data,
and completes privacy, bias, and presentation-attack reviews. A mismatch is a
request for another sample or human review, never an automatic misconduct
finding.

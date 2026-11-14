"""Builds the fixture for ``integration_test/native_runtime_parity_test.dart``.

The integration test runs the app's native runtimes on a device or simulator
(it is how the iOS Swift code is checked in CI without a Mac) and compares
them with this reference, computed with ONNX Runtime on the CPU:

* SFace embedding of one aligned 112x112 face (must match almost exactly);
* the five alignment points from ``face_identity_reference`` (YuNet + face
  mesh, as on Windows); the iOS/Android MediaPipe landmarker must agree
  within a tolerance;
* the full-pipeline embedding of the test image;
* the best "person" box from the exam YOLO model on the same frame.

Test image: NASA portrait of astronaut Eileen Collins (public domain; the
``astronaut`` image in scikit-image), cropped to 384x384 at full resolution.

Usage::

    python ai_runtime/tools/build_native_parity_fixture.py path/to/astronaut.png
"""

from __future__ import annotations

import base64
import io
import json
import sys
from pathlib import Path

import numpy as np

REPO = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO / "ai_runtime"))

from face_identity_reference import (  # noqa: E402
    FaceIdentityReference,
    align_face,
    five_points,
)

CROP_BOX = (64, 0, 448, 384)  # left, top, right, bottom in the 512x512 source
YOLO_MODEL = REPO / "assets/models/yolo_exam_review/yolo_exam_review.int8.onnx"
YOLO_MANIFEST = REPO / "assets/models/yolo_exam_review/manifest.json"
OUTPUT = REPO / "integration_test/fixtures/native_parity_fixture.dart"


def letterbox_rgb01(rgb: np.ndarray, side_w: int, side_h: int):
    """Same placement and nearest sampling as the Android/iOS YOLO engines."""
    height, width = rgb.shape[:2]
    ratio = min(side_w / width, side_h / height)
    content_w = min(max(int(np.floor(width * ratio + 0.5)), 1), side_w)
    content_h = min(max(int(np.floor(height * ratio + 0.5)), 1), side_h)
    pad_x = (side_w - content_w) // 2
    pad_y = (side_h - content_h) // 2
    tensor = np.full((3, side_h, side_w), 114.0 / 255.0, dtype=np.float32)
    for y in range(side_h):
        cy = y - pad_y
        if cy < 0 or cy >= content_h:
            continue
        sy = min(height - 1, cy * height // content_h)
        for x in range(side_w):
            cx = x - pad_x
            if cx < 0 or cx >= content_w:
                continue
            sx = min(width - 1, cx * width // content_w)
            tensor[:, y, x] = rgb[sy, sx, :3].astype(np.float32) / 255.0
    return tensor[None], (content_w, content_h, pad_x, pad_y)


def best_person(rgb: np.ndarray) -> dict:
    import onnxruntime as ort

    manifest = json.loads(YOLO_MANIFEST.read_text(encoding="utf-8"))
    classes = manifest["class_names"]
    side_w, side_h = manifest["input_width"], manifest["input_height"]
    options = ort.SessionOptions()
    options.log_severity_level = 3
    session = ort.InferenceSession(str(YOLO_MODEL), options, providers=["CPUExecutionProvider"])
    tensor, (cw, ch, px, py) = letterbox_rgb01(rgb, side_w, side_h)
    output = session.run(None, {session.get_inputs()[0].name: tensor})[0]
    assert output.shape[1] == 4 + len(classes), output.shape
    predictions = output[0].T  # [N, 4 + C], channels_first_yolov8
    scores = predictions[:, 4:]
    best = None
    for row, cls_scores in zip(predictions, scores):
        cls = int(np.argmax(cls_scores))
        score = float(cls_scores[cls])
        if classes[cls] != "person" or score < manifest["confidence_threshold"]:
            continue
        if best is None or score > best["confidence"]:
            cx, cy, w, h = (float(v) for v in row[:4])
            best = {
                "confidence": score,
                "x1": min(1.0, max(0.0, (cx - w / 2 - px) / cw)),
                "y1": min(1.0, max(0.0, (cy - h / 2 - py) / ch)),
                "x2": min(1.0, max(0.0, (cx + w / 2 - px) / cw)),
                "y2": min(1.0, max(0.0, (cy + h / 2 - py) / ch)),
            }
    if best is None:
        raise SystemExit("YOLO found no person in the fixture image")
    return best


def dart_doubles(values) -> str:
    return "[" + ", ".join(f"{float(v):.8f}" for v in values) + "]"


def main() -> None:
    from PIL import Image

    source = Image.open(sys.argv[1]).convert("RGB")
    if source.size != (512, 512):
        raise SystemExit(f"expected the 512x512 astronaut image, got {source.size}")
    image = source.crop(CROP_BOX)
    png = io.BytesIO()
    image.save(png, format="PNG", optimize=True)
    rgb = np.asarray(image, dtype=np.uint8)

    reference = FaceIdentityReference.from_repo(REPO)
    points = reference.landmarks(rgb)
    if points is None:
        raise SystemExit("reference found no face")
    five = five_points(points)
    aligned = align_face(rgb, points)
    if aligned is None:
        raise SystemExit("alignment failed")
    aligned_embedding = reference.embed_aligned(aligned)
    image_embedding = reference.embed_image(rgb)
    person = best_person(rgb)

    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_text(
        "// GENERATED by ai_runtime/tools/build_native_parity_fixture.py. Do not edit.\n"
        "//\n"
        "// Test image: NASA portrait of astronaut Eileen Collins (public domain),\n"
        f"// cropped to {image.width}x{image.height}. Reference values come from ONNX\n"
        "// Runtime (CPU) via ai_runtime/face_identity_reference.py.\n"
        "\n"
        "// ignore_for_file: lines_longer_than_80_chars\n"
        "\n"
        "abstract final class NativeParityFixture {\n"
        f"  static const int imageWidth = {image.width};\n"
        f"  static const int imageHeight = {image.height};\n"
        f"  static const String imagePngBase64 = '{base64.b64encode(png.getvalue()).decode()}';\n"
        "\n"
        "  /// Aligned 112x112 RGB face (from the reference landmarks).\n"
        f"  static const String alignedRgbBase64 = '{base64.b64encode(aligned.astype(np.uint8).tobytes()).decode()}';\n"
        f"  static const List<double> alignedEmbedding = {dart_doubles(aligned_embedding)};\n"
        "\n"
        "  /// Full pipeline (YuNet + face mesh landmarks) on the test image.\n"
        f"  static const List<double> imageEmbedding = {dart_doubles(image_embedding)};\n"
        "\n"
        "  /// Pixel positions: eye centres (image left, image right), nose tip,\n"
        "  /// mouth corners.\n"
        f"  static const List<double> fivePointsXY = {dart_doubles(five.reshape(-1))};\n"
        "\n"
        "  /// Best YOLO person box, normalized to the image.\n"
        f"  static const double personConfidence = {person['confidence']:.6f};\n"
        f"  static const List<double> personBox = {dart_doubles([person['x1'], person['y1'], person['x2'], person['y2']])};\n"
        "}\n",
        encoding="utf-8",
        newline="\n",
    )
    print(f"wrote {OUTPUT.relative_to(REPO)} ({OUTPUT.stat().st_size} bytes)")
    print("five points:", np.round(five, 2).tolist())
    print("person:", {k: round(v, 4) for k, v in person.items()})
    print("aligned vs image embedding cosine:", float(aligned_embedding @ image_embedding))


if __name__ == "__main__":
    main()

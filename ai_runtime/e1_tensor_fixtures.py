"""Build auditable experimental full-image tensors from real local images.

Two explicit transforms, both RGB/255 NCHW with nearest floor-coordinate
sampling:

- ``stretch_nn_rgb01``: the whole frame is stretched onto the square input.
- ``letterbox_nn_rgb01``: aspect-preserving letterbox with grey (114) padding,
  the same placement and sampling as the Windows/Android native runtimes
  (``input_preprocessing: letterbox_rgb01``). Per-sample content size and
  padding are recorded as ``input_geometry`` so predictions can be mapped back
  to source-frame coordinates.
"""

import math
from pathlib import Path

from .e1_ml_common import integer, load, sha256
from .e1_evaluation import fingerprint
from .e1_training_readiness import validate_dataset_manifest

PREPROCESSING = ("stretch_nn_rgb01", "letterbox_nn_rgb01")


def letterbox_geometry(width, height, size):
    """Content size and padding of a ``width`` x ``height`` frame in a square input.

    Mirrors ``OptimizedVisionRuntimeEngine::ComputeInputGeometry`` (C++) and
    ``computeInputGeometry`` (Kotlin): scale by the limiting axis, round the
    content size half-up, split padding floor-left/top.
    """
    ratio = min(size / width, size / height)
    content_width = max(1, min(size, int(math.floor(width * ratio + 0.5))))
    content_height = max(1, min(size, int(math.floor(height * ratio + 0.5))))
    return content_width, content_height, (size - content_width) // 2, (size - content_height) // 2


def build_tensor(rgb, size, preprocessing):
    """Return (CHW float32 tensor, (content_w, content_h, pad_x, pad_y))."""
    import numpy as np
    if preprocessing not in PREPROCESSING:
        raise ValueError(f"preprocessing must be one of {PREPROCESSING}")
    height, width = rgb.shape[:2]
    if preprocessing == "stretch_nn_rgb01":
        content_width, content_height, pad_x, pad_y = size, size, 0, 0
    else:
        content_width, content_height, pad_x, pad_y = letterbox_geometry(width, height, size)
    ys = np.arange(content_height) * height // content_height
    xs = np.arange(content_width) * width // content_width
    tensor = np.full((size, size, 3), np.float32(114) / np.float32(255), dtype=np.float32)
    tensor[pad_y:pad_y + content_height, pad_x:pad_x + content_width] = (
        rgb[ys[:, None], xs[None, :]].astype(np.float32) / np.float32(255))
    return tensor.transpose(2, 0, 1), (content_width, content_height, pad_x, pad_y)


def prepare(manifest_path, size, output, preprocessing="stretch_nn_rgb01"):
    import numpy as np
    from PIL import Image
    integer(size, "size")
    if preprocessing not in PREPROCESSING:
        raise ValueError(f"preprocessing must be one of {PREPROCESSING}")
    manifest_path, output = Path(manifest_path), Path(output)
    manifest = load(manifest_path)
    if validate_dataset_manifest(manifest) or manifest.get("example_only"):
        raise ValueError("Real valid manifest required")
    if output.exists():
        raise ValueError("Tensor output exists")
    inputs, ids, image_hashes, geometries = [], [], [], []
    for sample in manifest["samples"]:
        source = Path(sample["image_path"])
        if not source.is_absolute():
            source = manifest_path.parent / source
        with Image.open(source) as image:
            if image.size != (sample["width"], sample["height"]):
                raise ValueError("Decoded image dimensions differ from annotations")
            rgb = np.asarray(image.convert("RGB"))
        tensor, geometry = build_tensor(rgb, size, preprocessing)
        inputs.append(tensor)
        geometries.append(geometry)
        ids.append(sample["sample_id"])
        image_hashes.append(sha256(source))
    arrays = dict(inputs=np.stack(inputs), sample_ids=np.array(ids),
                  rois=np.tile(np.array([0., 0., 1., 1.]), (len(ids), 1)),
                  image_sha256=np.array(image_hashes), manifest_sha256=np.array(fingerprint(manifest)),
                  split=np.array(manifest["split"]), preprocessing=np.array(preprocessing))
    if preprocessing == "letterbox_nn_rgb01":
        arrays["input_geometry"] = np.array(geometries, dtype=np.float64)
    output.parent.mkdir(parents=True, exist_ok=True)
    with output.open("xb") as handle:
        np.savez_compressed(handle, **arrays)
    return {"fixture_sha256": sha256(output), "manifest_sha256": fingerprint(manifest),
            "samples": len(ids), "preprocessing": preprocessing,
            "native_preprocessing_parity": "pending", "production_accepted": False}


def to_source_frame(raw, geometry, input_width, input_height):
    """Rescale raw YOLOv8 box channels so the letterbox content spans the input.

    ``raw`` is ``[1, 4 + C, N]`` in input pixels and ``geometry`` is
    ``(content_w, content_h, pad_x, pad_y)``. Decoding the result with the
    input size yields normalized *source-frame* coordinates, and the decoder's
    clipping then clips to the source frame rather than the padded input.
    """
    import numpy as np
    content_width, content_height, pad_x, pad_y = (float(v) for v in geometry)
    mapped = np.array(raw, dtype=np.float64, copy=True)
    sx, sy = input_width / content_width, input_height / content_height
    mapped[0, 0] = (mapped[0, 0] - pad_x) * sx
    mapped[0, 1] = (mapped[0, 1] - pad_y) * sy
    mapped[0, 2] = mapped[0, 2] * sx
    mapped[0, 3] = mapped[0, 3] * sy
    return mapped

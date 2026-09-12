"""Build auditable experimental full-image tensors from real local images.

The transform is explicit: nearest floor-coordinate stretching, RGB/255, NCHW.
It is not a claim that every native runtime path uses this normalization.
"""

from pathlib import Path

from .e1_ml_common import integer, load, sha256
from .e1_evaluation import fingerprint
from .e1_training_readiness import validate_dataset_manifest


def prepare(manifest_path, size, output):
    import numpy as np
    from PIL import Image
    integer(size, "size")
    manifest_path, output = Path(manifest_path), Path(output)
    manifest = load(manifest_path)
    if validate_dataset_manifest(manifest) or manifest.get("example_only"):
        raise ValueError("Real valid manifest required")
    if output.exists():
        raise ValueError("Tensor output exists")
    inputs, ids, image_hashes = [], [], []
    for sample in manifest["samples"]:
        source = Path(sample["image_path"])
        if not source.is_absolute():
            source = manifest_path.parent / source
        with Image.open(source) as image:
            if image.size != (sample["width"], sample["height"]):
                raise ValueError("Decoded image dimensions differ from annotations")
            rgb = np.asarray(image.convert("RGB"))
        height, width = rgb.shape[:2]
        ys, xs = np.arange(size)*height//size, np.arange(size)*width//size
        tensor = rgb[ys[:, None], xs[None, :]].astype(np.float32) / np.float32(255)
        inputs.append(tensor.transpose(2, 0, 1))
        ids.append(sample["sample_id"])
        image_hashes.append(sha256(source))
    output.parent.mkdir(parents=True, exist_ok=True)
    with output.open("xb") as handle:
        np.savez_compressed(handle, inputs=np.stack(inputs), sample_ids=np.array(ids),
            rois=np.tile(np.array([0., 0., 1., 1.]), (len(ids), 1)),
            image_sha256=np.array(image_hashes), manifest_sha256=np.array(fingerprint(manifest)),
            split=np.array(manifest["split"]), preprocessing=np.array("stretch_nn_rgb01"))
    return {"fixture_sha256": sha256(output), "manifest_sha256": fingerprint(manifest),
            "samples": len(ids), "preprocessing": "stretch_nn_rgb01",
            "native_preprocessing_parity": "pending", "production_accepted": False}

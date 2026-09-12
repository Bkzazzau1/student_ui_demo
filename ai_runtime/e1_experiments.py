"""Opt-in local training/export/ORT experiments, never live runtime code.

Heavy frameworks are imported only by commands that need them. Callers provide
local checkpoints and measured operating points; no model is downloaded here.
"""

import importlib.metadata
import os
from pathlib import Path
import platform
import time

from .e1_ml_common import integer, load, number, required, save, sha256
from .e1_training_export import class_order_for_role
from .e1_evaluation import fingerprint, iou


def local_file(root, relative):
    root = Path(root).resolve()
    path = (root / relative).resolve()
    if not path.is_relative_to(root) or not path.is_file():
        raise ValueError(f"Missing/outside package file: {relative}")
    return path


def inspect_package(root):
    root = Path(root).resolve()
    manifest = load(root / "export_manifest.json")
    classes = class_order_for_role(manifest.get("model_role", ""))
    if not classes or manifest.get("class_map") != [
            {"index": i, "canonical_object_id": c} for i, c in enumerate(classes)]:
        raise ValueError("Package class map mismatch")
    groups, hashes, sample_keys, ledger = {}, {}, set(), []
    coverage = {s: set() for s in ("train", "validation", "test")}
    samples = manifest.get("samples", [])
    if not samples:
        raise ValueError("Empty training package")
    for sample in samples:
        split = sample["split"]
        if split not in coverage:
            raise ValueError("Invalid split")
        key = sample["sample_id"].casefold()
        if key in sample_keys:
            raise ValueError("Duplicate sample ID across package")
        sample_keys.add(key)
        image = local_file(root, sample["export_image_path"])
        label = local_file(root, sample["export_label_path"])
        if image.parent != root / "images" / split or label.parent != root / "labels" / split:
            raise ValueError("Image/label split path mismatch")
        if image.stem != label.stem or image.stem != sample["sample_id"]:
            raise ValueError("Image/label sample ID mismatch")
        digest = sha256(image)
        if digest != sample["source_image_sha256"]:
            raise ValueError("Package image changed since export")
        group = required(sample.get("source_group_id"), "source_group_id").casefold()
        for mapping, identity in ((groups, group), (hashes, digest)):
            if identity in mapping and mapping[identity] != split:
                raise ValueError("Source group or identical image leaks across splits")
            mapping[identity] = split
        lines = label.read_text(encoding="utf-8").splitlines()
        if len(lines) != sample["annotation_count"]:
            raise ValueError("Annotation count mismatch")
        for line in lines:
            fields = line.split()
            if len(fields) != 5:
                raise ValueError("Invalid YOLO label")
            index = int(fields[0])
            if not 0 <= index < len(classes):
                raise ValueError("Invalid label class index")
            cx, cy, w, h = [number(float(x), "YOLO box") for x in fields[1:]]
            if min(w, h) <= 0 or min(cx-w/2, cy-h/2) < -1e-9 or max(cx+w/2, cy+h/2) > 1+1e-9:
                raise ValueError("Invalid YOLO geometry")
            coverage[split].add(index)
        ledger.append({"image": sample["export_image_path"], "image_sha256": digest,
                       "label": sample["export_label_path"], "label_sha256": sha256(label)})
    for split in ("train", "validation"):
        if coverage[split] != set(range(len(classes))):
            raise ValueError(f"Every class needs real {split} support")
    # Reject unlisted files that a framework's directory scan could consume.
    expected = {str(local_file(root, s[k])) for s in samples
                for k in ("export_image_path", "export_label_path")}
    actual = {str(p.resolve()) for folder in ("images", "labels")
              for p in (root / folder).rglob("*") if p.is_file()}
    if actual != expected:
        raise ValueError("Unlisted files in training package")
    return manifest, ledger


def _yolo(checkpoint):
    checkpoint = Path(checkpoint).resolve()
    if not checkpoint.is_file():
        raise ValueError("Provide a local architecture YAML or checkpoint; no automatic download")
    os.environ["YOLO_OFFLINE"] = "true"
    from ultralytics import YOLO, settings
    settings.update({"sync": False, "wandb": False, "comet": False, "clearml": False})
    return YOLO(str(checkpoint), task="detect")


def check_names(model, role):
    names = model.names
    ordered = [names[i] for i in range(len(names))] if isinstance(names, dict) else list(names)
    if ordered != list(class_order_for_role(role)):
        raise ValueError("Checkpoint class indexing differs from the frozen E1 role")


def train(config, package, output):
    manifest, ledger = inspect_package(package)
    if config.get("model_role") != manifest["model_role"]:
        raise ValueError("Configuration/package role mismatch")
    for field in ("epochs", "batch", "imgsz"):
        integer(config.get(field), field)
    integer(config.get("seed"), "seed", 0)
    required(config.get("device"), "device")
    required(config.get("experiment_basis"), "experiment_basis")
    allowed = {"lr0", "lrf", "momentum", "weight_decay", "warmup_epochs", "hsv_h",
               "hsv_s", "hsv_v", "degrees", "translate", "scale", "shear", "perspective",
               "flipud", "fliplr", "mosaic", "mixup"}
    hyperparameters = config.get("hyperparameters", {})
    if not isinstance(hyperparameters, dict) or set(hyperparameters) - allowed:
        raise ValueError("Only numeric optimization/augmentation overrides are allowed")
    for key, value in hyperparameters.items():
        number(value, key, 0, float("inf"))
    checkpoint = Path(required(config.get("checkpoint"), "checkpoint")).resolve()
    if not checkpoint.is_file():
        raise ValueError("Local checkpoint/architecture is missing")
    output = Path(output).resolve()
    output.mkdir(parents=True, exist_ok=False)
    # JSON is valid YAML; absolute path avoids Ultralytics resolving `path: .`
    # against a global datasets directory.
    data = {"path": str(Path(package).resolve()), "train": "images/train",
            "val": "images/validation", "names": list(class_order_for_role(manifest["model_role"]))}
    if "test" in manifest["splits"]:
        data["test"] = "images/test"
    save(output / "dataset.yaml", data)
    save(output / "request.json", {"config": config, "package": manifest,
        "input_ledger": ledger, "checkpoint_sha256": sha256(checkpoint),
        "status": "requested", "production_accepted": False})
    model = _yolo(checkpoint)
    model.train(data=str(output / "dataset.yaml"), project=str(output), name="fit",
                exist_ok=False, pretrained=False, resume=False,
                epochs=config["epochs"], batch=config["batch"], imgsz=config["imgsz"],
                seed=config["seed"], device=config["device"], deterministic=True,
                **hyperparameters)
    best = Path(model.trainer.best)
    if not best.is_file():
        raise ValueError("Training did not produce a best checkpoint")
    check_names(_yolo(best), manifest["model_role"])
    result = {"status": "trained_not_validated", "checkpoint": str(best),
              "checkpoint_sha256": sha256(best), "request_sha256": sha256(output / "request.json"),
              "ultralytics_version": importlib.metadata.version("ultralytics"),
              "torch_version": importlib.metadata.version("torch"), "production_accepted": False}
    save(output / "training_result.json", result)
    return result


def export_onnx(checkpoint, role, size, output, model_id, version):
    integer(size, "input size")
    required(model_id, "model_id")
    required(version, "version")
    output = Path(output).resolve()
    if output.exists() or output.with_suffix(".json").exists():
        raise ValueError("Export output already exists")
    model = _yolo(checkpoint)
    check_names(model, role)
    # Copy to a fresh staging directory: framework exporters otherwise overwrite
    # an ONNX file beside the input checkpoint.
    import tempfile
    import shutil
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=output.parent) as directory:
        copied = Path(directory) / "checkpoint.pt"
        shutil.copyfile(checkpoint, copied)
        exported = Path(_yolo(copied).export(format="onnx", imgsz=size, batch=1,
                        dynamic=False, simplify=False, nms=False, half=False, device="cpu"))
        contract = inspect_onnx(exported, role, size)
        with output.open("xb") as handle:
            handle.write(exported.read_bytes())
    result = {**contract, "model_id": model_id, "model_version": version,
              "model_role": role, "model_sha256": sha256(output),
              "checkpoint_sha256": sha256(checkpoint), "model_path": str(output),
              "class_names": list(class_order_for_role(role)), "installed": False,
              "precision": "fp32", "production_accepted": False}
    result["preprocessing"] = {"color": "RGB", "scale": "1/255", "layout": "NCHW",
                               "geometry": "recorded tensor fixture; native parity pending"}
    save(output.with_suffix(".json"), result)
    return result


def inspect_onnx(path, role, size):
    import onnx
    model = onnx.load(str(path))
    onnx.checker.check_model(model)
    inputs, outputs = model.graph.input, model.graph.output
    if len(inputs) != 1 or len(outputs) != 1:
        raise ValueError("Expected one input and one output")
    shape = lambda value: [d.dim_value for d in value.type.tensor_type.shape.dim]
    classes = class_order_for_role(role)
    if not classes or shape(inputs[0]) != [1, 3, size, size]:
        raise ValueError("Expected static NCHW RGB input")
    result = shape(outputs[0])
    if len(result) != 3 or result[:2] != [1, 4 + len(classes)] or result[2] <= 0:
        raise ValueError("Expected [1,4+classes,candidates] YOLOv8 output without embedded NMS")
    if inputs[0].type.tensor_type.elem_type != onnx.TensorProto.FLOAT:
        raise ValueError("Runtime candidate requires float32 input")
    return {"input_name": inputs[0].name, "output_name": outputs[0].name,
            "input_width": size, "input_height": size, "input_shape": shape(inputs[0]),
            "output_shape": result, "output_layout": "channels_first_yolov8"}


def decode(raw, classes, width, height, confidence, nms_iou, roi=(0, 0, 1, 1)):
    """Explicit pixel-xywh YOLOv8 reference; class-aware NMS then ROI remap."""
    import numpy as np
    number(confidence, "confidence")
    number(nms_iou, "NMS IoU")
    from .e1_evaluation import box
    rx, ry, rw, rh = box(dict(zip(("x", "y", "width", "height"), roi)))
    raw = np.asarray(raw)
    if raw.ndim != 3 or raw.shape[:2] != (1, 4 + len(classes)) or not np.isfinite(raw).all():
        raise ValueError("Invalid raw detector tensor")
    found = []
    for row in raw[0].T:
        if np.any(row[4:] < 0) or np.any(row[4:] > 1):
            raise ValueError("Output contract requires probabilities, not logits")
        index = int(np.argmax(row[4:]))
        score = float(row[4 + index])
        if score < confidence:
            continue
        cx, cy, w, h = map(float, row[:4])
        if w <= 0 or h <= 0:
            continue
        x1, y1 = max(0, (cx-w/2)/width), max(0, (cy-h/2)/height)
        x2, y2 = min(1, (cx+w/2)/width), min(1, (cy+h/2)/height)
        if x2 <= x1 or y2 <= y1:
            continue
        found.append({"canonical_object_id": classes[index], "confidence": score,
                      "bbox_xywh_normalized": {"x": x1, "y": y1, "width": x2-x1, "height": y2-y1}})
    kept = []
    for detection in sorted(found, key=lambda d: -d["confidence"]):
        if any(d["canonical_object_id"] == detection["canonical_object_id"] and
               iou(d["bbox_xywh_normalized"], detection["bbox_xywh_normalized"]) > nms_iou for d in kept):
            continue
        kept.append(detection)
    for detection in kept:
        b = detection["bbox_xywh_normalized"]
        b.update(x=rx+b["x"]*rw, y=ry+b["y"]*rh, width=b["width"]*rw, height=b["height"]*rh)
    return kept


def session(model, provider):
    import onnxruntime as ort
    if provider not in ort.get_available_providers():
        raise ValueError(f"Requested provider unavailable: {provider}")
    result = ort.InferenceSession(str(model), providers=[provider])
    result.disable_fallback()
    return result


def parity(model, checkpoint, fixture, metadata, atol, rtol, confidence, nms_iou):
    """Compare checkpoint and ORT on recorded preprocessed inputs and ROI boxes."""
    import numpy as np
    import torch
    validate_metadata(metadata)
    number(atol, "atol", 0, float("inf"))
    number(rtol, "rtol", 0, float("inf"))
    if sha256(model) != metadata["model_sha256"] or sha256(checkpoint) != metadata["checkpoint_sha256"]:
        raise ValueError("Parity artifacts differ from export provenance")
    yolo = _yolo(checkpoint)
    check_names(yolo, metadata["model_role"])
    yolo.model.cpu().float().eval()
    runtime = session(model, "CPUExecutionProvider")
    with np.load(fixture, allow_pickle=False) as recording:
        inputs, rois = recording["inputs"], recording["rois"]
    if (len(inputs) == 0 or inputs.shape[1:] != tuple(metadata["input_shape"][1:])
            or inputs.dtype != np.float32 or not np.isfinite(inputs).all()
            or inputs.min() < 0 or inputs.max() > 1 or rois.shape != (len(inputs), 4)):
        raise ValueError("Fixture requires finite RGB/255 NCHW float32 inputs and normalized ROIs")
    errors, decoded_errors = [], []
    for sample, roi in zip(inputs, rois):
        with torch.no_grad():
            reference = yolo.model(torch.from_numpy(sample[None]))
        if isinstance(reference, (tuple, list)):
            reference = reference[0]
        reference = reference.cpu().numpy()
        actual = runtime.run(None, {runtime.get_inputs()[0].name: sample[None]})[0]
        if actual.shape != reference.shape or not np.isfinite(actual).all():
            raise ValueError("Output shape/nonfinite mismatch")
        errors.append(float(np.max(np.abs(reference - actual))))
        if not np.allclose(reference, actual, atol=atol, rtol=rtol):
            raise ValueError(f"Raw tensor parity failed; maximum absolute error {errors[-1]}")
        a, b = [decode(raw, metadata["class_names"], metadata["input_width"],
                       metadata["input_height"], confidence, nms_iou, roi) for raw in (reference, actual)]
        if len(a) != len(b):
            raise ValueError("NMS detection count differs")
        for left, right in zip(a, b):
            if left["canonical_object_id"] != right["canonical_object_id"]:
                raise ValueError("Postprocessing class differs")
            lv = [left["confidence"], *left["bbox_xywh_normalized"].values()]
            rv = [right["confidence"], *right["bbox_xywh_normalized"].values()]
            if not np.allclose(lv, rv, atol=atol, rtol=rtol):
                raise ValueError("Postprocessing confidence/box/ROI parity failed")
            decoded_errors.append(float(np.max(np.abs(np.array(lv)-rv))))
    return {"parity_passed": True, "model_sha256": sha256(model), "fixture_sha256": sha256(fixture),
            "samples": len(inputs), "atol": atol, "rtol": rtol, "max_absolute_error": max(errors),
            "postprocessing_max_error": max(decoded_errors, default=0),
            "operating_confidence": confidence, "nms_iou": nms_iou,
            "scope": "checkpoint-vs-ONNX on identical preprocessed inputs; native capture preprocessing still needs device acceptance"}


def benchmark(model, fixture, provider, warmup, repeats):
    import numpy as np
    import onnxruntime as ort
    integer(warmup, "warmup", 0)
    integer(repeats, "repeats")
    runtime = session(model, provider)
    with np.load(fixture, allow_pickle=False) as recording:
        inputs = recording["inputs"]
    if not len(inputs) or not np.isfinite(inputs).all():
        raise ValueError("Benchmark requires nonempty finite recorded inputs")
    name = runtime.get_inputs()[0].name
    for index in range(warmup):
        runtime.run(None, {name: inputs[index % len(inputs)][None]})
    times = []
    for _ in range(repeats):
        for sample in inputs:
            start = time.perf_counter_ns()
            runtime.run(None, {name: sample[None]})
            times.append((time.perf_counter_ns()-start)/1e6)
    return {"model_sha256": sha256(model), "fixture_sha256": sha256(fixture),
            "requested_provider": provider, "session_providers": runtime.get_providers(),
            "platform": platform.platform(), "processor": platform.processor(),
            "onnxruntime_version": ort.__version__,
            "iterations": len(times), "warmup": warmup, "latency_ms": {
                "mean": float(np.mean(times)), "p50": float(np.percentile(times, 50)),
                "p95": float(np.percentile(times, 95)), "max": max(times)},
            "scope": "ORT inference only; not complete camera pipeline or device acceptance",
            "production_accepted": False}



def validate_metadata(metadata):
    classes = class_order_for_role(metadata.get("model_role", ""))
    if not classes or metadata.get("class_names") != list(classes):
        raise ValueError("Metadata class order differs from the frozen role")
    for key in ("model_id", "model_version"):
        required(metadata.get(key), key)
    for key in ("model_sha256", "checkpoint_sha256"):
        value = required(metadata.get(key), key)
        if len(value) != 64 or any(c not in "0123456789abcdef" for c in value):
            raise ValueError(f"Invalid {key}")
    width = integer(metadata.get("input_width"), "input_width")
    height = integer(metadata.get("input_height"), "input_height")
    if metadata.get("input_shape") != [1, 3, height, width]:
        raise ValueError("Metadata input layout mismatch")
    shape = metadata.get("output_shape")
    if (not isinstance(shape, list) or len(shape) != 3
            or shape[:2] != [1, 4+len(classes)]
            or metadata.get("output_layout") != "channels_first_yolov8"):
        raise ValueError("Metadata output layout mismatch")
    integer(shape[2], "output candidate count")


def candidate_manifest(metadata, evaluation, parity_result):
    validate_metadata(metadata)
    required(metadata.get("model_path"), "model_path")
    expected = set(class_order_for_role(metadata["model_role"]))
    if set(evaluation.get("class_metrics", {})) != expected or set(evaluation.get("calibration", {})) != expected:
        raise ValueError("Candidate evidence must cover exactly the trained role classes")
    for artifact in (evaluation, parity_result):
        if artifact.get("model_sha256") != metadata.get("model_sha256"):
            raise ValueError("Candidate evidence/model hash mismatch")
    for key in ("model_id", "model_version", "model_role"):
        if metadata.get(key) != evaluation.get(key):
            raise ValueError(f"Candidate {key} mismatch")
    from .e1_training_readiness import validate_evaluation_report
    if (validate_evaluation_report(evaluation) or not evaluation.get("evaluation_valid")
            or any(m["support"] <= 0 for m in evaluation["class_metrics"].values())
            or parity_result.get("parity_passed") is not True):
        raise ValueError("Candidate requires valid nonzero held-out evidence and parity")
    return {**metadata, "manifest_schema_version": "1.0", "installed": False,
            "required_canonical_classes": list(class_order_for_role(metadata["model_role"])),
            "calibration": evaluation["calibration"],
            "evaluation_sha256": fingerprint(evaluation), "parity_sha256": fingerprint(parity_result),
            "production_accepted": False,
            "acceptance_pending": ["scientific acceptance review", "native preprocessing/postprocessing parity",
                                   "offline scenarios", "full pipeline device benchmark"]}

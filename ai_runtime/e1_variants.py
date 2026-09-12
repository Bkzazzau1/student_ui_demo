"""Experimental precision variants and recorded tensor inference."""

from pathlib import Path
from .e1_ml_common import number, save, sha256
from .e1_evaluation import fingerprint
from .e1_training_export import class_order_for_role
from .e1_experiments import decode, session, validate_metadata


def quantize(model, output, precision, fixture=None, metadata=None):
    import onnx
    validate_metadata(metadata or {})
    if not metadata or metadata.get("model_sha256") != sha256(model):
        raise ValueError("Quantization requires exact source export metadata")
    output = Path(output)
    if output.exists() or output.with_suffix(".json").exists():
        raise ValueError("Quantization output exists")
    output.parent.mkdir(parents=True, exist_ok=True)
    import tempfile
    with tempfile.TemporaryDirectory(dir=output.parent) as directory:
        staged = Path(directory) / "variant.onnx"
        if precision == "fp16":
            from onnxconverter_common import float16
            converted = float16.convert_float_to_float16(onnx.load(str(model)), keep_io_types=True)
            onnx.save(converted, str(staged))
        elif precision == "int8":
            if fixture is None:
                raise ValueError("INT8 requires representative TRAIN-split calibration tensors")
            import numpy as np
            from onnxruntime.quantization import CalibrationDataReader, QuantFormat, QuantType, quantize_static
            with np.load(fixture, allow_pickle=False) as recording:
                inputs = recording["inputs"]
                split = str(recording["split"].item())
            if split != "train" or not len(inputs) or not np.isfinite(inputs).all():
                raise ValueError("INT8 calibration requires finite nonempty train-split inputs")
            input_name = onnx.load(str(model)).graph.input[0].name

            class Reader(CalibrationDataReader):
                def __init__(self):
                    self.rows = iter(inputs)

                def get_next(self):
                    item = next(self.rows, None)
                    return None if item is None else {input_name: item[None]}

            quantize_static(str(model), str(staged), Reader(), quant_format=QuantFormat.QDQ,
                            activation_type=QuantType.QInt8, weight_type=QuantType.QInt8)
        else:
            raise ValueError("Precision must be fp16 or int8")
        onnx.checker.check_model(onnx.load(str(staged)))
        with output.open("xb") as handle:
            handle.write(staged.read_bytes())
    result = {**metadata, "source_model_sha256": sha256(model), "model_sha256": sha256(output),
              "model_path": str(output.resolve()), "precision": precision,
              "calibration_fixture_sha256": sha256(fixture) if fixture else None,
              "installed": False, "production_accepted": False,
              "accuracy_comparison": "pending same held-out set and per-class evaluation",
              "provider_benchmark": "pending"}
    save(output.with_suffix(".json"), result)
    return result


def predict_tensors(model, fixture, manifest, metadata, score_floor, nms_iou, provider):
    import numpy as np
    validate_metadata(metadata)
    number(score_floor, "score floor")
    number(nms_iou, "NMS IoU")
    from .e1_training_readiness import validate_dataset_manifest
    if validate_dataset_manifest(manifest) or manifest.get("example_only"):
        raise ValueError("Invalid or example dataset manifest")
    if manifest["model_role"] != metadata["model_role"] or sha256(model) != metadata["model_sha256"]:
        raise ValueError("Model/manifest provenance mismatch")
    if metadata["class_names"] != list(class_order_for_role(manifest["model_role"])):
        raise ValueError("Invalid class mapping")
    with np.load(fixture, allow_pickle=False) as recording:
        inputs, rois = recording["inputs"], recording["rois"]
        ids = recording["sample_ids"].tolist()
        manifest_digest = str(recording["manifest_sha256"].item())
    expected_ids = {s["sample_id"] for s in manifest["samples"]}
    if (manifest_digest != fingerprint(manifest) or len(ids) != len(set(ids))
            or set(ids) != expected_ids or len(inputs) != len(ids) or rois.shape != (len(ids), 4)):
        raise ValueError("Tensor fixture must cover every manifest sample exactly once")
    if inputs.dtype != np.float32 or inputs.shape[1:] != tuple(metadata["input_shape"][1:]) or not np.isfinite(inputs).all():
        raise ValueError("Invalid recorded input tensors")
    runtime = session(model, provider)
    predictions = {}
    for sid, sample, roi in zip(ids, inputs, rois):
        raw = runtime.run(None, {runtime.get_inputs()[0].name: sample[None]})[0]
        predictions[sid] = decode(raw, metadata["class_names"], metadata["input_width"],
                                  metadata["input_height"], score_floor, nms_iou, roi)
    return {**{k: metadata[k] for k in ("model_id", "model_version", "model_sha256", "class_names")},
            "split": manifest["split"], "manifest_sha256": fingerprint(manifest),
            "fixture_sha256": sha256(fixture), "score_floor": score_floor, "nms_iou": nms_iou,
            "prediction_basis": "ORT recorded-tensor inference; class-aware NMS; normalized ROI remap",
            "requested_provider": provider, "samples": predictions}

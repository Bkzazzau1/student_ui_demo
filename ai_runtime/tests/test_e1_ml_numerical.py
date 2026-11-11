"""Synthetic graphs and pixels exercise tools; no E1 model validation evidence."""

import contextlib
import importlib.util
from pathlib import Path
import tempfile
import types
import unittest
from unittest.mock import patch

from ai_runtime.e1_experiments import benchmark, decode, export_onnx, inspect_onnx, parity
from ai_runtime.e1_variants import predict_tensors, quantize
from ai_runtime.e1_tensor_fixtures import prepare
from ai_runtime.e1_ml_common import load, save, sha256
from ai_runtime.e1_evaluation import fingerprint
from ai_runtime.e1_training_export import class_order_for_role
from ai_runtime.tests.test_e1_ml_pipeline import fixtures


AVAILABLE = all(importlib.util.find_spec(m) for m in ("numpy", "onnx", "onnxruntime", "onnxconverter_common", "PIL"))


@unittest.skipUnless(AVAILABLE, "Optional numerical dependencies are not installed")
class NumericalTests(unittest.TestCase):
    def setUp(self):
        import numpy as np
        self.np = np
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.model = self.root / "test.onnx"
        self.raw = np.zeros((1, 12, 2), dtype=np.float32)
        self.raw[0, :4, :] = np.array([[2, 2], [2, 2], [1, 1], [1, 1]])
        self.raw[0, 4, 0] = .9
        self.raw[0, 5, 1] = .8
        self.make_graph(self.model)
        self.checkpoint = self.root / "test.pt"
        self.checkpoint.write_bytes(b"synthetic checkpoint stand-in")
        self.metadata = {**inspect_onnx(self.model, "base", 4),
            "model_id": "synthetic-graph", "model_version": "test-only", "model_role": "base",
            "model_sha256": sha256(self.model), "checkpoint_sha256": sha256(self.checkpoint),
            "class_names": list(class_order_for_role("base")), "precision": "fp32"}
        self.fixture = self.root / "inputs.npz"
        np.savez(self.fixture, inputs=np.ones((2, 3, 4, 4), dtype=np.float32),
                 rois=np.array([[0, 0, 1, 1], [.5, .2, .4, .6]]), split=np.array("train"))

    def make_graph(self, path):
        import onnx
        from onnx import TensorProto, helper, numpy_helper
        np = self.np
        nodes = [helper.make_node("Flatten", ["images"], ["flat"], axis=1),
                 helper.make_node("MatMul", ["flat", "weights"], ["linear"]),
                 helper.make_node("Add", ["linear", "bias"], ["scores"]),
                 helper.make_node("Reshape", ["scores", "shape"], ["output"])]
        initializers = [numpy_helper.from_array(np.zeros((48, 24), dtype=np.float32), "weights"),
                        numpy_helper.from_array(self.raw.reshape(1, 24), "bias"),
                        numpy_helper.from_array(np.array([1, 12, 2], dtype=np.int64), "shape")]
        graph = helper.make_graph(nodes, "synthetic-unit-test", [helper.make_tensor_value_info("images", TensorProto.FLOAT, [1, 3, 4, 4])],
                                  [helper.make_tensor_value_info("output", TensorProto.FLOAT, [1, 12, 2])], initializers)
        model = helper.make_model(graph, opset_imports=[helper.make_opsetid("", 17)], ir_version=10)
        onnx.save(model, str(path))

    def test_decode_class_aware_nms_and_roi(self):
        raw = self.np.concatenate([self.raw, self.raw[:, :, :1]], axis=2)
        result = decode(raw, self.metadata["class_names"], 4, 4, .5, .5, (.5, .2, .4, .6))
        self.assertEqual([d["canonical_object_id"] for d in result], ["person", "phone"])
        b = result[0]["bbox_xywh_normalized"]
        self.assertAlmostEqual(b["x"], .65)
        self.assertAlmostEqual(b["y"], .425)
        self.assertAlmostEqual(b["width"], .1)
        self.assertAlmostEqual(b["height"], .15)

    def test_invalid_tensor_logits_and_roi_fail(self):
        for raw in (self.raw.transpose(0, 2, 1), self.raw * float("nan")):
            with self.assertRaises(ValueError):
                decode(raw, self.metadata["class_names"], 4, 4, .5, .5)
        raw = self.raw.copy()
        raw[0, 4, 0] = 4
        with self.assertRaises(ValueError):
            decode(raw, self.metadata["class_names"], 4, 4, .5, .5)
        with self.assertRaises(ValueError):
            decode(self.raw, self.metadata["class_names"], 4, 4, .5, .5, (0, 0, 2, 1))

    def test_wrong_role_tensor_contract_fails(self):
        with self.assertRaises(ValueError):
            inspect_onnx(self.model, "specialist", 4)

    def test_benchmark_measures_real_synthetic_graph_execution(self):
        result = benchmark(self.model, self.fixture, "CPUExecutionProvider", 1, 2)
        self.assertEqual(result["iterations"], 4)
        self.assertGreater(result["latency_ms"]["mean"], 0)
        self.assertFalse(result["production_accepted"])
        with self.assertRaises(ValueError):
            benchmark(self.model, self.fixture, "UnavailableExecutionProvider", 0, 1)

    def test_fp16_and_int8_variants_preserve_provenance(self):
        for precision in ("fp16", "int8"):
            output = self.root / f"variant-{precision}.onnx"
            result = quantize(self.model, output, precision, self.fixture if precision == "int8" else None, self.metadata)
            self.assertTrue(output.is_file())
            self.assertEqual(result["source_model_sha256"], sha256(self.model))
            self.assertEqual(result["class_names"], self.metadata["class_names"])
            self.assertFalse(result["installed"])
            self.assertEqual(inspect_onnx(output, "base", 4)["input_shape"], [1, 3, 4, 4])

    def test_int8_cannot_use_test_split(self):
        bad = self.root / "test-inputs.npz"
        self.np.savez(bad, inputs=self.np.ones((1, 3, 4, 4), dtype=self.np.float32), split=self.np.array("test"))
        output = self.root / "bad.onnx"
        with self.assertRaises(ValueError):
            quantize(self.model, output, "int8", bad, self.metadata)
        self.assertFalse(output.exists())

    def test_real_image_tensor_preparation_and_prediction(self):
        from PIL import Image
        manifest = fixtures()[0][1]
        for index, sample in enumerate(manifest["samples"]):
            Image.new("RGB", (100, 100), (index, 40, 200)).save(self.root / sample["image_path"])
        path = self.root / "manifest.json"
        save(path, manifest)
        fixture = self.root / "prepared.npz"
        prepared = prepare(path, 4, fixture)
        self.assertEqual(prepared["samples"], 9)
        result = predict_tensors(self.model, fixture, manifest, self.metadata, .5, .5, "CPUExecutionProvider")
        self.assertEqual(set(result["samples"]), {s["sample_id"] for s in manifest["samples"]})
        self.assertEqual(result["manifest_sha256"], fingerprint(manifest))
        self.assertEqual(len(result["samples"]["validation-0"]), 2)

    def fake_yolo(self):
        raw = self.raw

        class Tensor:
            def cpu(self): return self
            def numpy(self): return raw.copy()

        class Model:
            def cpu(self): return self
            def float(self): return self
            def eval(self): return self
            def __call__(self, inputs): return Tensor()

        return types.SimpleNamespace(names=self.metadata["class_names"], model=Model())

    def test_parity_dispatch_and_numerics_against_synthetic_reference(self):
        # Tests the parity harness, not a real PyTorch checkpoint/export.
        fake_torch = types.SimpleNamespace(no_grad=contextlib.nullcontext, from_numpy=lambda v: v)
        with patch.dict("sys.modules", torch=fake_torch), patch("ai_runtime.e1_experiments._yolo", return_value=self.fake_yolo()):
            result = parity(self.model, self.checkpoint, self.fixture, self.metadata, 1e-6, 1e-6, .5, .5)
            self.assertTrue(result["parity_passed"])
            self.assertEqual(result["samples"], 2)
            self.raw[0, 4, 0] = .1
            with self.assertRaises(ValueError):
                parity(self.model, self.checkpoint, self.fixture, self.metadata, 1e-6, 1e-6, .5, .5)

    def test_export_dispatch_uses_safe_static_contract(self):
        def fake_export(**kwargs):
            self.assertFalse(kwargs["nms"])
            self.assertFalse(kwargs["dynamic"])
            return self.model
        yolo = types.SimpleNamespace(names=self.metadata["class_names"], export=fake_export)
        output = self.root / "exported.onnx"
        with patch("ai_runtime.e1_experiments._yolo", return_value=yolo):
            result = export_onnx(self.checkpoint, "base", 4, output, "test-model", "test-only")
        self.assertFalse(result["installed"])
        self.assertEqual(load(output.with_suffix(".json"))["model_sha256"], sha256(output))


if __name__ == "__main__":
    unittest.main()

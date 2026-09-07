import hashlib
import io
import json
from pathlib import Path
import tempfile
import unittest

from ai_runtime.e1_training_experiment import (
    E1TrainingExperimentInputError,
    lock_training_experiment,
    main,
    validate_experiment_spec,
)
from ai_runtime.e1_training_export import export_training_package


def _annotation(annotation_id: str, canonical_id: str):
    return {
        "annotation_id": annotation_id,
        "canonical_object_id": canonical_id,
        "bbox_xywh_normalized": {
            "x": 0.1,
            "y": 0.2,
            "width": 0.3,
            "height": 0.4,
        },
    }


def _sample(sample_id: str, group_id: str, image_path: str):
    return {
        "sample_id": sample_id,
        "source_group_id": group_id,
        "image_path": image_path,
        "width": 1280,
        "height": 720,
        "negative_tags": [],
        "annotations": [_annotation(f"ann-{sample_id}", "person")],
    }


def _manifest(split: str, sample):
    return {
        "schema_version": "1.0",
        "taxonomy_version": "1.0",
        "dataset_id": "e1-base-dataset",
        "dataset_version": "v1",
        "model_role": "base",
        "split": split,
        "samples": [sample],
    }


def _scratch_spec():
    return {
        "experiment_schema_version": "1.0",
        "experiment_id": "e1-base-exp-001",
        "model_role": "base",
        "framework": {
            "name": "example-yolo-framework",
            "version": "explicit-test-version",
        },
        "model": {
            "architecture": "explicit-test-architecture",
            "initialization": "scratch",
            "checkpoint": None,
        },
        "training": {
            "seed": 17,
            "image_size": 640,
            "epochs": 2,
            "batch_size": 2,
            "optimizer": "explicit-test-optimizer",
            "learning_rate": 0.001,
            "weight_decay": 0.0,
            "workers": 0,
            "precision": "fp32",
            "deterministic": True,
        },
        "augmentation": {
            "enabled": False,
            "parameters": {},
        },
        "execution": {
            "device": "cpu",
        },
    }


class E1TrainingExperimentTests(unittest.TestCase):
    def _write_manifest(self, root: Path, name: str, value) -> Path:
        path = root / name
        path.write_text(json.dumps(value), encoding="utf-8")
        return path

    def _build_base_export(self, root: Path) -> Path:
        (root / "train.jpg").write_bytes(b"synthetic-train-image")
        (root / "validation.jpg").write_bytes(b"synthetic-validation-image")
        train = self._write_manifest(
            root,
            "train.json",
            _manifest("train", _sample("sample-train", "group-train", "train.jpg")),
        )
        validation = self._write_manifest(
            root,
            "validation.json",
            _manifest(
                "validation",
                _sample("sample-validation", "group-validation", "validation.jpg"),
            ),
        )
        export_dir = root / "export"
        result = export_training_package([train, validation], export_dir)
        self.assertTrue(result["ok"])
        return export_dir

    def _write_spec(self, root: Path, spec, name: str = "experiment.json") -> Path:
        path = root / name
        path.write_text(json.dumps(spec), encoding="utf-8")
        return path

    def test_valid_scratch_experiment_locks_verified_dataset_package(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            export_dir = self._build_base_export(root)
            spec_path = self._write_spec(root, _scratch_spec())
            output = root / "experiment.lock.json"

            result = lock_training_experiment(spec_path, export_dir, output)

            self.assertTrue(result["ok"])
            self.assertEqual(result["experiment_id"], "e1-base-exp-001")
            self.assertEqual(result["model_role"], "base")
            self.assertEqual(len(result["dataset_package_sha256"]), 64)
            self.assertIsNone(result["checkpoint_sha256"])
            lock = json.loads(output.read_text(encoding="utf-8"))
            self.assertEqual(lock["lock_schema_version"], "1.0")
            self.assertEqual(lock["dataset"]["verified_sample_count"], 2)
            self.assertEqual(lock["dataset"]["package_sha256"], result["dataset_package_sha256"])
            self.assertEqual(lock["experiment"], _scratch_spec())
            self.assertIsNone(lock["checkpoint"])

    def test_same_spec_and_export_produce_same_dataset_fingerprint(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            export_dir = self._build_base_export(root)
            spec_path = self._write_spec(root, _scratch_spec())

            first = lock_training_experiment(spec_path, export_dir, root / "first.lock.json")
            second = lock_training_experiment(spec_path, export_dir, root / "second.lock.json")

            self.assertTrue(first["ok"])
            self.assertTrue(second["ok"])
            self.assertEqual(first["dataset_package_sha256"], second["dataset_package_sha256"])

    def test_missing_core_training_choice_is_not_defaulted(self):
        spec = _scratch_spec()
        del spec["training"]["learning_rate"]

        issues = validate_experiment_spec(spec)

        self.assertIn("missing_training_field", {issue.code for issue in issues})
        self.assertIn("training.learning_rate", {issue.path for issue in issues})

    def test_invalid_spec_does_not_write_lock(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            export_dir = self._build_base_export(root)
            spec = _scratch_spec()
            spec["training"]["precision"] = "guess"
            spec_path = self._write_spec(root, spec)
            output = root / "experiment.lock.json"

            result = lock_training_experiment(spec_path, export_dir, output)

            self.assertFalse(result["ok"])
            self.assertFalse(output.exists())
            self.assertIn("invalid_precision", {issue["code"] for issue in result["issues"]})

    def test_export_image_tampering_is_detected_before_lock(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            export_dir = self._build_base_export(root)
            (export_dir / "images/train/sample-train.jpg").write_bytes(b"tampered")
            spec_path = self._write_spec(root, _scratch_spec())

            with self.assertRaises(E1TrainingExperimentInputError) as raised:
                lock_training_experiment(spec_path, export_dir, root / "lock.json")

            self.assertEqual(raised.exception.code, "export_image_hash_mismatch")
            self.assertFalse((root / "lock.json").exists())

    def test_experiment_role_must_match_training_export(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            export_dir = self._build_base_export(root)
            spec = _scratch_spec()
            spec["model_role"] = "specialist"
            spec_path = self._write_spec(root, spec)

            with self.assertRaises(E1TrainingExperimentInputError) as raised:
                lock_training_experiment(spec_path, export_dir, root / "lock.json")

            self.assertEqual(raised.exception.code, "experiment_export_role_mismatch")

    def test_pretrained_checkpoint_requires_matching_sha256(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            export_dir = self._build_base_export(root)
            checkpoint = root / "checkpoint.pt"
            checkpoint_bytes = b"synthetic-checkpoint-bytes"
            checkpoint.write_bytes(checkpoint_bytes)
            spec = _scratch_spec()
            spec["model"] = {
                "architecture": "explicit-test-architecture",
                "initialization": "pretrained",
                "checkpoint": {
                    "path": "checkpoint.pt",
                    "sha256": hashlib.sha256(checkpoint_bytes).hexdigest(),
                },
            }
            spec_path = self._write_spec(root, spec)
            output = root / "lock.json"

            result = lock_training_experiment(spec_path, export_dir, output)

            self.assertTrue(result["ok"])
            self.assertEqual(
                result["checkpoint_sha256"], hashlib.sha256(checkpoint_bytes).hexdigest()
            )
            lock = json.loads(output.read_text(encoding="utf-8"))
            self.assertEqual(lock["checkpoint"]["declared_path"], "checkpoint.pt")

    def test_pretrained_checkpoint_hash_mismatch_fails_closed(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            export_dir = self._build_base_export(root)
            checkpoint = root / "checkpoint.pt"
            checkpoint.write_bytes(b"actual-checkpoint")
            spec = _scratch_spec()
            spec["model"] = {
                "architecture": "explicit-test-architecture",
                "initialization": "pretrained",
                "checkpoint": {
                    "path": "checkpoint.pt",
                    "sha256": "0" * 64,
                },
            }
            spec_path = self._write_spec(root, spec)

            with self.assertRaises(E1TrainingExperimentInputError) as raised:
                lock_training_experiment(spec_path, export_dir, root / "lock.json")

            self.assertEqual(raised.exception.code, "checkpoint_hash_mismatch")

    def test_existing_lock_is_never_overwritten(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            export_dir = self._build_base_export(root)
            spec_path = self._write_spec(root, _scratch_spec())
            output = root / "lock.json"
            output.write_text("preserve", encoding="utf-8")

            with self.assertRaises(E1TrainingExperimentInputError) as raised:
                lock_training_experiment(spec_path, export_dir, output)

            self.assertEqual(raised.exception.code, "output_exists")
            self.assertEqual(output.read_text(encoding="utf-8"), "preserve")

    def test_cli_returns_machine_readable_failure(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            stream = io.StringIO()

            exit_code = main(
                [
                    "--export",
                    str(root / "missing-export"),
                    "--output",
                    str(root / "lock.json"),
                    str(root / "missing-spec.json"),
                ],
                stdout=stream,
            )
            payload = json.loads(stream.getvalue())

            self.assertEqual(exit_code, 1)
            self.assertFalse(payload["ok"])
            self.assertIn("experiment_spec_read_error", {item["code"] for item in payload["issues"]})


if __name__ == "__main__":
    unittest.main()

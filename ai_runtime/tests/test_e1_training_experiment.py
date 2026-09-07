import hashlib
import io
import json
from pathlib import Path
import tempfile
import unittest

from ai_runtime.e1_training_experiment import (
    E1TrainingExperimentInputError,
    build_training_plan,
    main,
    materialize_training_plan,
)
from ai_runtime.e1_training_export import class_order_for_role


def _write_json(path: Path, value) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2) + "\n", encoding="utf-8")


def _export_manifest(role: str = "base"):
    class_order = class_order_for_role(role)
    return {
        "export_schema_version": "1.0",
        "taxonomy_version": "1.0",
        "dataset_id": "e1-base-dataset",
        "dataset_version": "v1",
        "model_role": role,
        "class_map": [
            {"index": index, "canonical_object_id": canonical_id}
            for index, canonical_id in enumerate(class_order)
        ],
        "source_manifests": ["train.json", "validation.json"],
        "splits": {
            "train": {"sample_count": 10, "annotation_count": 12},
            "validation": {"sample_count": 4, "annotation_count": 5},
        },
        "samples": [],
    }


def _spec(**overrides):
    value = {
        "schema_version": "1.0",
        "experiment_id": "e1-base-exp-001",
        "framework": "ultralytics",
        "framework_version": "pinned-test-version",
        "task": "detect",
        "model_role": "base",
        "checkpoint_path": "models/init.pt",
        "project_dir": "runs",
        "seed": 12345,
        "trainer_args": {
            "epochs": 2,
            "imgsz": 320,
            "batch": 2,
            "workers": 0,
            "device": "cpu",
            "optimizer": "SGD",
            "lr0": 0.001,
            "weight_decay": 0.0,
            "patience": 0,
            "deterministic": True,
        },
        "augmentation_policy": {"mode": "framework_defaults", "args": {}},
    }
    value.update(overrides)
    return value


class E1TrainingExperimentTests(unittest.TestCase):
    def _workspace(self):
        temporary = tempfile.TemporaryDirectory()
        root = Path(temporary.name)
        export_dir = root / "export"
        export_dir.mkdir()
        _write_json(export_dir / "export_manifest.json", _export_manifest())
        (export_dir / "dataset.yaml").write_text(
            "path: .\ntrain: images/train\nval: images/validation\n",
            encoding="utf-8",
        )
        checkpoint = root / "models" / "init.pt"
        checkpoint.parent.mkdir()
        checkpoint.write_bytes(b"synthetic-checkpoint-for-contract-tests")
        spec_path = root / "experiment.json"
        _write_json(spec_path, _spec())
        return temporary, root, export_dir, checkpoint, spec_path

    def test_builds_non_executing_plan_with_pinned_provenance(self):
        temporary, root, export_dir, checkpoint, spec_path = self._workspace()
        self.addCleanup(temporary.cleanup)

        plan = build_training_plan(spec_path, export_dir)

        self.assertEqual(plan["execution_status"], "not_executed")
        self.assertEqual(plan["framework"], "ultralytics")
        self.assertEqual(plan["framework_version"], "pinned-test-version")
        self.assertEqual(plan["model_role"], "base")
        self.assertEqual(plan["dataset"]["dataset_id"], "e1-base-dataset")
        self.assertEqual(plan["dataset"]["dataset_version"], "v1")
        self.assertEqual(
            plan["checkpoint"]["sha256"],
            hashlib.sha256(checkpoint.read_bytes()).hexdigest(),
        )
        self.assertEqual(plan["run_dir"], str((root / "runs" / "e1-base-exp-001").resolve()))
        self.assertEqual(plan["command_argv"][0:3], ["yolo", "detect", "train"])
        self.assertIn("exist_ok=false", plan["command_argv"])
        self.assertIn("seed=12345", plan["command_argv"])
        self.assertIn("deterministic=true", plan["command_argv"])
        self.assertNotIn("shell", plan)

    def test_materializes_once_and_refuses_plan_overwrite(self):
        temporary, _, export_dir, _, spec_path = self._workspace()
        self.addCleanup(temporary.cleanup)
        output_plan = Path(temporary.name) / "plans" / "plan.json"

        result = materialize_training_plan(spec_path, export_dir, output_plan)
        self.assertTrue(result["ok"])
        self.assertTrue(output_plan.is_file())
        written = json.loads(output_plan.read_text(encoding="utf-8"))
        self.assertEqual(written["execution_status"], "not_executed")

        with self.assertRaises(E1TrainingExperimentInputError) as caught:
            materialize_training_plan(spec_path, export_dir, output_plan)
        self.assertEqual(caught.exception.code, "output_plan_exists")

    def test_missing_checkpoint_fails_closed(self):
        temporary, _, export_dir, checkpoint, spec_path = self._workspace()
        self.addCleanup(temporary.cleanup)
        checkpoint.unlink()

        with self.assertRaises(E1TrainingExperimentInputError) as caught:
            build_training_plan(spec_path, export_dir)
        self.assertEqual(caught.exception.code, "checkpoint_unavailable")

    def test_model_role_must_match_export(self):
        temporary, root, export_dir, _, spec_path = self._workspace()
        self.addCleanup(temporary.cleanup)
        _write_json(
            spec_path,
            _spec(model_role="specialist"),
        )

        with self.assertRaises(E1TrainingExperimentInputError) as caught:
            build_training_plan(spec_path, export_dir)
        self.assertEqual(caught.exception.code, "model_role_mismatch")
        self.assertFalse((root / "runs" / "e1-base-exp-001").exists())

    def test_frozen_class_map_drift_is_rejected(self):
        temporary, _, export_dir, _, spec_path = self._workspace()
        self.addCleanup(temporary.cleanup)
        manifest = _export_manifest()
        manifest["class_map"][0]["canonical_object_id"] = "phone"
        _write_json(export_dir / "export_manifest.json", manifest)

        with self.assertRaises(E1TrainingExperimentInputError) as caught:
            build_training_plan(spec_path, export_dir)
        self.assertEqual(caught.exception.code, "class_map_mismatch")

    def test_required_training_choices_cannot_be_implicit(self):
        temporary, _, export_dir, _, spec_path = self._workspace()
        self.addCleanup(temporary.cleanup)
        spec = _spec()
        del spec["trainer_args"]["optimizer"]
        _write_json(spec_path, spec)

        with self.assertRaises(E1TrainingExperimentInputError) as caught:
            build_training_plan(spec_path, export_dir)
        self.assertEqual(caught.exception.code, "missing_trainer_args")
        self.assertIn("optimizer", caught.exception.message)

    def test_reserved_trainer_arguments_cannot_override_provenance(self):
        temporary, _, export_dir, _, spec_path = self._workspace()
        self.addCleanup(temporary.cleanup)
        spec = _spec()
        spec["trainer_args"]["data"] = "other.yaml"
        _write_json(spec_path, spec)

        with self.assertRaises(E1TrainingExperimentInputError) as caught:
            build_training_plan(spec_path, export_dir)
        self.assertEqual(caught.exception.code, "reserved_trainer_arg")

    def test_framework_version_must_be_explicit(self):
        temporary, _, export_dir, _, spec_path = self._workspace()
        self.addCleanup(temporary.cleanup)
        _write_json(spec_path, _spec(framework_version=""))

        with self.assertRaises(E1TrainingExperimentInputError) as caught:
            build_training_plan(spec_path, export_dir)
        self.assertEqual(caught.exception.code, "missing_framework_version")

    def test_existing_run_directory_is_rejected(self):
        temporary, root, export_dir, _, spec_path = self._workspace()
        self.addCleanup(temporary.cleanup)
        (root / "runs" / "e1-base-exp-001").mkdir(parents=True)

        with self.assertRaises(E1TrainingExperimentInputError) as caught:
            build_training_plan(spec_path, export_dir)
        self.assertEqual(caught.exception.code, "run_output_exists")

    def test_explicit_augmentation_is_recorded_as_argv_not_shell_text(self):
        temporary, _, export_dir, _, spec_path = self._workspace()
        self.addCleanup(temporary.cleanup)
        spec = _spec(
            augmentation_policy={
                "mode": "explicit",
                "args": {"fliplr": 0.25, "mosaic": 0.5},
            }
        )
        _write_json(spec_path, spec)

        plan = build_training_plan(spec_path, export_dir)
        self.assertEqual(plan["augmentation_policy"]["mode"], "explicit")
        self.assertIn("fliplr=0.25", plan["command_argv"])
        self.assertIn("mosaic=0.5", plan["command_argv"])
        self.assertIsInstance(plan["command_argv"], list)

    def test_cli_failure_does_not_write_plan(self):
        temporary, root, export_dir, checkpoint, spec_path = self._workspace()
        self.addCleanup(temporary.cleanup)
        checkpoint.unlink()
        output_plan = root / "plans" / "plan.json"
        stdout = io.StringIO()

        exit_code = main(
            [
                "--spec",
                str(spec_path),
                "--export",
                str(export_dir),
                "--output-plan",
                str(output_plan),
            ],
            stdout=stdout,
        )
        result = json.loads(stdout.getvalue())
        self.assertEqual(exit_code, 1)
        self.assertFalse(result["ok"])
        self.assertFalse(output_plan.exists())
        self.assertEqual(result["execution_status"], "not_executed")


if __name__ == "__main__":
    unittest.main()

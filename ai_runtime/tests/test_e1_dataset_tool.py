import io
import json
from pathlib import Path
import tempfile
import unittest

from ai_runtime.e1_dataset_tool import (
    main,
    validate_dataset_files,
    validate_evaluation_file,
)
from ai_runtime.e1_training_readiness import BASE_TRAINABLE_CLASSES


def _sample(
    canonical_object_id: str,
    *,
    sample_id: str,
    source_group_id: str,
    negative_tags=None,
):
    return {
        "sample_id": sample_id,
        "source_group_id": source_group_id,
        "image_path": f"images/{sample_id}.jpg",
        "width": 1280,
        "height": 720,
        "negative_tags": negative_tags or [],
        "annotations": [
            {
                "annotation_id": f"ann-{sample_id}",
                "canonical_object_id": canonical_object_id,
                "bbox_xywh_normalized": {
                    "x": 0.1,
                    "y": 0.2,
                    "width": 0.3,
                    "height": 0.4,
                },
            }
        ],
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


def _evaluation_report(*, support: int = 10, calibrated: bool = False):
    class_metrics = {
        canonical_id: {
            "support": support,
            "precision": 0.8,
            "recall": 0.8,
            "f1": 0.8,
            "ap50": 0.8,
            "ap50_95": 0.7,
        }
        for canonical_id in BASE_TRAINABLE_CLASSES
    }
    calibration = {}
    for canonical_id in BASE_TRAINABLE_CLASSES:
        if calibrated:
            calibration[canonical_id] = {
                "selected_confidence_threshold": 0.5,
                "selection_basis": "held-out calibration sweep",
                "calibration_dataset_id": "e1-base-calibration-v1",
            }
        else:
            calibration[canonical_id] = {"selected_confidence_threshold": None}

    return {
        "schema_version": "1.0",
        "taxonomy_version": "1.0",
        "model_id": "e1-base-candidate",
        "model_version": "candidate-1",
        "evaluation_dataset_id": "e1-base-heldout-v1",
        "model_role": "base",
        "evaluation_split": "validation",
        "class_metrics": class_metrics,
        "hard_negative_metrics": {},
        "calibration": calibration,
    }


class E1DatasetToolTests(unittest.TestCase):
    def _write_json(self, directory: Path, name: str, value) -> Path:
        path = directory / name
        path.write_text(json.dumps(value), encoding="utf-8")
        return path

    def test_valid_dataset_files_report_counts_and_no_leakage(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            train = self._write_json(
                root,
                "train.json",
                _manifest(
                    "train",
                    _sample(
                        "person",
                        sample_id="train-1",
                        source_group_id="capture-train-1",
                        negative_tags=["hand_without_phone"],
                    ),
                ),
            )
            validation = self._write_json(
                root,
                "validation.json",
                _manifest(
                    "validation",
                    _sample(
                        "phone",
                        sample_id="validation-1",
                        source_group_id="capture-validation-1",
                    ),
                ),
            )

            result = validate_dataset_files([train, validation])

            self.assertTrue(result["ok"])
            self.assertEqual(result["issues"], [])
            self.assertEqual(result["summary"]["manifest_count"], 2)
            self.assertEqual(result["summary"]["sample_count"], 2)
            self.assertEqual(result["summary"]["annotation_count"], 2)
            self.assertEqual(result["summary"]["class_counts"], {"person": 1, "phone": 1})
            self.assertEqual(
                result["summary"]["negative_tag_counts"],
                {"hand_without_phone": 1},
            )

    def test_cross_split_source_group_leakage_fails(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            train = self._write_json(
                root,
                "train.json",
                _manifest(
                    "train",
                    _sample(
                        "person",
                        sample_id="train-1",
                        source_group_id="shared-capture",
                    ),
                ),
            )
            validation = self._write_json(
                root,
                "validation.json",
                _manifest(
                    "validation",
                    _sample(
                        "person",
                        sample_id="validation-1",
                        source_group_id="shared-capture",
                    ),
                ),
            )

            result = validate_dataset_files([train, validation])

            self.assertFalse(result["ok"])
            self.assertIn(
                "source_group_split_leakage",
                {issue["code"] for issue in result["issues"]},
            )

    def test_malformed_json_is_a_machine_readable_failure(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            path = Path(temp_dir) / "broken.json"
            path.write_text("{not-json", encoding="utf-8")

            result = validate_dataset_files([path])

            self.assertFalse(result["ok"])
            self.assertEqual(result["loaded_files"], [])
            self.assertEqual(result["issues"][0]["code"], "invalid_json")

    def test_zero_heldout_support_is_not_evaluation_ready(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            path = self._write_json(
                Path(temp_dir),
                "evaluation.json",
                _evaluation_report(support=0),
            )

            result = validate_evaluation_file(path)

            self.assertFalse(result["ok"])
            self.assertFalse(result["calibration_complete"])
            self.assertIn(
                "zero_class_support",
                {issue["code"] for issue in result["issues"]},
            )

    def test_valid_evaluation_can_be_uncalibrated_without_being_invalid(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            path = self._write_json(
                Path(temp_dir),
                "evaluation.json",
                _evaluation_report(support=10, calibrated=False),
            )

            result = validate_evaluation_file(path)

            self.assertTrue(result["ok"])
            self.assertFalse(result["calibration_complete"])
            self.assertEqual(result["issues"], [])

    def test_calibrated_evaluation_reports_complete(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            path = self._write_json(
                Path(temp_dir),
                "evaluation.json",
                _evaluation_report(support=10, calibrated=True),
            )

            result = validate_evaluation_file(path)

            self.assertTrue(result["ok"])
            self.assertTrue(result["calibration_complete"])

    def test_cli_emits_json_and_nonzero_exit_for_unsafe_data(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            train = self._write_json(
                root,
                "train.json",
                _manifest(
                    "train",
                    _sample(
                        "person",
                        sample_id="train-1",
                        source_group_id="shared-capture",
                    ),
                ),
            )
            validation = self._write_json(
                root,
                "validation.json",
                _manifest(
                    "validation",
                    _sample(
                        "person",
                        sample_id="validation-1",
                        source_group_id="shared-capture",
                    ),
                ),
            )
            output = io.StringIO()

            exit_code = main(
                ["dataset", str(train), str(validation)],
                stdout=output,
            )
            payload = json.loads(output.getvalue())

            self.assertEqual(exit_code, 1)
            self.assertFalse(payload["ok"])
            self.assertEqual(payload["command"], "dataset")


if __name__ == "__main__":
    unittest.main()

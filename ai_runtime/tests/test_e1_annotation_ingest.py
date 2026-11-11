import copy
import io
import json
from pathlib import Path
import tempfile
import unittest

from ai_runtime.e1_annotation_ingest import (
    build_dataset_manifest,
    ingest_annotation_file,
    main,
)
from ai_runtime.e1_training_readiness import validate_dataset_manifest


def _base_staging() -> dict:
    return {
        "ingest_schema_version": "1.0",
        "dataset_id": "e1-controlled-pilot",
        "dataset_version": "2026.09.1",
        "model_role": "base",
        "split": "train",
        "records": [
            {
                "source_group_id": "capture-session-001",
                "image_path": ".\\images\\session-001\\frame-0001.jpg",
                "width": 1000,
                "height": 500,
                "negative_tags": ["Hand_Without_Phone", "bracelet_or_wristband", "bracelet_or_wristband"],
                "annotations": [
                    {
                        "canonical_object_id": "Phone",
                        "bbox_xyxy_pixels": [100, 50, 300, 250],
                    }
                ],
            }
        ],
    }


class BuildDatasetManifestTests(unittest.TestCase):
    def test_pixel_xyxy_becomes_full_image_normalized_manifest(self) -> None:
        manifest, issues = build_dataset_manifest(_base_staging())

        self.assertEqual(issues, ())
        self.assertIsNotNone(manifest)
        assert manifest is not None
        self.assertEqual(validate_dataset_manifest(manifest), ())
        sample = manifest["samples"][0]
        self.assertEqual(sample["image_path"], "images/session-001/frame-0001.jpg")
        self.assertEqual(
            sample["negative_tags"],
            ["bracelet_or_wristband", "hand_without_phone"],
        )
        annotation = sample["annotations"][0]
        self.assertEqual(annotation["canonical_object_id"], "phone")
        self.assertEqual(
            annotation["bbox_xywh_normalized"],
            {"x": 0.1, "y": 0.1, "width": 0.2, "height": 0.4},
        )
        self.assertTrue(sample["sample_id"].startswith("e1s_"))
        self.assertTrue(annotation["annotation_id"].startswith("e1a_"))

    def test_pixel_xywh_and_normalized_boxes_are_supported(self) -> None:
        staging = _base_staging()
        staging["records"][0]["annotations"] = [
            {
                "canonical_object_id": "laptop",
                "bbox_xywh_pixels": [250, 100, 500, 250],
            },
            {
                "canonical_object_id": "book",
                "bbox_xywh_normalized": [0.2, 0.3, 0.1, 0.2],
            },
        ]

        manifest, issues = build_dataset_manifest(staging)

        self.assertEqual(issues, ())
        assert manifest is not None
        boxes = {
            item["canonical_object_id"]: item["bbox_xywh_normalized"]
            for item in manifest["samples"][0]["annotations"]
        }
        self.assertEqual(
            boxes["laptop"],
            {"x": 0.25, "y": 0.2, "width": 0.5, "height": 0.5},
        )
        self.assertEqual(
            boxes["book"],
            {"x": 0.2, "y": 0.3, "width": 0.1, "height": 0.2},
        )

    def test_ids_are_deterministic_and_annotation_order_independent(self) -> None:
        staging = _base_staging()
        staging["records"][0]["annotations"] = [
            {
                "canonical_object_id": "phone",
                "bbox_xywh_normalized": [0.1, 0.2, 0.2, 0.3],
            },
            {
                "canonical_object_id": "laptop",
                "bbox_xywh_normalized": [0.5, 0.4, 0.3, 0.4],
            },
        ]
        reversed_staging = copy.deepcopy(staging)
        reversed_staging["records"][0]["annotations"].reverse()

        first, first_issues = build_dataset_manifest(staging)
        second, second_issues = build_dataset_manifest(reversed_staging)

        self.assertEqual(first_issues, ())
        self.assertEqual(second_issues, ())
        assert first is not None and second is not None
        self.assertEqual(first["samples"][0]["sample_id"], second["samples"][0]["sample_id"])
        first_ids = {
            item["canonical_object_id"]: item["annotation_id"]
            for item in first["samples"][0]["annotations"]
        }
        second_ids = {
            item["canonical_object_id"]: item["annotation_id"]
            for item in second["samples"][0]["annotations"]
        }
        self.assertEqual(first_ids, second_ids)

    def test_hard_negative_only_sample_is_valid(self) -> None:
        staging = _base_staging()
        staging["records"][0]["annotations"] = []
        staging["records"][0]["negative_tags"] = ["bracelet_or_wristband", "earring"]

        manifest, issues = build_dataset_manifest(staging)

        self.assertEqual(issues, ())
        assert manifest is not None
        self.assertEqual(manifest["samples"][0]["annotations"], [])
        self.assertEqual(
            manifest["samples"][0]["negative_tags"],
            ["bracelet_or_wristband", "earring"],
        )

    def test_missing_source_group_is_rejected_without_inference(self) -> None:
        staging = _base_staging()
        staging["records"][0]["source_group_id"] = ""

        manifest, issues = build_dataset_manifest(staging)

        self.assertIsNone(manifest)
        self.assertIn("missing_source_group_id", {issue.code for issue in issues})

    def test_semantic_alias_is_not_guessed(self) -> None:
        staging = _base_staging()
        staging["records"][0]["annotations"][0]["canonical_object_id"] = "cell phone"

        manifest, issues = build_dataset_manifest(staging)

        self.assertIsNone(manifest)
        self.assertIn("class_not_allowed_for_role", {issue.code for issue in issues})

    def test_specialist_class_cannot_enter_base_manifest(self) -> None:
        staging = _base_staging()
        staging["records"][0]["annotations"][0]["canonical_object_id"] = "wrist_device"

        manifest, issues = build_dataset_manifest(staging)

        self.assertIsNone(manifest)
        self.assertIn("class_not_allowed_for_role", {issue.code for issue in issues})

    def test_ambiguous_geometry_source_is_rejected(self) -> None:
        staging = _base_staging()
        annotation = staging["records"][0]["annotations"][0]
        annotation["bbox_xywh_normalized"] = [0.1, 0.1, 0.2, 0.4]

        manifest, issues = build_dataset_manifest(staging)

        self.assertIsNone(manifest)
        self.assertIn("ambiguous_bbox_source", {issue.code for issue in issues})

    def test_out_of_bounds_pixel_geometry_is_rejected(self) -> None:
        staging = _base_staging()
        staging["records"][0]["annotations"][0]["bbox_xyxy_pixels"] = [900, 50, 1100, 250]

        manifest, issues = build_dataset_manifest(staging)

        self.assertIsNone(manifest)
        self.assertIn("bbox_out_of_bounds", {issue.code for issue in issues})

    def test_duplicate_class_and_box_is_rejected(self) -> None:
        staging = _base_staging()
        duplicate = copy.deepcopy(staging["records"][0]["annotations"][0])
        staging["records"][0]["annotations"].append(duplicate)

        manifest, issues = build_dataset_manifest(staging)

        self.assertIsNone(manifest)
        self.assertIn("duplicate_annotation_identity", {issue.code for issue in issues})

    def test_specialist_role_accepts_only_specialist_class(self) -> None:
        staging = _base_staging()
        staging["model_role"] = "specialist"
        staging["records"][0]["annotations"] = [
            {
                "canonical_object_id": "earbud",
                "bbox_xywh_pixels": [100, 50, 40, 30],
            }
        ]

        manifest, issues = build_dataset_manifest(staging)

        self.assertEqual(issues, ())
        assert manifest is not None
        self.assertEqual(
            manifest["samples"][0]["annotations"][0]["canonical_object_id"],
            "earbud",
        )


class AnnotationIngestCliTests(unittest.TestCase):
    def _write_staging(self, directory: Path, value: dict | None = None) -> Path:
        path = directory / "staging.json"
        path.write_text(json.dumps(value or _base_staging()), encoding="utf-8")
        return path

    def test_ingest_writes_valid_manifest_and_result(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            directory = Path(temporary_directory)
            input_path = self._write_staging(directory)
            output_path = directory / "canonical" / "train.json"
            stdout = io.StringIO()

            exit_code = main(
                [str(input_path), str(output_path), "--pretty"],
                stdout=stdout,
            )

            self.assertEqual(exit_code, 0)
            result = json.loads(stdout.getvalue())
            self.assertTrue(result["ok"])
            self.assertEqual(result["summary"]["sample_count"], 1)
            self.assertEqual(result["summary"]["annotation_count"], 1)
            manifest = json.loads(output_path.read_text(encoding="utf-8"))
            self.assertEqual(validate_dataset_manifest(manifest), ())

    def test_existing_output_requires_force(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            directory = Path(temporary_directory)
            input_path = self._write_staging(directory)
            output_path = directory / "manifest.json"
            output_path.write_text("do-not-replace", encoding="utf-8")

            blocked = ingest_annotation_file(input_path, output_path)
            self.assertFalse(blocked["ok"])
            self.assertEqual(blocked["issues"][0]["code"], "output_exists")
            self.assertEqual(output_path.read_text(encoding="utf-8"), "do-not-replace")

            replaced = ingest_annotation_file(input_path, output_path, force=True)
            self.assertTrue(replaced["ok"])
            manifest = json.loads(output_path.read_text(encoding="utf-8"))
            self.assertEqual(validate_dataset_manifest(manifest), ())

    def test_invalid_json_never_creates_output(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            directory = Path(temporary_directory)
            input_path = directory / "broken.json"
            output_path = directory / "manifest.json"
            input_path.write_text("{broken", encoding="utf-8")

            result = ingest_annotation_file(input_path, output_path)

            self.assertFalse(result["ok"])
            self.assertEqual(result["issues"][0]["code"], "invalid_json")
            self.assertFalse(output_path.exists())

    def test_invalid_staging_never_creates_output(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            directory = Path(temporary_directory)
            staging = _base_staging()
            staging["records"][0]["source_group_id"] = ""
            input_path = self._write_staging(directory, staging)
            output_path = directory / "manifest.json"

            result = ingest_annotation_file(input_path, output_path)

            self.assertFalse(result["ok"])
            self.assertFalse(output_path.exists())

    def test_input_and_output_must_be_different_files(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            directory = Path(temporary_directory)
            input_path = self._write_staging(directory)

            result = ingest_annotation_file(input_path, input_path, force=True)

            self.assertFalse(result["ok"])
            self.assertEqual(result["issues"][0]["code"], "input_output_same")


if __name__ == "__main__":
    unittest.main()

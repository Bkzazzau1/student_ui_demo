import hashlib
import io
import json
from pathlib import Path
import tempfile
import unittest

from ai_runtime.e1_training_export import (
    BASE_YOLO_CLASS_ORDER,
    SPECIALIST_YOLO_CLASS_ORDER,
    E1TrainingExportInputError,
    class_order_for_role,
    export_training_package,
    main,
)
from ai_runtime.e1_training_readiness import expected_classes_for_role


def _annotation(annotation_id: str, canonical_id: str, *, x=0.1, y=0.2, width=0.3, height=0.4):
    return {
        "annotation_id": annotation_id,
        "canonical_object_id": canonical_id,
        "bbox_xywh_normalized": {
            "x": x,
            "y": y,
            "width": width,
            "height": height,
        },
    }


def _sample(sample_id: str, group_id: str, image_path: str, annotations, negative_tags=None):
    return {
        "sample_id": sample_id,
        "source_group_id": group_id,
        "image_path": image_path,
        "width": 1280,
        "height": 720,
        "negative_tags": negative_tags or [],
        "annotations": annotations,
    }


def _manifest(role: str, split: str, samples, *, dataset_id="e1-dataset", version="v1"):
    return {
        "schema_version": "1.0",
        "taxonomy_version": "1.1",
        "dataset_id": dataset_id,
        "dataset_version": version,
        "model_role": role,
        "split": split,
        "samples": samples,
    }


class E1TrainingExportTests(unittest.TestCase):
    def _write_image(self, root: Path, name: str, payload: bytes) -> Path:
        path = root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(payload)
        return path

    def _write_manifest(self, root: Path, name: str, value) -> Path:
        path = root / name
        path.write_text(json.dumps(value), encoding="utf-8")
        return path

    def test_class_orders_match_frozen_training_roles(self):
        self.assertEqual(set(BASE_YOLO_CLASS_ORDER), set(expected_classes_for_role("base")))
        self.assertEqual(
            set(SPECIALIST_YOLO_CLASS_ORDER),
            set(expected_classes_for_role("specialist")),
        )
        self.assertEqual(class_order_for_role("BASE"), BASE_YOLO_CLASS_ORDER)
        self.assertEqual(class_order_for_role("specialist"), SPECIALIST_YOLO_CLASS_ORDER)
        self.assertEqual(class_order_for_role("unknown"), ())

    def test_specialist_yolo_class_index_mapping_is_locked(self):
        # Taxonomy 1.1 replaced smartwatch with wrist_device in place at index 0;
        # this must never silently renumber earbud/tablet/paper_note/calculator.
        self.assertEqual(
            SPECIALIST_YOLO_CLASS_ORDER,
            ("wrist_device", "earbud", "tablet", "paper_note", "calculator"),
        )

    def test_base_export_materializes_images_labels_yaml_and_provenance(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            train_bytes = b"synthetic-train-image"
            val_bytes = b"synthetic-validation-image"
            self._write_image(root, "source/train.jpg", train_bytes)
            self._write_image(root, "source/val.jpg", val_bytes)

            train = self._write_manifest(
                root,
                "train.json",
                _manifest(
                    "base",
                    "train",
                    [
                        _sample(
                            "sample-train",
                            "group-train",
                            "source/train.jpg",
                            [_annotation("ann-person", "person")],
                        )
                    ],
                ),
            )
            validation = self._write_manifest(
                root,
                "validation.json",
                _manifest(
                    "base",
                    "validation",
                    [
                        _sample(
                            "sample-validation",
                            "group-validation",
                            "source/val.jpg",
                            [],
                            negative_tags=["hand_without_phone"],
                        )
                    ],
                ),
            )
            output = root / "export"

            result = export_training_package([train, validation], output)

            self.assertTrue(result["ok"])
            self.assertEqual(result["model_role"], "base")
            self.assertEqual(result["class_count"], len(BASE_YOLO_CLASS_ORDER))
            self.assertEqual(result["sample_count"], 2)
            self.assertEqual(result["annotation_count"], 1)

            train_image = output / "images/train/sample-train.jpg"
            train_label = output / "labels/train/sample-train.txt"
            val_image = output / "images/validation/sample-validation.jpg"
            val_label = output / "labels/validation/sample-validation.txt"
            self.assertEqual(train_image.read_bytes(), train_bytes)
            self.assertEqual(val_image.read_bytes(), val_bytes)
            self.assertEqual(train_label.read_text(encoding="utf-8"), "0 0.25 0.4 0.3 0.4\n")
            self.assertEqual(val_label.read_text(encoding="utf-8"), "")

            yaml_text = (output / "dataset.yaml").read_text(encoding="utf-8")
            self.assertIn("train: images/train", yaml_text)
            self.assertIn("val: images/validation", yaml_text)
            self.assertNotIn("test: images/test", yaml_text)
            self.assertIn("  0: person", yaml_text)
            self.assertIn("  7: book", yaml_text)

            manifest = json.loads((output / "export_manifest.json").read_text(encoding="utf-8"))
            self.assertEqual(manifest["dataset_id"], "e1-dataset")
            self.assertEqual(manifest["model_role"], "base")
            self.assertEqual(
                [item["canonical_object_id"] for item in manifest["class_map"]],
                list(BASE_YOLO_CLASS_ORDER),
            )
            train_record = next(
                item for item in manifest["samples"] if item["sample_id"] == "sample-train"
            )
            self.assertEqual(train_record["source_group_id"], "group-train")
            self.assertEqual(
                train_record["source_image_sha256"], hashlib.sha256(train_bytes).hexdigest()
            )
            negative_record = next(
                item
                for item in manifest["samples"]
                if item["sample_id"] == "sample-validation"
            )
            self.assertEqual(negative_record["negative_tags"], ["hand_without_phone"])
            self.assertEqual(negative_record["annotation_count"], 0)

    def test_specialist_export_uses_specialist_class_order(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            self._write_image(root, "train.jpg", b"train")
            self._write_image(root, "validation.jpg", b"validation")
            train = self._write_manifest(
                root,
                "train.json",
                _manifest(
                    "specialist",
                    "train",
                    [
                        _sample(
                            "s-train",
                            "g-train",
                            "train.jpg",
                            [_annotation("ann-watch", "wrist_device")],
                        )
                    ],
                ),
            )
            validation = self._write_manifest(
                root,
                "validation.json",
                _manifest(
                    "specialist",
                    "validation",
                    [
                        _sample(
                            "s-val",
                            "g-val",
                            "validation.jpg",
                            [_annotation("ann-calc", "calculator")],
                        )
                    ],
                ),
            )
            output = root / "specialist-export"

            result = export_training_package([train, validation], output)

            self.assertTrue(result["ok"])
            self.assertEqual(result["model_role"], "specialist")
            self.assertEqual(
                (output / "labels/train/s-train.txt").read_text(encoding="utf-8"),
                "0 0.25 0.4 0.3 0.4\n",
            )
            self.assertEqual(
                (output / "labels/validation/s-val.txt").read_text(encoding="utf-8"),
                "4 0.25 0.4 0.3 0.4\n",
            )

    def test_cross_split_source_group_leakage_blocks_export(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            self._write_image(root, "train.jpg", b"train")
            self._write_image(root, "val.jpg", b"val")
            train = self._write_manifest(
                root,
                "train.json",
                _manifest(
                    "base",
                    "train",
                    [_sample("train", "shared", "train.jpg", [_annotation("a1", "person")])],
                ),
            )
            validation = self._write_manifest(
                root,
                "validation.json",
                _manifest(
                    "base",
                    "validation",
                    [_sample("val", "shared", "val.jpg", [_annotation("a2", "person")])],
                ),
            )
            output = root / "export"

            result = export_training_package([train, validation], output)

            self.assertFalse(result["ok"])
            self.assertFalse(output.exists())
            self.assertIn(
                "source_group_split_leakage",
                {issue["code"] for issue in result["issues"]},
            )

    def test_mixed_base_and_specialist_manifests_are_rejected(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            self._write_image(root, "base.jpg", b"base")
            self._write_image(root, "specialist.jpg", b"specialist")
            train = self._write_manifest(
                root,
                "train.json",
                _manifest(
                    "base",
                    "train",
                    [_sample("base", "g1", "base.jpg", [_annotation("a1", "person")])],
                ),
            )
            validation = self._write_manifest(
                root,
                "validation.json",
                _manifest(
                    "specialist",
                    "validation",
                    [
                        _sample(
                            "specialist",
                            "g2",
                            "specialist.jpg",
                            [_annotation("a2", "earbud")],
                        )
                    ],
                ),
            )

            result = export_training_package([train, validation], root / "export")

            self.assertFalse(result["ok"])
            self.assertIn("mixed_model_role", {issue["code"] for issue in result["issues"]})

    def test_missing_source_image_fails_closed_and_cleans_staging(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            self._write_image(root, "val.jpg", b"val")
            train = self._write_manifest(
                root,
                "train.json",
                _manifest(
                    "base",
                    "train",
                    [
                        _sample(
                            "missing",
                            "g1",
                            "does-not-exist.jpg",
                            [_annotation("a1", "person")],
                        )
                    ],
                ),
            )
            validation = self._write_manifest(
                root,
                "validation.json",
                _manifest(
                    "base",
                    "validation",
                    [_sample("val", "g2", "val.jpg", [_annotation("a2", "person")])],
                ),
            )
            output = root / "export"

            with self.assertRaises(E1TrainingExportInputError) as raised:
                export_training_package([train, validation], output)

            self.assertEqual(raised.exception.code, "missing_source_image")
            self.assertFalse(output.exists())
            self.assertFalse(any(path.name.startswith(".export.staging-") for path in root.iterdir()))

    def test_existing_output_is_never_overwritten(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            output = root / "export"
            output.mkdir()
            sentinel = output / "keep.txt"
            sentinel.write_text("do not replace", encoding="utf-8")

            with self.assertRaises(E1TrainingExportInputError) as raised:
                export_training_package([], output)

            self.assertEqual(raised.exception.code, "no_manifests")
            self.assertEqual(sentinel.read_text(encoding="utf-8"), "do not replace")

    def test_missing_validation_split_is_rejected_before_materialization(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            self._write_image(root, "train.jpg", b"train")
            train = self._write_manifest(
                root,
                "train.json",
                _manifest(
                    "base",
                    "train",
                    [_sample("train", "g1", "train.jpg", [_annotation("a1", "person")])],
                ),
            )

            result = export_training_package([train], root / "export")

            self.assertFalse(result["ok"])
            self.assertIn(
                "missing_required_split",
                {issue["code"] for issue in result["issues"]},
            )

    def test_cli_returns_machine_readable_failure(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            output_dir = root / "export"
            stream = io.StringIO()

            exit_code = main(
                ["--output", str(output_dir), str(root / "missing.json")],
                stdout=stream,
            )
            payload = json.loads(stream.getvalue())

            self.assertEqual(exit_code, 1)
            self.assertFalse(payload["ok"])
            self.assertIn("manifest_read_error", {issue["code"] for issue in payload["issues"]})


if __name__ == "__main__":
    unittest.main()

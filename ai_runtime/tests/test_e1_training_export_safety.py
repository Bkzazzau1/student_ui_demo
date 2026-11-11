import json
from pathlib import Path
import tempfile
import unittest

from ai_runtime.e1_training_export import (
    E1TrainingExportInputError,
    export_training_package,
)


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


def _sample(sample_id: str, group_id: str, image_path: str, annotation_id: str):
    return {
        "sample_id": sample_id,
        "source_group_id": group_id,
        "image_path": image_path,
        "width": 1280,
        "height": 720,
        "negative_tags": [],
        "annotations": [_annotation(annotation_id, "person")],
    }


def _manifest(split: str, sample):
    return {
        "schema_version": "1.0",
        "taxonomy_version": "1.1",
        "dataset_id": "e1-base-dataset",
        "dataset_version": "v1",
        "model_role": "base",
        "split": split,
        "samples": [sample],
    }


class E1TrainingExportSafetyTests(unittest.TestCase):
    def _write_inputs(self, root: Path, *, include_test: bool = False):
        paths = []
        for split in ("train", "validation", "test"):
            if split == "test" and not include_test:
                continue
            image = root / f"{split}.jpg"
            image.write_bytes(f"synthetic-{split}".encode("utf-8"))
            manifest = root / f"{split}.json"
            manifest.write_text(
                json.dumps(
                    _manifest(
                        split,
                        _sample(
                            f"sample-{split}",
                            f"group-{split}",
                            image.name,
                            f"ann-{split}",
                        ),
                    )
                ),
                encoding="utf-8",
            )
            paths.append(manifest)
        return paths

    def test_valid_inputs_cannot_overwrite_existing_export_directory(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            manifests = self._write_inputs(root)
            output = root / "export"
            output.mkdir()
            sentinel = output / "keep.txt"
            sentinel.write_text("preserve-me", encoding="utf-8")

            with self.assertRaises(E1TrainingExportInputError) as raised:
                export_training_package(manifests, output)

            self.assertEqual(raised.exception.code, "output_exists")
            self.assertEqual(sentinel.read_text(encoding="utf-8"), "preserve-me")
            self.assertEqual(sorted(path.name for path in output.iterdir()), ["keep.txt"])

    def test_optional_test_split_is_materialized_and_declared_in_yaml(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            manifests = self._write_inputs(root, include_test=True)
            output = root / "export"

            result = export_training_package(manifests, output)

            self.assertTrue(result["ok"])
            self.assertEqual(result["splits"]["test"]["sample_count"], 1)
            self.assertTrue((output / "images/test/sample-test.jpg").is_file())
            self.assertTrue((output / "labels/test/sample-test.txt").is_file())
            yaml_text = (output / "dataset.yaml").read_text(encoding="utf-8")
            self.assertIn("test: images/test", yaml_text)

    def test_path_like_sample_id_is_rejected_before_materialization(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            manifests = self._write_inputs(root)
            train = json.loads(manifests[0].read_text(encoding="utf-8"))
            train["samples"][0]["sample_id"] = "../escape"
            manifests[0].write_text(json.dumps(train), encoding="utf-8")
            output = root / "export"

            with self.assertRaises(E1TrainingExportInputError) as raised:
                export_training_package(manifests, output)

            self.assertEqual(raised.exception.code, "unsafe_sample_id")
            self.assertFalse(output.exists())
            self.assertFalse((root.parent / "escape.jpg").exists())

    def test_windows_reserved_sample_id_is_rejected(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            manifests = self._write_inputs(root)
            train = json.loads(manifests[0].read_text(encoding="utf-8"))
            train["samples"][0]["sample_id"] = "CON"
            manifests[0].write_text(json.dumps(train), encoding="utf-8")

            with self.assertRaises(E1TrainingExportInputError) as raised:
                export_training_package(manifests, root / "export")

            self.assertEqual(raised.exception.code, "unsafe_sample_id")


if __name__ == "__main__":
    unittest.main()

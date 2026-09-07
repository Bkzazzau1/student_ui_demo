import copy
import io
import json
from pathlib import Path
import tempfile
import unittest

from ai_runtime.e1_collection_split import (
    build_split_plan,
    create_split_plan_file,
    main,
    split_plan_is_group_disjoint,
)


def _collection() -> dict:
    records = []
    group_sizes = {
        "session-a": 4,
        "session-b": 3,
        "session-c": 2,
        "session-d": 2,
        "session-e": 1,
        "session-f": 1,
    }
    for group_id, count in group_sizes.items():
        for index in range(count):
            records.append(
                {
                    "source_group_id": group_id,
                    "image_path": f"images\\{group_id}\\frame-{index:04d}.jpg",
                    "width": 1920,
                    "height": 1080,
                }
            )
    return {
        "collection_schema_version": "1.0",
        "dataset_id": "e1-controlled-pilot",
        "dataset_version": "2026.09.1",
        "model_role": "base",
        "split_seed": "pilot-seed-001",
        "split_weights": {
            "train": 8,
            "validation": 1,
            "test": 1,
        },
        "records": records,
    }


class BuildSplitPlanTests(unittest.TestCase):
    def test_plan_keeps_every_source_group_inside_one_split(self) -> None:
        plan, issues = build_split_plan(_collection())

        self.assertEqual(issues, [])
        self.assertIsNotNone(plan)
        assert plan is not None
        self.assertTrue(split_plan_is_group_disjoint(plan))

        splits_by_group: dict[str, set[str]] = {}
        for record in plan["records"]:
            splits_by_group.setdefault(record["source_group_id"], set()).add(record["split"])
        self.assertTrue(all(len(splits) == 1 for splits in splits_by_group.values()))
        self.assertEqual(plan["summary"]["record_count"], 13)
        self.assertEqual(plan["summary"]["source_group_count"], 6)

    def test_same_input_and_seed_are_deterministic(self) -> None:
        first, first_issues = build_split_plan(_collection())
        second, second_issues = build_split_plan(_collection())

        self.assertEqual(first_issues, [])
        self.assertEqual(second_issues, [])
        self.assertEqual(first, second)

    def test_record_order_does_not_change_group_assignment(self) -> None:
        original = _collection()
        reordered = copy.deepcopy(original)
        reordered["records"].reverse()

        first, first_issues = build_split_plan(original)
        second, second_issues = build_split_plan(reordered)

        self.assertEqual(first_issues, [])
        self.assertEqual(second_issues, [])
        assert first is not None and second is not None
        self.assertEqual(first["assignments"], second["assignments"])
        self.assertEqual(first["records"], second["records"])

    def test_no_split_ratio_is_invented_when_weights_are_missing(self) -> None:
        collection = _collection()
        del collection["split_weights"]

        plan, issues = build_split_plan(collection)

        self.assertIsNone(plan)
        self.assertIn("invalid_split_weights", {issue["code"] for issue in issues})

    def test_each_weight_must_be_explicit(self) -> None:
        collection = _collection()
        del collection["split_weights"]["test"]

        plan, issues = build_split_plan(collection)

        self.assertIsNone(plan)
        self.assertIn("invalid_split_weight", {issue["code"] for issue in issues})

    def test_zero_weight_split_receives_no_groups(self) -> None:
        collection = _collection()
        collection["split_weights"] = {
            "train": 4,
            "validation": 1,
            "test": 0,
        }

        plan, issues = build_split_plan(collection)

        self.assertEqual(issues, [])
        assert plan is not None
        self.assertEqual(plan["summary"]["splits"]["test"]["record_count"], 0)
        self.assertEqual(plan["summary"]["splits"]["test"]["source_group_count"], 0)
        self.assertNotIn("test", {item["split"] for item in plan["assignments"]})

    def test_windows_paths_are_normalized_before_output(self) -> None:
        plan, issues = build_split_plan(_collection())

        self.assertEqual(issues, [])
        assert plan is not None
        self.assertTrue(all("\\" not in record["image_path"] for record in plan["records"]))
        self.assertTrue(all(record["image_path"].startswith("images/") for record in plan["records"]))

    def test_duplicate_normalized_image_path_is_rejected(self) -> None:
        collection = _collection()
        duplicate = copy.deepcopy(collection["records"][0])
        duplicate["image_path"] = duplicate["image_path"].replace("\\", "/")
        duplicate["source_group_id"] = "different-group"
        collection["records"].append(duplicate)

        plan, issues = build_split_plan(collection)

        self.assertIsNone(plan)
        self.assertIn("duplicate_image_path", {issue["code"] for issue in issues})

    def test_missing_source_group_is_rejected_not_inferred(self) -> None:
        collection = _collection()
        collection["records"][0]["source_group_id"] = ""

        plan, issues = build_split_plan(collection)

        self.assertIsNone(plan)
        self.assertIn("missing_source_group_id", {issue["code"] for issue in issues})

    def test_unknown_weight_key_is_rejected(self) -> None:
        collection = _collection()
        collection["split_weights"]["holdout"] = 1

        plan, issues = build_split_plan(collection)

        self.assertIsNone(plan)
        self.assertIn("unknown_split_weight", {issue["code"] for issue in issues})


class CollectionSplitCliTests(unittest.TestCase):
    def _write_collection(self, directory: Path, value: dict | None = None) -> Path:
        path = directory / "collection.json"
        path.write_text(json.dumps(value or _collection()), encoding="utf-8")
        return path

    def test_cli_writes_deterministic_group_safe_plan(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            directory = Path(temporary_directory)
            input_path = self._write_collection(directory)
            output_path = directory / "plans" / "split-plan.json"
            stdout = io.StringIO()

            exit_code = main(
                [str(input_path), str(output_path), "--pretty"],
                stdout=stdout,
            )

            self.assertEqual(exit_code, 0)
            result = json.loads(stdout.getvalue())
            self.assertTrue(result["ok"])
            plan = json.loads(output_path.read_text(encoding="utf-8"))
            self.assertTrue(split_plan_is_group_disjoint(plan))
            self.assertEqual(plan["split_seed"], "pilot-seed-001")

    def test_existing_output_requires_force(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            directory = Path(temporary_directory)
            input_path = self._write_collection(directory)
            output_path = directory / "split-plan.json"
            output_path.write_text("keep-me", encoding="utf-8")

            blocked = create_split_plan_file(input_path, output_path)
            self.assertFalse(blocked["ok"])
            self.assertEqual(blocked["issues"][0]["code"], "output_exists")
            self.assertEqual(output_path.read_text(encoding="utf-8"), "keep-me")

            replaced = create_split_plan_file(input_path, output_path, force=True)
            self.assertTrue(replaced["ok"])
            self.assertTrue(split_plan_is_group_disjoint(json.loads(output_path.read_text(encoding="utf-8"))))

    def test_invalid_json_writes_nothing(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            directory = Path(temporary_directory)
            input_path = directory / "broken.json"
            output_path = directory / "split-plan.json"
            input_path.write_text("{broken", encoding="utf-8")

            result = create_split_plan_file(input_path, output_path)

            self.assertFalse(result["ok"])
            self.assertEqual(result["issues"][0]["code"], "invalid_json")
            self.assertFalse(output_path.exists())

    def test_input_and_output_must_be_different(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            directory = Path(temporary_directory)
            input_path = self._write_collection(directory)

            result = create_split_plan_file(input_path, input_path, force=True)

            self.assertFalse(result["ok"])
            self.assertEqual(result["issues"][0]["code"], "input_output_same")


if __name__ == "__main__":
    unittest.main()

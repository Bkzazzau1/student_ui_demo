from __future__ import annotations

from copy import deepcopy
import io
import json
from pathlib import Path
import tempfile
import unittest

from ai_runtime.e1_annotation_ingest import build_dataset_manifest
from ai_runtime.e1_coco_source import (
    COCO_TO_E1_BASE,
    LABEL_QUALITY,
    E1CocoSourceError,
    build_inventory,
    build_staging,
    main,
)
from ai_runtime.e1_collection_split import build_split_plan
from ai_runtime.e1_training_readiness import BASE_TRAINABLE_CLASSES, validate_split_disjointness


_CATEGORIES = [
    {"id": 1, "name": "person"}, {"id": 2, "name": "bicycle"}, {"id": 62, "name": "chair"},
    {"id": 72, "name": "tv"}, {"id": 73, "name": "laptop"}, {"id": 74, "name": "mouse"},
    {"id": 75, "name": "remote"}, {"id": 76, "name": "keyboard"}, {"id": 77, "name": "cell phone"},
    {"id": 84, "name": "book"},
]


def _image(image_id, license_id=4, width=100, height=80):
    return {"id": image_id, "file_name": f"{image_id:012d}.jpg", "width": width, "height": height,
            "license": license_id, "coco_url": f"http://example.invalid/{image_id}.jpg", "flickr_url": ""}


def _ann(ann_id, image_id, category_id, bbox, iscrowd=0):
    return {"id": ann_id, "image_id": image_id, "category_id": category_id, "bbox": bbox, "iscrowd": iscrowd}


def instances():
    images = [_image(i) for i in range(1, 13)]
    images[8]["license"] = 1  # image 9: license not allowed
    anns = [
        _ann(1, 1, 77, [10.37, 20.11, 30.29, 15.73]),  # phone, float box inside image (not clipped)
        _ann(2, 1, 1, [0, 0, 50, 80]),               # person
        _ann(3, 2, 1, [5, 5, 40, 60]),               # person only
        _ann(4, 3, 1, [5, 5, 40, 60]),               # person only
        _ann(5, 4, 62, [1, 1, 10, 10]),              # background (chair only)
        _ann(6, 5, 1, [0, 0, 90, 70], iscrowd=1),    # crowd person -> excluded
        _ann(7, 6, 72, [90, 10, 10.6, 20]),          # tv overshoots 0.6 px -> clipped
        _ann(8, 7, 84, [95, 10, 20, 20]),            # book far outside -> excluded
        _ann(9, 8, 74, [10, 10, 0.4, 5]),            # degenerate mouse -> excluded
        _ann(10, 9, 73, [10, 10, 30, 20]),           # laptop but license 1 -> excluded
        _ann(11, 10, 75, [10, 10, 5, 5]),            # remote
        _ann(12, 10, 75, [10, 10, 5, 5]),            # exact duplicate remote -> deduped
        _ann(13, 11, 2, [1, 1, 10, 10]),             # background (bicycle only)
        # image 12 has no annotations at all -> excluded_unannotated_image
    ]
    return {"categories": deepcopy(_CATEGORIES), "images": images, "annotations": anns,
            "licenses": [{"id": 1, "name": "BY-NC-SA", "url": "u1"}, {"id": 4, "name": "BY", "url": "u4"}]}


def selection(**overrides):
    base = {"selection_schema_version": "1.0", "dataset_id": "e1-base-coco-test", "dataset_version": "t1",
            "coco_split": "train2017", "image_dir": "train2017", "selection_seed": "sel-seed",
            "split_seed": "split-seed", "split_weights": {"train": 1, "validation": 0, "test": 0},
            "allowed_license_ids": [4], "person_only_limit": 1, "background_limit": 1}
    base.update(overrides)
    return base


class MappingTests(unittest.TestCase):
    def test_mapping_is_exact_and_covers_frozen_base_classes(self):
        self.assertEqual(frozenset(COCO_TO_E1_BASE.values()), BASE_TRAINABLE_CLASSES)
        self.assertEqual(COCO_TO_E1_BASE["cell phone"], "phone")
        self.assertEqual(COCO_TO_E1_BASE["tv"], "television")

    def test_missing_category_fails_closed(self):
        data = instances()
        data["categories"] = [c for c in data["categories"] if c["name"] != "book"]
        with self.assertRaises(E1CocoSourceError) as caught:
            build_inventory(data, selection())
        self.assertEqual(caught.exception.code, "category_mapping_mismatch")


class InventoryTests(unittest.TestCase):
    def test_selection_tiers_and_exclusions(self):
        inventory = build_inventory(instances(), selection())
        info = inventory["coco_selection"]
        self.assertEqual(info["available"], {"non_person_target": 3, "person_only": 2, "background": 2})
        self.assertEqual(info["selected"], {"non_person_target": 3, "person_only": 1, "background": 1})
        outcomes = info["image_outcomes"]
        for reason in ("excluded_crowd_target", "excluded_target_box_outside_image",
                       "excluded_degenerate_target_box", "excluded_license_not_allowed",
                       "excluded_unannotated_image"):
            self.assertEqual(outcomes[reason], 1, reason)
        ids = {r["source_group_id"] for r in inventory["records"]}
        self.assertTrue({"coco2017:train2017:1", "coco2017:train2017:6", "coco2017:train2017:10"} <= ids)
        self.assertEqual(len(ids), 5)
        self.assertEqual(inventory["records"][0]["image_path"], "train2017/000000000001.jpg")

    def test_sampling_is_deterministic_and_seeded(self):
        first = build_inventory(instances(), selection())
        self.assertEqual(first, build_inventory(instances(), selection()))
        seeds = {tuple(r["source_group_id"] for r in build_inventory(instances(), selection(selection_seed=s))["records"])
                 for s in ("a", "b", "c", "d", "e", "f")}
        self.assertGreater(len(seeds), 1)

    def test_selection_requires_explicit_values(self):
        for broken in (selection(allowed_license_ids=[]), selection(person_only_limit=None),
                       selection(coco_split="test2017"), selection(selection_seed="")):
            with self.assertRaises(E1CocoSourceError):
                build_inventory(instances(), broken)


class StagingTests(unittest.TestCase):
    def _plan(self, sel):
        plan, issues = build_split_plan(build_inventory(instances(), sel))
        self.assertEqual(issues, [])
        return plan

    def test_end_to_end_into_canonical_ingest(self):
        sel = selection()
        staging = build_staging(instances(), self._plan(sel), "train", sel["allowed_license_ids"])
        audit = staging["open_dataset_audit"]
        self.assertEqual(audit["label_quality"], LABEL_QUALITY)
        self.assertFalse(audit["is_gold"])
        self.assertFalse(audit["is_teacher_consensus"])
        self.assertEqual(audit["boxes_clipped_to_image"], 1)
        self.assertEqual(audit["annotation_counts"]["remote"], 1)  # duplicate collapsed
        by_group = {r["source_group_id"]: r for r in staging["records"]}
        tv = by_group["coco2017:train2017:6"]["annotations"][0]
        self.assertAlmostEqual(tv["bbox_xywh_pixels"][0] + tv["bbox_xywh_pixels"][2], 100.0)
        self.assertEqual(by_group["coco2017:train2017:1"]["provenance"]["license"]["name"], "BY")
        phone = [a for a in by_group["coco2017:train2017:1"]["annotations"] if a["canonical_object_id"] == "phone"][0]
        self.assertEqual(phone["bbox_xywh_pixels"], [10.37, 20.11, 30.29, 15.73])  # COCO numbers kept exactly
        manifest, issues = build_dataset_manifest(staging)
        self.assertEqual(issues, ())
        self.assertEqual(manifest["split"], "train")
        backgrounds = [s for s in manifest["samples"] if not s["annotations"]]
        self.assertEqual(len(backgrounds), 1)

    def test_val2017_feeds_validation_and_test_without_leakage(self):
        sel = selection(coco_split="val2017", image_dir="val2017", person_only_limit=2, background_limit=2,
                        split_weights={"train": 0, "validation": 1, "test": 1})
        plan = self._plan(sel)
        manifests = []
        for split in ("validation", "test"):
            staging = build_staging(instances(), plan, split, sel["allowed_license_ids"])
            manifest, issues = build_dataset_manifest(staging)
            self.assertEqual(issues, ())
            manifests.append(manifest)
        self.assertEqual(validate_split_disjointness(manifests), ())

    def test_rejects_foreign_or_mismatched_plans(self):
        sel = selection()
        plan = self._plan(sel)
        foreign = deepcopy(plan)
        foreign["records"][0]["source_group_id"] = "session-001"
        foreign["assignments"][0]["source_group_id"] = "session-001"
        with self.assertRaises(E1CocoSourceError):
            build_staging(instances(), foreign, "train", [4])
        resized = deepcopy(plan)
        resized["records"][0]["width"] = 999
        with self.assertRaises(E1CocoSourceError) as caught:
            build_staging(instances(), resized, "train", [4])
        self.assertEqual(caught.exception.code, "plan_instances_mismatch")
        with self.assertRaises(E1CocoSourceError) as caught:
            build_staging(instances(), plan, "validation", [4])
        self.assertEqual(caught.exception.code, "empty_split")


class CliTests(unittest.TestCase):
    def test_cli_refuses_overwrite(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "instances.json").write_text(json.dumps(instances()), encoding="utf-8")
            (root / "selection.json").write_text(json.dumps(selection()), encoding="utf-8")
            args = ["inventory", "--instances", str(root / "instances.json"),
                    "--selection", str(root / "selection.json"), "--output", str(root / "inv.json")]
            self.assertEqual(main(args, stdout=io.StringIO()), 0)
            out = io.StringIO()
            self.assertEqual(main(args, stdout=out), 1)
            self.assertEqual(json.loads(out.getvalue())["error"]["code"], "output_exists")


if __name__ == "__main__":
    unittest.main()

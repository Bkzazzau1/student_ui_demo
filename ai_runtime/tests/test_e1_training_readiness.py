import unittest

from ai_runtime.e1_training_readiness import (
    BASE_TRAINABLE_CLASSES,
    SPECIALIST_TRAINABLE_CLASSES,
    calibration_complete,
    expected_classes_for_role,
    validate_dataset_manifest,
    validate_evaluation_report,
    validate_split_disjointness,
)


def _sample(canonical_object_id: str, *, sample_id: str = "sample-1", group_id: str = "capture-1"):
    return {
        "sample_id": sample_id,
        "source_group_id": group_id,
        "image_path": f"images/{sample_id}.jpg",
        "width": 1280,
        "height": 720,
        "negative_tags": [],
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


def _manifest(role: str, split: str, sample):
    return {
        "schema_version": "1.0",
        "taxonomy_version": "1.0",
        "dataset_id": f"e1-{role}-dataset",
        "dataset_version": "v1",
        "model_role": role,
        "split": split,
        "samples": [sample],
    }


def _evaluation_report(role: str):
    expected = expected_classes_for_role(role)
    class_metrics = {
        canonical_id: {
            "support": 10,
            "precision": 0.8,
            "recall": 0.8,
            "f1": 0.8,
            "ap50": 0.8,
            "ap50_95": 0.7,
        }
        for canonical_id in expected
    }
    calibration = {
        canonical_id: {"selected_confidence_threshold": None}
        for canonical_id in expected
    }
    return {
        "schema_version": "1.0",
        "taxonomy_version": "1.0",
        "model_id": f"e1-{role}",
        "model_version": "candidate-1",
        "evaluation_dataset_id": f"e1-{role}-heldout",
        "model_role": role,
        "evaluation_split": "validation",
        "class_metrics": class_metrics,
        "hard_negative_metrics": {
            "ordinary_watch": {
                "sample_count": 10,
                "false_positive_rate": 0.1,
            }
        },
        "calibration": calibration,
    }


class E1TrainingReadinessTests(unittest.TestCase):
    def test_frozen_training_roles_are_disjoint(self):
        self.assertEqual(
            BASE_TRAINABLE_CLASSES,
            frozenset(
                {
                    "person",
                    "phone",
                    "laptop",
                    "television",
                    "keyboard",
                    "mouse",
                    "remote",
                    "book",
                }
            ),
        )
        self.assertEqual(
            SPECIALIST_TRAINABLE_CLASSES,
            frozenset(
                {"smartwatch", "earbud", "tablet", "paper_note", "calculator"}
            ),
        )
        self.assertTrue(BASE_TRAINABLE_CLASSES.isdisjoint(SPECIALIST_TRAINABLE_CLASSES))

    def test_valid_base_and_specialist_manifests_pass(self):
        base = _manifest("base", "train", _sample("person"))
        specialist = _manifest(
            "specialist",
            "validation",
            _sample("earbud", sample_id="specialist-1", group_id="capture-2"),
        )
        self.assertEqual(validate_dataset_manifest(base), ())
        self.assertEqual(validate_dataset_manifest(specialist), ())

    def test_role_boundary_rejects_wrong_or_derived_classes(self):
        wrong_role = _manifest("base", "train", _sample("smartwatch"))
        derived = _manifest("base", "train", _sample("additional_person"))

        self.assertIn(
            "class_not_allowed_for_role",
            {issue.code for issue in validate_dataset_manifest(wrong_role)},
        )
        self.assertIn(
            "derived_class_not_trainable",
            {issue.code for issue in validate_dataset_manifest(derived)},
        )

    def test_invalid_geometry_is_rejected(self):
        sample = _sample("phone")
        sample["annotations"][0]["bbox_xywh_normalized"] = {
            "x": 0.9,
            "y": 0.1,
            "width": 0.2,
            "height": 0.2,
        }
        issues = validate_dataset_manifest(_manifest("base", "train", sample))
        self.assertIn("bbox_out_of_range", {issue.code for issue in issues})

    def test_source_groups_must_not_leak_across_splits(self):
        train = _manifest("base", "train", _sample("person", group_id="same-capture"))
        validation = _manifest(
            "base",
            "validation",
            _sample("person", sample_id="sample-2", group_id="same-capture"),
        )
        issues = validate_split_disjointness([train, validation])
        self.assertIn("source_group_split_leakage", {issue.code for issue in issues})

    def test_evaluation_contract_accepts_unselected_thresholds_but_is_not_complete(self):
        report = _evaluation_report("specialist")
        self.assertEqual(validate_evaluation_report(report), ())
        self.assertFalse(calibration_complete(report))

    def test_calibration_completes_only_with_evidence_backed_thresholds(self):
        report = _evaluation_report("base")
        for canonical_id in BASE_TRAINABLE_CLASSES:
            report["calibration"][canonical_id] = {
                "selected_confidence_threshold": 0.5,
                "selection_basis": "held-out calibration sweep",
                "calibration_dataset_id": "e1-base-calibration-v1",
            }

        self.assertEqual(validate_evaluation_report(report), ())
        self.assertTrue(calibration_complete(report))

    def test_training_split_cannot_be_used_as_evaluation_split(self):
        report = _evaluation_report("base")
        report["evaluation_split"] = "train"
        issues = validate_evaluation_report(report)
        self.assertIn("invalid_evaluation_split", {issue.code for issue in issues})


if __name__ == "__main__":
    unittest.main()

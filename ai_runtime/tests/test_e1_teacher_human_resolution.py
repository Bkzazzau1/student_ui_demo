import copy
import io
import json
from pathlib import Path
import tempfile
import unittest

from ai_runtime.e1_annotation_ingest import build_dataset_manifest
from ai_runtime.e1_teacher_human_resolution import (
    build_annotation_staging,
    main,
    resolve_files,
)


def _teacher_report() -> dict:
    return {
        "teacher_schema_version": "1.0",
        "packet_id": "packet-001",
        "model_role": "base",
        "image": {
            "image_path": "images/session-001/frame-0001.jpg",
            "width": 1000,
            "height": 500,
        },
        "policy": {
            "human_review_required": True,
            "teacher_agreement_is_ground_truth": False,
        },
        "summary": {"candidate_count": 2},
        "candidates": [
            {
                "candidate_id": "candidate-phone-001",
                "status": "teacher_agreement",
                "human_review_required": True,
                "suggested_decision": {
                    "decision": "canonical",
                    "canonical_object_id": "phone",
                },
                "teacher_votes": [],
            },
            {
                "candidate_id": "candidate-remote-001",
                "status": "needs_human_review",
                "human_review_required": True,
                "suggested_decision": None,
                "teacher_votes": [],
            },
        ],
    }


def _human_review() -> dict:
    return {
        "review_schema_version": "1.0",
        "review_packet_id": "packet-001",
        "dataset_id": "e1-controlled-pilot",
        "dataset_version": "2026.09.1",
        "split": "train",
        "source_group_id": "session-001",
        "image": {
            "image_path": "images/session-001/frame-0001.jpg",
            "width": 1000,
            "height": 500,
        },
        "negative_tags": ["ordinary_watch", "ordinary_watch"],
        "candidate_reviews": [
            {
                "candidate_id": "candidate-phone-001",
                "reviewer_id": "reviewer-001",
                "decision": "canonical",
                "canonical_object_id": "phone",
                "bbox_xywh_normalized": [0.1, 0.2, 0.2, 0.3],
            },
            {
                "candidate_id": "candidate-remote-001",
                "reviewer_id": "reviewer-001",
                "decision": "no_object",
            },
        ],
    }


class BuildAnnotationStagingTests(unittest.TestCase):
    def test_explicit_human_review_emits_ingest_compatible_staging(self) -> None:
        staging, issues = build_annotation_staging(_teacher_report(), _human_review())

        self.assertEqual(issues, ())
        self.assertIsNotNone(staging)
        assert staging is not None
        self.assertEqual(staging["model_role"], "base")
        record = staging["records"][0]
        self.assertEqual(record["source_group_id"], "session-001")
        self.assertEqual(record["negative_tags"], ["ordinary_watch"])
        self.assertEqual(
            record["annotations"],
            [
                {
                    "canonical_object_id": "phone",
                    "bbox_xywh_normalized": [0.1, 0.2, 0.2, 0.3],
                }
            ],
        )

        manifest, ingest_issues = build_dataset_manifest(staging)
        self.assertEqual(ingest_issues, ())
        self.assertIsNotNone(manifest)

    def test_teacher_suggestion_is_not_authoritative(self) -> None:
        review = _human_review()
        review["candidate_reviews"][0]["canonical_object_id"] = "remote"

        staging, issues = build_annotation_staging(_teacher_report(), review)

        self.assertEqual(issues, ())
        assert staging is not None
        self.assertEqual(
            staging["records"][0]["annotations"][0]["canonical_object_id"],
            "remote",
        )

    def test_unresolved_candidate_blocks_staging(self) -> None:
        review = _human_review()
        review["candidate_reviews"][1]["decision"] = "unresolved"

        staging, issues = build_annotation_staging(_teacher_report(), review)

        self.assertIsNone(staging)
        self.assertIn("unresolved_candidate", {issue.code for issue in issues})

    def test_missing_candidate_review_blocks_partial_export(self) -> None:
        review = _human_review()
        review["candidate_reviews"] = review["candidate_reviews"][:1]

        staging, issues = build_annotation_staging(_teacher_report(), review)

        self.assertIsNone(staging)
        self.assertIn("missing_candidate_reviews", {issue.code for issue in issues})

    def test_unknown_candidate_is_rejected(self) -> None:
        review = _human_review()
        review["candidate_reviews"][1]["candidate_id"] = "invented-candidate"

        staging, issues = build_annotation_staging(_teacher_report(), review)

        self.assertIsNone(staging)
        codes = {issue.code for issue in issues}
        self.assertIn("unknown_candidate_id", codes)
        self.assertIn("missing_candidate_reviews", codes)

    def test_source_group_is_required_and_never_inferred(self) -> None:
        review = _human_review()
        review["source_group_id"] = ""

        staging, issues = build_annotation_staging(_teacher_report(), review)

        self.assertIsNone(staging)
        self.assertIn("missing_source_group_id", {issue.code for issue in issues})

    def test_image_identity_must_match_teacher_report(self) -> None:
        review = _human_review()
        review["image"]["image_path"] = "images/other/frame.jpg"

        staging, issues = build_annotation_staging(_teacher_report(), review)

        self.assertIsNone(staging)
        self.assertIn("image_path_mismatch", {issue.code for issue in issues})

    def test_alias_is_not_guessed(self) -> None:
        review = _human_review()
        review["candidate_reviews"][0]["canonical_object_id"] = "cell phone"

        staging, issues = build_annotation_staging(_teacher_report(), review)

        self.assertIsNone(staging)
        self.assertIn("class_not_allowed_for_role", {issue.code for issue in issues})

    def test_specialist_class_cannot_enter_base_review(self) -> None:
        review = _human_review()
        review["candidate_reviews"][0]["canonical_object_id"] = "smartwatch"

        staging, issues = build_annotation_staging(_teacher_report(), review)

        self.assertIsNone(staging)
        self.assertIn("class_not_allowed_for_role", {issue.code for issue in issues})

    def test_canonical_decision_requires_valid_geometry(self) -> None:
        review = _human_review()
        review["candidate_reviews"][0]["bbox_xywh_normalized"] = [0.9, 0.2, 0.2, 0.3]

        staging, issues = build_annotation_staging(_teacher_report(), review)

        self.assertIsNone(staging)
        self.assertIn("invalid_bbox", {issue.code for issue in issues})

    def test_noncanonical_decision_cannot_smuggle_geometry(self) -> None:
        review = _human_review()
        review["candidate_reviews"][1]["bbox_xywh_normalized"] = [0.1, 0.1, 0.2, 0.2]

        staging, issues = build_annotation_staging(_teacher_report(), review)

        self.assertIsNone(staging)
        self.assertIn("unexpected_bbox", {issue.code for issue in issues})

    def test_reviewer_identity_is_explicit(self) -> None:
        review = _human_review()
        review["candidate_reviews"][0]["reviewer_id"] = ""

        staging, issues = build_annotation_staging(_teacher_report(), review)

        self.assertIsNone(staging)
        self.assertIn("missing_reviewer_id", {issue.code for issue in issues})

    def test_exclude_candidate_is_allowed_without_annotation(self) -> None:
        review = _human_review()
        review["candidate_reviews"][1]["decision"] = "exclude_candidate"

        staging, issues = build_annotation_staging(_teacher_report(), review)

        self.assertEqual(issues, ())
        assert staging is not None
        self.assertEqual(len(staging["records"][0]["annotations"]), 1)


class HumanResolutionCliTests(unittest.TestCase):
    def test_cli_writes_staging_only_after_valid_review(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            directory = Path(temporary_directory)
            teacher_path = directory / "teacher.json"
            review_path = directory / "review.json"
            output_path = directory / "staging.json"
            teacher_path.write_text(json.dumps(_teacher_report()), encoding="utf-8")
            review_path.write_text(json.dumps(_human_review()), encoding="utf-8")
            stdout = io.StringIO()

            exit_code = main(
                [str(teacher_path), str(review_path), str(output_path), "--pretty"],
                stdout=stdout,
            )

            self.assertEqual(exit_code, 0)
            result = json.loads(stdout.getvalue())
            self.assertTrue(result["ok"])
            self.assertTrue(output_path.exists())
            emitted = json.loads(output_path.read_text(encoding="utf-8"))
            manifest, issues = build_dataset_manifest(emitted)
            self.assertEqual(issues, ())
            self.assertIsNotNone(manifest)

    def test_invalid_review_never_creates_output(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            directory = Path(temporary_directory)
            teacher_path = directory / "teacher.json"
            review_path = directory / "review.json"
            output_path = directory / "staging.json"
            review = _human_review()
            review["candidate_reviews"][0]["decision"] = "unresolved"
            review["candidate_reviews"][0].pop("canonical_object_id")
            review["candidate_reviews"][0].pop("bbox_xywh_normalized")
            teacher_path.write_text(json.dumps(_teacher_report()), encoding="utf-8")
            review_path.write_text(json.dumps(review), encoding="utf-8")

            result = resolve_files(teacher_path, review_path, output_path)

            self.assertFalse(result["ok"])
            self.assertFalse(output_path.exists())

    def test_existing_output_requires_force(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            directory = Path(temporary_directory)
            teacher_path = directory / "teacher.json"
            review_path = directory / "review.json"
            output_path = directory / "staging.json"
            teacher_path.write_text(json.dumps(_teacher_report()), encoding="utf-8")
            review_path.write_text(json.dumps(_human_review()), encoding="utf-8")
            output_path.write_text("keep", encoding="utf-8")

            blocked = resolve_files(teacher_path, review_path, output_path)
            self.assertFalse(blocked["ok"])
            self.assertEqual(output_path.read_text(encoding="utf-8"), "keep")

            replaced = resolve_files(
                teacher_path,
                review_path,
                output_path,
                force=True,
            )
            self.assertTrue(replaced["ok"])
            self.assertNotEqual(output_path.read_text(encoding="utf-8"), "keep")


if __name__ == "__main__":
    unittest.main()

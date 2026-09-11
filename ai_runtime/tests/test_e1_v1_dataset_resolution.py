import io
import json
from pathlib import Path
import tempfile
import unittest

from ai_runtime.e1_annotation_ingest import build_dataset_manifest
from ai_runtime.e1_teacher_consensus import evaluate_teacher_packet
from ai_runtime.e1_v1_dataset_resolution import (
    V1_DATASET_SCHEMA_VERSION,
    build_v1_annotation_staging,
    main,
    resolve_v1_files,
)


def _teacher_packet(*, canonical_id: str = "phone", role: str = "base") -> dict:
    return {
        "teacher_schema_version": "1.0",
        "packet_id": "packet-v1-001",
        "model_role": role,
        "image": {
            "image_path": "images/v1/source-001/frame-0001.jpg",
            "width": 1000,
            "height": 500,
        },
        "candidates": [
            {
                "candidate_id": "candidate-001",
                "teacher_votes": [
                    {
                        "teacher_id": "openai-01",
                        "provider": "openai",
                        "model_id": "openai-model-exact",
                        "decision": "canonical",
                        "canonical_object_id": canonical_id,
                    },
                    {
                        "teacher_id": "anthropic-01",
                        "provider": "anthropic",
                        "model_id": "anthropic-model-exact",
                        "decision": "canonical",
                        "canonical_object_id": canonical_id,
                    },
                    {
                        "teacher_id": "google-01",
                        "provider": "google",
                        "model_id": "google-model-exact",
                        "decision": "canonical",
                        "canonical_object_id": canonical_id,
                    },
                    {
                        "teacher_id": "moonshot-01",
                        "provider": "moonshot",
                        "model_id": "moonshot-model-exact",
                        "decision": "abstain",
                    },
                ],
            }
        ],
    }


def _teacher_report(*, canonical_id: str = "phone", role: str = "base") -> dict:
    report, issues = evaluate_teacher_packet(
        _teacher_packet(canonical_id=canonical_id, role=role)
    )
    assert issues == ()
    assert report is not None
    return report


def _synthetic_request(*, split: str = "train") -> dict:
    return {
        "v1_dataset_schema_version": V1_DATASET_SCHEMA_VERSION,
        "review_packet_id": "packet-v1-001",
        "dataset_id": "e1-v1-base",
        "dataset_version": "2026.09.11",
        "split": split,
        "source_group_id": "synthetic-openai-scene-family-001",
        "data_source": {
            "kind": "synthetic",
            "source_id": "synthetic-source-001",
            "generator_provider": "openai",
            "generator_model_id": "image-model-exact",
            "generation_id": "generation-001",
            "prompt_id": "prompt-001",
        },
        "image": {
            "image_path": "images/v1/source-001/frame-0001.jpg",
            "width": 1000,
            "height": 500,
        },
        "negative_tags": [],
        "geometry_proposals": [
            {
                "candidate_id": "candidate-001",
                "bbox_xywh_normalized": [0.1, 0.2, 0.2, 0.3],
                "geometry_source": {
                    "provider": "grounding_dino",
                    "model_id": "grounding-dino-exact",
                    "proposal_id": "proposal-001",
                },
            }
        ],
    }


def _open_request(*, split: str = "validation") -> dict:
    request = _synthetic_request(split=split)
    request["source_group_id"] = "open-dataset-original-group-001"
    request["data_source"] = {
        "kind": "open_source_dataset",
        "source_id": "open-source-001",
        "source_name": "example-dataset",
        "source_item_id": "original-item-123",
        "license": "CC-BY-4.0",
        "source_ref": "dataset-record-123",
    }
    return request


class V1DatasetResolutionTests(unittest.TestCase):
    def test_synthetic_train_is_silver_and_ingest_compatible(self) -> None:
        staging, issues = build_v1_annotation_staging(
            _teacher_report(), _synthetic_request(split="train")
        )

        self.assertEqual(issues, ())
        self.assertIsNotNone(staging)
        assert staging is not None
        self.assertEqual(staging["v1_audit"]["label_quality"], "silver")
        self.assertFalse(staging["v1_audit"]["human_verified"])
        self.assertFalse(staging["v1_audit"]["live_exam_external_ai_allowed"])
        self.assertFalse(staging["v1_audit"]["physical_collection_required_for_v1"])
        self.assertEqual(staging["v1_audit"]["data_source"]["kind"], "synthetic")

        manifest, ingest_issues = build_dataset_manifest(staging)
        self.assertEqual(ingest_issues, ())
        self.assertIsNotNone(manifest)

    def test_validation_teacher_consensus_is_not_gold(self) -> None:
        staging, issues = build_v1_annotation_staging(
            _teacher_report(), _open_request(split="validation")
        )

        self.assertEqual(issues, ())
        assert staging is not None
        audit = staging["v1_audit"]
        self.assertEqual(audit["label_quality"], "teacher_consensus_eval")
        self.assertFalse(audit["human_verified"])
        self.assertFalse(audit["teacher_consensus_is_ground_truth"])
        self.assertFalse(audit["evaluation_is_human_ground_truth"])
        self.assertFalse(audit["final_human_grounded_accuracy_claim_allowed"])

    def test_test_split_teacher_consensus_is_allowed_but_not_human_ground_truth(self) -> None:
        staging, issues = build_v1_annotation_staging(
            _teacher_report(), _open_request(split="test")
        )

        self.assertEqual(issues, ())
        assert staging is not None
        self.assertEqual(staging["split"], "test")
        self.assertEqual(staging["v1_audit"]["label_quality"], "teacher_consensus_eval")
        self.assertFalse(staging["v1_audit"]["final_human_grounded_accuracy_claim_allowed"])

    def test_project_physical_capture_is_rejected_for_v1_path(self) -> None:
        request = _synthetic_request()
        request["data_source"] = {
            "kind": "physical_capture",
            "source_id": "physical-001",
        }

        staging, issues = build_v1_annotation_staging(_teacher_report(), request)

        self.assertIsNone(staging)
        self.assertIn("unsupported_v1_source_kind", {issue.code for issue in issues})

    def test_synthetic_generator_provenance_is_required(self) -> None:
        request = _synthetic_request()
        request["data_source"]["generator_model_id"] = ""

        staging, issues = build_v1_annotation_staging(_teacher_report(), request)

        self.assertIsNone(staging)
        self.assertIn("missing_generator_model_id", {issue.code for issue in issues})

    def test_open_source_license_is_required_and_never_guessed(self) -> None:
        request = _open_request()
        request["data_source"]["license"] = ""

        staging, issues = build_v1_annotation_staging(_teacher_report(), request)

        self.assertIsNone(staging)
        self.assertIn("missing_source_license", {issue.code for issue in issues})

    def test_unknown_teacher_vote_quarantines_v1_data(self) -> None:
        packet = _teacher_packet()
        vote = packet["candidates"][0]["teacher_votes"][2]
        vote["decision"] = "unknown"
        vote.pop("canonical_object_id")
        report, consensus_issues = evaluate_teacher_packet(packet)
        self.assertEqual(consensus_issues, ())
        assert report is not None

        staging, issues = build_v1_annotation_staging(report, _synthetic_request())

        self.assertIsNone(staging)
        codes = {issue.code for issue in issues}
        self.assertTrue(
            "silver_unknown_present" in codes or "teacher_report_status_mismatch" in codes
        )

    def test_three_distinct_effective_providers_remain_required(self) -> None:
        packet = _teacher_packet()
        packet["candidates"][0]["teacher_votes"] = packet["candidates"][0]["teacher_votes"][:2]
        report, consensus_issues = evaluate_teacher_packet(packet)
        self.assertEqual(consensus_issues, ())
        assert report is not None

        staging, issues = build_v1_annotation_staging(report, _synthetic_request())

        self.assertIsNone(staging)
        self.assertIn(
            "silver_insufficient_effective_providers", {issue.code for issue in issues}
        )

    def test_specialist_wrist_device_works_with_nonphysical_v1_data(self) -> None:
        staging, issues = build_v1_annotation_staging(
            _teacher_report(canonical_id="wrist_device", role="specialist"),
            _synthetic_request(split="train"),
        )

        self.assertEqual(issues, ())
        assert staging is not None
        self.assertEqual(
            staging["records"][0]["annotations"][0]["canonical_object_id"],
            "wrist_device",
        )


class V1DatasetResolutionCliTests(unittest.TestCase):
    def test_cli_routes_train_and_validation_differently(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            directory = Path(temporary_directory)
            teacher_path = directory / "teacher.json"
            request_path = directory / "request.json"
            output_path = directory / "staging.json"
            teacher_path.write_text(json.dumps(_teacher_report()), encoding="utf-8")
            request_path.write_text(
                json.dumps(_open_request(split="validation")), encoding="utf-8"
            )
            stdout = io.StringIO()

            exit_code = main(
                [str(teacher_path), str(request_path), str(output_path), "--pretty"],
                stdout=stdout,
            )

            self.assertEqual(exit_code, 0)
            result = json.loads(stdout.getvalue())
            self.assertTrue(result["ok"])
            self.assertEqual(result["route"], "teacher_consensus_validation")
            self.assertEqual(result["summary"]["label_quality"], "teacher_consensus_eval")
            self.assertFalse(result["summary"]["human_verified"])

    def test_failed_request_writes_nothing(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            directory = Path(temporary_directory)
            teacher_path = directory / "teacher.json"
            request_path = directory / "request.json"
            output_path = directory / "staging.json"
            request = _synthetic_request()
            request["data_source"]["kind"] = "physical_capture"
            teacher_path.write_text(json.dumps(_teacher_report()), encoding="utf-8")
            request_path.write_text(json.dumps(request), encoding="utf-8")

            result = resolve_v1_files(teacher_path, request_path, output_path)

            self.assertFalse(result["ok"])
            self.assertEqual(result["route"], "quarantine")
            self.assertFalse(output_path.exists())


if __name__ == "__main__":
    unittest.main()

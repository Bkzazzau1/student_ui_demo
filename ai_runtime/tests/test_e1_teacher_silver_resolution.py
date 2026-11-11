import io
import json
from pathlib import Path
import tempfile
import unittest

from ai_runtime.e1_annotation_ingest import build_dataset_manifest
from ai_runtime.e1_teacher_consensus import evaluate_teacher_packet
from ai_runtime.e1_teacher_silver_resolution import (
    MIN_EFFECTIVE_PROVIDERS,
    build_silver_annotation_staging,
    main,
    resolve_silver_files,
)


def _teacher_packet(*, role: str = "base", canonical_id: str = "phone") -> dict:
    return {
        "teacher_schema_version": "1.0",
        "packet_id": "packet-silver-001",
        "model_role": role,
        "image": {
            "image_path": "images/session-001/frame-0001.jpg",
            "width": 1000,
            "height": 500,
        },
        "candidates": [
            {
                "candidate_id": "candidate-001",
                "teacher_votes": [
                    {
                        "teacher_id": "openai-teacher-01",
                        "provider": "openai",
                        "model_id": "model-openai-exact",
                        "decision": "canonical",
                        "canonical_object_id": canonical_id,
                        "bbox_xywh_normalized": [0.10, 0.20, 0.20, 0.30],
                    },
                    {
                        "teacher_id": "anthropic-teacher-01",
                        "provider": "anthropic",
                        "model_id": "model-anthropic-exact",
                        "decision": "canonical",
                        "canonical_object_id": canonical_id,
                        "bbox_xywh_normalized": [0.12, 0.21, 0.18, 0.29],
                    },
                    {
                        "teacher_id": "moonshot-teacher-01",
                        "provider": "moonshot",
                        "model_id": "model-kimi-exact",
                        "decision": "canonical",
                        "canonical_object_id": canonical_id,
                        "bbox_xywh_normalized": [0.09, 0.19, 0.22, 0.31],
                    },
                    {
                        "teacher_id": "google-teacher-01",
                        "provider": "google",
                        "model_id": "model-gemini-exact",
                        "decision": "abstain",
                    },
                ],
            }
        ],
    }


def _teacher_report(*, role: str = "base", canonical_id: str = "phone") -> dict:
    report, issues = evaluate_teacher_packet(_teacher_packet(role=role, canonical_id=canonical_id))
    assert issues == ()
    assert report is not None
    return report


def _silver_request() -> dict:
    return {
        "silver_schema_version": "1.0",
        "review_packet_id": "packet-silver-001",
        "dataset_id": "e1-v1-silver-base",
        "dataset_version": "2026.09.11",
        "split": "train",
        "source_group_id": "session-001",
        "image": {
            "image_path": "images/session-001/frame-0001.jpg",
            "width": 1000,
            "height": 500,
        },
        "negative_tags": [],
        "geometry_proposals": [
            {
                "candidate_id": "candidate-001",
                "bbox_xywh_normalized": [0.11, 0.20, 0.19, 0.30],
                "geometry_source": {
                    "provider": "grounding_dino",
                    "model_id": "grounding-dino-exact-model-id",
                    "proposal_id": "proposal-001",
                },
            }
        ],
    }


class SilverBootstrapTests(unittest.TestCase):
    def test_strict_three_provider_agreement_emits_training_only_silver_staging(self) -> None:
        staging, issues = build_silver_annotation_staging(_teacher_report(), _silver_request())

        self.assertEqual(issues, ())
        self.assertIsNotNone(staging)
        assert staging is not None
        self.assertEqual(staging["split"], "train")
        self.assertEqual(staging["silver_audit"]["label_quality"], "silver")
        self.assertFalse(staging["silver_audit"]["human_verified"])
        self.assertEqual(
            staging["silver_audit"]["minimum_effective_provider_count"],
            MIN_EFFECTIVE_PROVIDERS,
        )
        self.assertFalse(staging["silver_audit"]["live_exam_external_ai_allowed"])
        self.assertTrue(staging["silver_audit"]["teacher_models_are_development_only"])
        self.assertEqual(
            staging["records"][0]["annotations"],
            [
                {
                    "canonical_object_id": "phone",
                    "bbox_xywh_normalized": [0.11, 0.20, 0.19, 0.30],
                }
            ],
        )

        manifest, ingest_issues = build_dataset_manifest(staging)
        self.assertEqual(ingest_issues, ())
        self.assertIsNotNone(manifest)

    def test_teacher_boxes_are_not_fused_or_selected(self) -> None:
        staging, issues = build_silver_annotation_staging(_teacher_report(), _silver_request())

        self.assertEqual(issues, ())
        assert staging is not None
        self.assertEqual(
            staging["records"][0]["annotations"][0]["bbox_xywh_normalized"],
            [0.11, 0.20, 0.19, 0.30],
        )
        audit = staging["silver_audit"]["accepted_candidates"][0]
        self.assertEqual(audit["geometry_source"]["provider"], "grounding_dino")
        self.assertEqual(audit["geometry_source"]["proposal_id"], "proposal-001")
        self.assertEqual(
            staging["silver_audit"]["geometry_policy"],
            "explicit_candidate_proposal_no_teacher_box_fusion",
        )

    def test_two_effective_providers_are_not_enough_for_silver(self) -> None:
        packet = _teacher_packet()
        packet["candidates"][0]["teacher_votes"] = packet["candidates"][0]["teacher_votes"][:2]
        report, consensus_issues = evaluate_teacher_packet(packet)
        self.assertEqual(consensus_issues, ())
        assert report is not None
        self.assertEqual(report["candidates"][0]["status"], "teacher_agreement")

        staging, issues = build_silver_annotation_staging(report, _silver_request())

        self.assertIsNone(staging)
        self.assertIn("silver_insufficient_effective_providers", {issue.code for issue in issues})

    def test_repeated_calls_from_same_provider_do_not_fake_independence(self) -> None:
        packet = _teacher_packet()
        votes = packet["candidates"][0]["teacher_votes"]
        votes[2]["provider"] = "anthropic"
        report, consensus_issues = evaluate_teacher_packet(packet)
        self.assertEqual(consensus_issues, ())
        assert report is not None
        self.assertEqual(report["candidates"][0]["teacher_effective_provider_count"], 2)

        staging, issues = build_silver_annotation_staging(report, _silver_request())

        self.assertIsNone(staging)
        self.assertIn("silver_insufficient_effective_providers", {issue.code for issue in issues})

    def test_unknown_routes_to_quarantine(self) -> None:
        packet = _teacher_packet()
        vote = packet["candidates"][0]["teacher_votes"][2]
        vote["decision"] = "unknown"
        vote.pop("canonical_object_id")
        vote.pop("bbox_xywh_normalized")
        report, consensus_issues = evaluate_teacher_packet(packet)
        self.assertEqual(consensus_issues, ())
        assert report is not None

        staging, issues = build_silver_annotation_staging(report, _silver_request())

        self.assertIsNone(staging)
        codes = {issue.code for issue in issues}
        self.assertTrue(
            "silver_unknown_present" in codes or "teacher_report_status_mismatch" in codes
        )

    def test_disagreement_routes_to_quarantine(self) -> None:
        packet = _teacher_packet()
        packet["candidates"][0]["teacher_votes"][1]["canonical_object_id"] = "remote"
        report, consensus_issues = evaluate_teacher_packet(packet)
        self.assertEqual(consensus_issues, ())
        assert report is not None

        staging, issues = build_silver_annotation_staging(report, _silver_request())

        self.assertIsNone(staging)
        self.assertIn("silver_teacher_disagreement", {issue.code for issue in issues})

    def test_canonical_silver_candidate_requires_explicit_geometry_proposal(self) -> None:
        request = _silver_request()
        request["geometry_proposals"] = []

        staging, issues = build_silver_annotation_staging(_teacher_report(), request)

        self.assertIsNone(staging)
        self.assertIn("missing_geometry_proposal", {issue.code for issue in issues})

    def test_geometry_provenance_must_be_complete(self) -> None:
        request = _silver_request()
        request["geometry_proposals"][0]["geometry_source"]["model_id"] = ""

        staging, issues = build_silver_annotation_staging(_teacher_report(), request)

        self.assertIsNone(staging)
        self.assertIn("incomplete_geometry_provenance", {issue.code for issue in issues})

    def test_silver_labels_cannot_enter_validation_or_test(self) -> None:
        for split in ("validation", "test"):
            with self.subTest(split=split):
                request = _silver_request()
                request["split"] = split
                staging, issues = build_silver_annotation_staging(_teacher_report(), request)
                self.assertIsNone(staging)
                self.assertIn("silver_train_only", {issue.code for issue in issues})

    def test_wrist_device_is_supported_for_specialist_silver_training(self) -> None:
        report = _teacher_report(role="specialist", canonical_id="wrist_device")
        request = _silver_request()
        request["dataset_id"] = "e1-v1-silver-specialist"

        staging, issues = build_silver_annotation_staging(report, request)

        self.assertEqual(issues, ())
        assert staging is not None
        self.assertEqual(
            staging["records"][0]["annotations"][0]["canonical_object_id"],
            "wrist_device",
        )

    def test_no_object_can_create_explicit_hard_negative_but_not_implicit_negative(self) -> None:
        packet = _teacher_packet()
        for vote in packet["candidates"][0]["teacher_votes"]:
            if vote["decision"] == "canonical":
                vote["decision"] = "no_object"
                vote.pop("canonical_object_id")
                vote.pop("bbox_xywh_normalized")
        report, consensus_issues = evaluate_teacher_packet(packet)
        self.assertEqual(consensus_issues, ())
        assert report is not None

        request = _silver_request()
        request["geometry_proposals"] = []
        staging, issues = build_silver_annotation_staging(report, request)
        self.assertIsNone(staging)
        self.assertIn("empty_silver_record_without_negative_tags", {issue.code for issue in issues})

        request["negative_tags"] = ["hand_without_phone"]
        staging, issues = build_silver_annotation_staging(report, request)
        self.assertEqual(issues, ())
        assert staging is not None
        self.assertEqual(staging["records"][0]["annotations"], [])
        self.assertEqual(staging["records"][0]["negative_tags"], ["hand_without_phone"])


class SilverBootstrapCliTests(unittest.TestCase):
    def test_cli_writes_ingest_compatible_silver_staging(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            directory = Path(temporary_directory)
            teacher_path = directory / "teacher.json"
            request_path = directory / "silver-request.json"
            output_path = directory / "staging.json"
            teacher_path.write_text(json.dumps(_teacher_report()), encoding="utf-8")
            request_path.write_text(json.dumps(_silver_request()), encoding="utf-8")
            stdout = io.StringIO()

            exit_code = main(
                [str(teacher_path), str(request_path), str(output_path), "--pretty"],
                stdout=stdout,
            )

            self.assertEqual(exit_code, 0)
            result = json.loads(stdout.getvalue())
            self.assertTrue(result["ok"])
            self.assertEqual(result["route"], "silver_train")
            emitted = json.loads(output_path.read_text(encoding="utf-8"))
            manifest, issues = build_dataset_manifest(emitted)
            self.assertEqual(issues, ())
            self.assertIsNotNone(manifest)

    def test_failed_silver_review_does_not_write_output(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            directory = Path(temporary_directory)
            teacher_path = directory / "teacher.json"
            request_path = directory / "silver-request.json"
            output_path = directory / "staging.json"
            packet = _teacher_packet()
            packet["candidates"][0]["teacher_votes"] = packet["candidates"][0]["teacher_votes"][:2]
            report, consensus_issues = evaluate_teacher_packet(packet)
            self.assertEqual(consensus_issues, ())
            assert report is not None
            teacher_path.write_text(json.dumps(report), encoding="utf-8")
            request_path.write_text(json.dumps(_silver_request()), encoding="utf-8")

            result = resolve_silver_files(teacher_path, request_path, output_path)

            self.assertFalse(result["ok"])
            self.assertEqual(result["route"], "quarantine")
            self.assertFalse(output_path.exists())

    def test_output_cannot_overwrite_an_input_even_with_force(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            directory = Path(temporary_directory)
            teacher_path = directory / "teacher.json"
            request_path = directory / "silver-request.json"
            teacher_text = json.dumps(_teacher_report())
            teacher_path.write_text(teacher_text, encoding="utf-8")
            request_path.write_text(json.dumps(_silver_request()), encoding="utf-8")

            result = resolve_silver_files(
                teacher_path,
                request_path,
                teacher_path,
                force=True,
            )

            self.assertFalse(result["ok"])
            self.assertEqual(result["issues"][0]["code"], "input_output_same")
            self.assertEqual(teacher_path.read_text(encoding="utf-8"), teacher_text)


if __name__ == "__main__":
    unittest.main()

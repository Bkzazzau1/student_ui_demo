import copy
import io
import json
from pathlib import Path
import tempfile
import unittest

from ai_runtime.e1_teacher_consensus import (
    evaluate_teacher_packet,
    main,
    review_teacher_file,
)


def _packet() -> dict:
    return {
        "teacher_schema_version": "1.0",
        "packet_id": "e1-teacher-example-001",
        "model_role": "base",
        "image": {
            "image_path": "images/example/frame-0001.jpg",
            "width": 1280,
            "height": 720,
        },
        "candidates": [
            {
                "candidate_id": "candidate-phone-001",
                "teacher_votes": [
                    {
                        "teacher_id": "openai-teacher-01",
                        "provider": "openai",
                        "model_id": "actual-model-id-a",
                        "decision": "canonical",
                        "canonical_object_id": "Phone",
                        "bbox_xywh_normalized": [0.40, 0.30, 0.10, 0.20],
                    },
                    {
                        "teacher_id": "anthropic-teacher-01",
                        "provider": "anthropic",
                        "model_id": "actual-model-id-b",
                        "decision": "canonical",
                        "canonical_object_id": "phone",
                        "bbox_xywh_normalized": [0.41, 0.31, 0.09, 0.19],
                    },
                    {
                        "teacher_id": "google-teacher-01",
                        "provider": "google",
                        "model_id": "actual-model-id-c",
                        "decision": "canonical",
                        "canonical_object_id": "phone",
                        "bbox_xywh_normalized": [0.39, 0.30, 0.11, 0.20],
                    },
                ],
            }
        ],
    }


class TeacherConsensusTests(unittest.TestCase):
    def test_unanimous_canonical_vote_is_only_teacher_agreement(self) -> None:
        report, issues = evaluate_teacher_packet(_packet())

        self.assertEqual(issues, ())
        assert report is not None
        candidate = report["candidates"][0]
        self.assertEqual(candidate["status"], "teacher_agreement")
        self.assertEqual(
            candidate["suggested_decision"],
            {"decision": "canonical", "canonical_object_id": "phone"},
        )
        self.assertTrue(candidate["human_review_required"])
        self.assertEqual(candidate["geometry_resolution"], "human_required")
        self.assertFalse(report["policy"]["teacher_agreement_is_ground_truth"])
        self.assertFalse(report["policy"]["live_exam_external_ai_allowed"])
        self.assertFalse(report["policy"]["teacher_geometry_fusion_used"])

    def test_disagreement_is_preserved(self) -> None:
        packet = _packet()
        packet["candidates"][0]["teacher_votes"][1]["canonical_object_id"] = "remote"

        report, issues = evaluate_teacher_packet(packet)

        self.assertEqual(issues, ())
        assert report is not None
        candidate = report["candidates"][0]
        self.assertEqual(candidate["status"], "needs_human_review")
        self.assertIsNone(candidate["suggested_decision"])
        self.assertEqual(candidate["vote_counts"]["canonical:phone"], 2)
        self.assertEqual(candidate["vote_counts"]["canonical:remote"], 1)

    def test_unknown_forces_human_review_even_when_other_teachers_agree(self) -> None:
        packet = _packet()
        vote = packet["candidates"][0]["teacher_votes"][2]
        vote["decision"] = "unknown"
        vote.pop("canonical_object_id")
        vote.pop("bbox_xywh_normalized")

        report, issues = evaluate_teacher_packet(packet)

        self.assertEqual(issues, ())
        assert report is not None
        candidate = report["candidates"][0]
        self.assertEqual(candidate["status"], "needs_human_review")
        self.assertIsNone(candidate["suggested_decision"])
        self.assertEqual(candidate["vote_counts"]["unknown"], 1)

    def test_one_provider_is_insufficient_even_with_multiple_votes(self) -> None:
        packet = _packet()
        for vote in packet["candidates"][0]["teacher_votes"]:
            vote["provider"] = "openai"

        report, issues = evaluate_teacher_packet(packet)

        self.assertEqual(issues, ())
        assert report is not None
        candidate = report["candidates"][0]
        self.assertEqual(candidate["status"], "insufficient_review")
        self.assertEqual(candidate["teacher_provider_count"], 1)
        self.assertIsNone(candidate["suggested_decision"])

    def test_repeated_calls_from_one_effective_provider_are_not_agreement(self) -> None:
        # A second provider is represented in the packet (satisfying the naive
        # "at least two providers" check), but it only abstained. The single
        # remaining provider answering twice under two teacher_id configs must
        # not be treated as independent multi-provider agreement.
        packet = _packet()
        votes = packet["candidates"][0]["teacher_votes"]
        votes[0]["decision"] = "abstain"
        votes[0].pop("canonical_object_id")
        votes[0].pop("bbox_xywh_normalized")
        votes[2]["provider"] = votes[1]["provider"]
        votes[2]["teacher_id"] = votes[1]["teacher_id"] + "-second-call"

        report, issues = evaluate_teacher_packet(packet)

        self.assertEqual(issues, ())
        assert report is not None
        candidate = report["candidates"][0]
        self.assertEqual(candidate["teacher_provider_count"], 2)
        self.assertEqual(candidate["teacher_effective_provider_count"], 1)
        self.assertEqual(candidate["status"], "insufficient_review")
        self.assertIsNone(candidate["suggested_decision"])

    def test_no_object_agreement_is_not_an_annotation(self) -> None:
        packet = _packet()
        for vote in packet["candidates"][0]["teacher_votes"]:
            vote["decision"] = "no_object"
            vote.pop("canonical_object_id")
            vote.pop("bbox_xywh_normalized")

        report, issues = evaluate_teacher_packet(packet)

        self.assertEqual(issues, ())
        assert report is not None
        candidate = report["candidates"][0]
        self.assertEqual(candidate["status"], "teacher_agreement")
        self.assertEqual(candidate["suggested_decision"], {"decision": "no_object"})
        self.assertTrue(candidate["human_review_required"])
        self.assertEqual(candidate["geometry_resolution"], "not_applicable")

    def test_semantic_alias_is_rejected_instead_of_guessed(self) -> None:
        packet = _packet()
        packet["candidates"][0]["teacher_votes"][0]["canonical_object_id"] = "cell phone"

        report, issues = evaluate_teacher_packet(packet)

        self.assertIsNone(report)
        self.assertIn("class_not_allowed_for_role", {issue.code for issue in issues})

    def test_specialist_class_cannot_enter_base_teacher_packet(self) -> None:
        packet = _packet()
        packet["candidates"][0]["teacher_votes"][0]["canonical_object_id"] = "smartwatch"

        report, issues = evaluate_teacher_packet(packet)

        self.assertIsNone(report)
        self.assertIn("class_not_allowed_for_role", {issue.code for issue in issues})

    def test_specialist_role_accepts_specialist_canonical_classes(self) -> None:
        packet = _packet()
        packet["model_role"] = "specialist"
        for vote in packet["candidates"][0]["teacher_votes"]:
            vote["canonical_object_id"] = "earbud"

        report, issues = evaluate_teacher_packet(packet)

        self.assertEqual(issues, ())
        assert report is not None
        self.assertEqual(
            report["candidates"][0]["suggested_decision"],
            {"decision": "canonical", "canonical_object_id": "earbud"},
        )

    def test_invalid_geometry_is_rejected(self) -> None:
        packet = _packet()
        packet["candidates"][0]["teacher_votes"][0]["bbox_xywh_normalized"] = [0.95, 0.1, 0.2, 0.2]

        report, issues = evaluate_teacher_packet(packet)

        self.assertIsNone(report)
        self.assertIn("invalid_bbox", {issue.code for issue in issues})

    def test_teacher_confidence_field_is_not_used_or_propagated(self) -> None:
        packet = _packet()
        packet["candidates"][0]["teacher_votes"][0]["confidence"] = 0.999
        packet["candidates"][0]["teacher_votes"][1]["confidence"] = 0.001

        report, issues = evaluate_teacher_packet(packet)

        self.assertEqual(issues, ())
        assert report is not None
        votes = report["candidates"][0]["teacher_votes"]
        self.assertTrue(all("confidence" not in vote for vote in votes))
        self.assertFalse(report["policy"]["teacher_confidence_weighting_used"])


class TeacherConsensusCliTests(unittest.TestCase):
    def test_cli_writes_review_report(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            directory = Path(temporary_directory)
            input_path = directory / "packet.json"
            output_path = directory / "report.json"
            input_path.write_text(json.dumps(_packet()), encoding="utf-8")
            stdout = io.StringIO()

            exit_code = main(
                [str(input_path), str(output_path), "--pretty"],
                stdout=stdout,
            )

            self.assertEqual(exit_code, 0)
            result = json.loads(stdout.getvalue())
            self.assertTrue(result["ok"])
            report = json.loads(output_path.read_text(encoding="utf-8"))
            self.assertEqual(report["summary"]["candidate_count"], 1)
            self.assertEqual(report["summary"]["status_counts"]["teacher_agreement"], 1)

    def test_existing_output_requires_force(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            directory = Path(temporary_directory)
            input_path = directory / "packet.json"
            output_path = directory / "report.json"
            input_path.write_text(json.dumps(_packet()), encoding="utf-8")
            output_path.write_text("keep-me", encoding="utf-8")

            blocked = review_teacher_file(input_path, output_path)
            self.assertFalse(blocked["ok"])
            self.assertEqual(blocked["issues"][0]["code"], "output_exists")
            self.assertEqual(output_path.read_text(encoding="utf-8"), "keep-me")

            replaced = review_teacher_file(input_path, output_path, force=True)
            self.assertTrue(replaced["ok"])

    def test_input_output_same_path_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            directory = Path(temporary_directory)
            shared_path = directory / "packet.json"
            original_text = json.dumps(_packet())
            shared_path.write_text(original_text, encoding="utf-8")

            result = review_teacher_file(shared_path, shared_path)

            self.assertFalse(result["ok"])
            self.assertEqual(result["issues"][0]["code"], "input_output_same")
            self.assertEqual(shared_path.read_text(encoding="utf-8"), original_text)

    def test_input_output_same_path_is_rejected_even_with_force(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            directory = Path(temporary_directory)
            shared_path = directory / "packet.json"
            original_text = json.dumps(_packet())
            shared_path.write_text(original_text, encoding="utf-8")

            result = review_teacher_file(shared_path, shared_path, force=True)

            self.assertFalse(result["ok"])
            self.assertEqual(result["issues"][0]["code"], "input_output_same")
            self.assertEqual(shared_path.read_text(encoding="utf-8"), original_text)

    def test_invalid_packet_does_not_create_output(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            directory = Path(temporary_directory)
            input_path = directory / "packet.json"
            output_path = directory / "report.json"
            packet = copy.deepcopy(_packet())
            packet["model_role"] = "wrong-role"
            input_path.write_text(json.dumps(packet), encoding="utf-8")

            result = review_teacher_file(input_path, output_path)

            self.assertFalse(result["ok"])
            self.assertFalse(output_path.exists())


if __name__ == "__main__":
    unittest.main()

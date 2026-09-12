"""Synthetic fixtures test engineering contracts, never model accuracy."""

from copy import deepcopy
import contextlib
import io
import json
from pathlib import Path
import tempfile
import unittest

from ai_runtime.e1_evaluation import evaluate, fingerprint, ingest_calibration
from ai_runtime.e1_experiments import candidate_manifest, inspect_package
from ai_runtime.e1_ml_common import load, save
from ai_runtime.e1_ml_pipeline import main
from ai_runtime.e1_scenarios import check_scenarios
from ai_runtime.e1_training_export import class_order_for_role, export_training_package


BOX = {"x": .1, "y": .2, "width": .2, "height": .3}


def fixtures(role="base"):
    classes = class_order_for_role(role)
    manifests = []
    for split in ("train", "validation", "test"):
        samples = [{"sample_id": f"{split}-{index}", "source_group_id": f"{split}-session",
                    "image_path": f"{split}-{index}.png", "width": 100, "height": 100,
                    "annotations": [{"annotation_id": f"ann-{index}", "canonical_object_id": c,
                                     "bbox_xywh_normalized": deepcopy(BOX)}]}
                   for index, c in enumerate(classes)]
        samples.append({"sample_id": f"{split}-negative", "source_group_id": f"{split}-negative-session",
                        "image_path": f"{split}-negative.png", "width": 100, "height": 100,
                        "annotations": [], "negative_tags": ["hand_without_phone"]})
        manifests.append({"schema_version": "1.0", "taxonomy_version": "1.0",
                          "dataset_id": "synthetic-unit-fixture", "dataset_version": "test-only",
                          "model_role": role, "split": split, "samples": samples})
    predictions = {"model_id": "unit-test", "model_version": "test-only", "model_sha256": "a"*64,
                   "split": "validation", "manifest_sha256": fingerprint(manifests[1]),
                   "class_names": list(classes), "prediction_basis": "synthetic unit test",
                   "score_floor": 0.0, "samples": {}}
    for sample in manifests[1]["samples"]:
        predictions["samples"][sample["sample_id"]] = [
            {"canonical_object_id": a["canonical_object_id"], "confidence": .8,
             "bbox_xywh_normalized": deepcopy(BOX)} for a in sample["annotations"]]
    return manifests, predictions


class EvaluationTests(unittest.TestCase):
    def test_perfect_predictions_and_empty_negative(self):
        for role in ("base", "specialist"):
            manifests, predictions = fixtures(role)
            result = evaluate(manifests, predictions, .5)
            self.assertTrue(result["evaluation_valid"])
            self.assertFalse(result["production_accepted"])
            for metric in result["class_metrics"].values():
                self.assertEqual(metric, dict(support=1, precision=1, recall=1, f1=1, ap50=1, ap50_95=1))
            self.assertEqual(result["hard_negative_metrics"]["hand_without_phone"]["false_positive_rate"], 0)
            self.assertTrue(all(v["selected_confidence_threshold"] is None for v in result["calibration"].values()))

    def test_high_rank_false_positive_reduces_ap_and_counts_negative(self):
        manifests, predictions = fixtures()
        predictions["samples"]["validation-negative"] = [{"canonical_object_id": "person",
            "confidence": .9, "bbox_xywh_normalized": deepcopy(BOX)}]
        result = evaluate(manifests, predictions, .5)
        self.assertEqual(result["class_metrics"]["person"]["ap50"], .5)
        self.assertEqual(result["class_metrics"]["person"]["precision"], .5)
        self.assertEqual(result["hard_negative_metrics"]["hand_without_phone"]["false_positive_rate"], 1)

    def test_duplicate_prediction_cannot_match_truth_twice(self):
        manifests, predictions = fixtures()
        predictions["samples"]["validation-0"] *= 2
        metric = evaluate(manifests, predictions, .5)["class_metrics"]["person"]
        self.assertEqual(metric["recall"], 1)
        self.assertEqual(metric["precision"], .5)

    def test_missing_or_unknown_inference_rejected(self):
        for value in (None, "UNKNOWN"):
            manifests, predictions = fixtures()
            predictions["samples"]["validation-0"] = value
            with self.assertRaises(ValueError):
                evaluate(manifests, predictions, .5)
        del predictions["samples"]["validation-0"]
        with self.assertRaises(ValueError):
            evaluate(manifests, predictions, .5)

    def test_leakage_and_hash_mismatch_rejected(self):
        manifests, predictions = fixtures()
        manifests[0]["samples"][0]["source_group_id"] = "validation-session"
        with self.assertRaises(ValueError):
            evaluate(manifests, predictions, .5)
        manifests, predictions = fixtures()
        predictions["manifest_sha256"] = "other"
        with self.assertRaises(ValueError):
            evaluate(manifests, predictions, .5)

    def test_zero_support_is_null_and_invalid(self):
        manifests, predictions = fixtures()
        manifests[1]["samples"][0]["annotations"] = []
        predictions["manifest_sha256"] = fingerprint(manifests[1])
        result = evaluate(manifests, predictions, .5)
        self.assertFalse(result["evaluation_valid"])
        self.assertIsNone(result["class_metrics"]["person"]["ap50"])
        self.assertIsNone(result["class_metrics"]["person"]["recall"])

    def test_threshold_floor_and_nonfinite_rejected(self):
        manifests, predictions = fixtures()
        predictions["score_floor"] = .9
        with self.assertRaises(ValueError):
            evaluate(manifests, predictions, .5)
        predictions["score_floor"] = 0
        predictions["samples"]["validation-0"][0]["confidence"] = float("nan")
        with self.assertRaises(ValueError):
            evaluate(manifests, predictions, .5)

    def test_calibration_binds_validation_and_model(self):
        manifests, predictions = fixtures()
        report = evaluate(manifests, predictions, .5)
        evidence = {k: report[k] for k in ("model_id", "model_version", "model_sha256", "model_role")}
        evidence.update(split="validation", manifest_sha256=fingerprint(manifests[1]),
                        selection_basis="synthetic test only", thresholds={c: .6 for c in predictions["class_names"]})
        calibrated = ingest_calibration(report, evidence, manifests)
        self.assertEqual(calibrated["calibration"]["phone"]["selected_confidence_threshold"], .6)
        self.assertIsNone(report["calibration"]["phone"]["selected_confidence_threshold"])
        for field, value in (("split", "test"), ("model_sha256", "wrong"), ("selection_basis", "")):
            bad = deepcopy(evidence)
            bad[field] = value
            with self.assertRaises(ValueError):
                ingest_calibration(report, bad, manifests)

    def test_candidate_always_uninstalled(self):
        manifests, predictions = fixtures()
        report = evaluate(manifests, predictions, .5)
        metadata = {k: report[k] for k in ("model_id", "model_version", "model_sha256", "model_role")}
        metadata.update(class_names=list(class_order_for_role("base")), checkpoint_sha256="b"*64,
                        input_width=4, input_height=4, input_shape=[1, 3, 4, 4],
                        output_shape=[1, 12, 2], output_layout="channels_first_yolov8", model_path="test.onnx")
        parity = {"model_sha256": report["model_sha256"], "parity_passed": True}
        candidate = candidate_manifest(metadata, report, parity)
        self.assertFalse(candidate["installed"])
        self.assertFalse(candidate["production_accepted"])
        parity["model_sha256"] = "different"
        with self.assertRaises(ValueError):
            candidate_manifest(metadata, report, parity)

    def test_cli_writes_metrics_and_refuses_overwrite(self):
        manifests, predictions = fixtures()
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for manifest in manifests:
                save(root / (manifest["split"] + ".json"), manifest)
            save(root / "predictions.json", predictions)
            args = ["evaluate", "--manifests", *[str(root / (m["split"] + ".json")) for m in manifests],
                    "--predictions", str(root / "predictions.json"), "--operating-confidence", ".5",
                    "--output", str(root / "report.json")]
            with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
                self.assertEqual(main(args), 0)
                before = (root / "report.json").read_bytes()
                self.assertEqual(main(args), 1)
                self.assertEqual(before, (root / "report.json").read_bytes())

    def test_json_nonfinite_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "bad.json"
            path.write_text('{"value": NaN}')
            with self.assertRaises(ValueError):
                load(path)


class PackageTests(unittest.TestCase):
    def test_package_hashes_coverage_and_extra_file(self):
        manifests, _ = fixtures()
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for m in manifests:
                for sample in m["samples"]:
                    (root / sample["image_path"]).write_bytes(sample["sample_id"].encode())
                save(root / (m["split"] + ".json"), m)
            package = root / "package"
            result = export_training_package([root / (m["split"] + ".json") for m in manifests], package)
            self.assertTrue(result["ok"])
            _, ledger = inspect_package(package)
            self.assertEqual(len(ledger), 27)
            (package / "images/train/unlisted.png").write_bytes(b"extra")
            with self.assertRaises(ValueError):
                inspect_package(package)


def scenario_fixture():
    def event(eid, frame, timestamp, track):
        return {"schema_version": "1.0", "session_id": "session", "event_id": eid,
                "source_frame_id": frame, "capture_timestamp_ns": timestamp,
                "inference_timestamp_ns": timestamp+10, "model_id": "unit-test", "model_version": "1",
                "track_id": track, "class_id": "person", "confidence": .8, "quality": None,
                "geometry": None, "validity_interval": {"start_timestamp_ns": timestamp,
                "end_timestamp_ns": None}, "metadata": {}}
    spec = {"cases": [{"case_id": "short-disappearance", "assertions": [
        {"kind": "same_track", "event_ids": ["a", "b"]},
        {"kind": "distinct_tracks", "event_ids": ["b", "c"]},
        {"kind": "unknown", "session_id": "session", "source_frame_id": 3},
        {"kind": "event", "event_id": "b", "class_id": "person", "capture_timestamp_ns": 200}]}]}
    trace = {"scenario_sha256": fingerprint(spec), "tracker_owner": "rust", "native_build_id": "test-only",
             "frames": [{"session_id": "session", "source_frame_id": i, "capture_timestamp_ns": i*100}
                        for i in (1, 2, 3)],
             "events": [event("b", 2, 200, "track-a"), event("a", 1, 100, "track-a"), event("c", 2, 200, "track-c")],
             "specialist_outcomes": [{"session_id": "session", "source_frame_id": 3,
                                      "status": "skipped", "evidence": "UNKNOWN", "event_ids": []}]}
    return spec, trace


class ScenarioTests(unittest.TestCase):
    def test_out_of_order_trace_tracks_and_unknown(self):
        spec, trace = scenario_fixture()
        result = check_scenarios(spec, trace)
        self.assertTrue(result["trace_assertions_passed"])
        self.assertEqual(result["offline_device_acceptance"], "pending_operator_evidence")

    def test_capture_timestamp_cannot_be_replaced(self):
        spec, trace = scenario_fixture()
        trace["events"][0]["capture_timestamp_ns"] += 1
        with self.assertRaises(ValueError):
            check_scenarios(spec, trace)

    def test_skipped_cannot_be_absence(self):
        spec, trace = scenario_fixture()
        trace["specialist_outcomes"][0]["evidence"] = "ABSENT"
        with self.assertRaises(ValueError):
            check_scenarios(spec, trace)

    def test_track_identity_mismatch_rejected(self):
        spec, trace = scenario_fixture()
        trace["events"][0]["track_id"] = "wrong"
        with self.assertRaises(ValueError):
            check_scenarios(spec, trace)

    def test_empty_scenario_cannot_pass(self):
        spec, trace = scenario_fixture()
        spec["cases"][0]["assertions"] = []
        trace["scenario_sha256"] = fingerprint(spec)
        with self.assertRaises(ValueError):
            check_scenarios(spec, trace)


if __name__ == "__main__":
    unittest.main()

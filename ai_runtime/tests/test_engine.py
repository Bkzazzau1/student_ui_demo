import unittest

from ai_runtime.engine import EdgeAiEngine
from ai_runtime.server import handle_request


class EdgeAiEngineTests(unittest.TestCase):
    def test_gaze_observations_require_calibration_before_review(self):
        engine = EdgeAiEngine()
        uncertain = engine.observe_gaze({
            "attempt_id": "a1", "zone": "downward_gaze",
            "confidence": 0.9, "signal_quality": 0.9,
            "calibrated": False, "actionable": False, "deviating": True,
        })
        self.assertEqual("uncertain", uncertain["state"])
        result = None
        for _ in range(8):
            result = engine.observe_gaze({
                "attempt_id": "a1", "zone": "downward_gaze",
                "confidence": 0.9, "signal_quality": 0.9,
                "calibrated": True, "actionable": True, "deviating": True,
            })
        self.assertEqual("needs_review", result["state"])
        self.assertEqual([], result["proposed_actions"])
    def test_single_gaze_event_does_not_accuse_or_pause(self):
        result = EdgeAiEngine().review_event({
            "attempt_id": "a1", "event_type": "gaze_head_pose_deviation", "confidence": 0.9
        })
        self.assertEqual("continue_observation", result.disposition)
        self.assertFalse(result.requires_human_review)
        self.assertIn("never treated as proof", result.reasons[-1])

    def test_corroborating_signals_request_human_review(self):
        engine = EdgeAiEngine()
        engine.review_event({"attempt_id": "a1", "event_type": "sustained_gaze_head_pose_deviation", "confidence": 1})
        result = engine.review_event({"attempt_id": "a1", "event_type": "yolo_phone_detected", "confidence": 1})
        self.assertEqual("human_review", result.disposition)
        self.assertTrue(result.requires_human_review)
        self.assertEqual(("capture_review_snapshot",), result.proposed_actions)

    def test_memory_is_bounded_and_clearable(self):
        engine = EdgeAiEngine(max_events_per_attempt=2)
        for _ in range(3):
            engine.review_event({"attempt_id": "a1", "event_type": "gaze_head_pose_deviation"})
        self.assertEqual(2, engine.event_count("a1"))
        self.assertTrue(engine.clear_attempt("a1"))
        self.assertEqual(0, engine.event_count("a1"))

    def test_protocol_health(self):
        response = handle_request(EdgeAiEngine(), {
            "protocol_version": "1.0", "request_id": "health-1", "type": "health"
        })
        self.assertTrue(response["ok"])
        self.assertFalse(response["result"]["stores_raw_media"])

    def test_invalid_confidence_is_rejected(self):
        with self.assertRaisesRegex(ValueError, "confidence"):
            EdgeAiEngine().review_event({
                "attempt_id": "a1", "event_type": "gaze_head_pose_deviation", "confidence": "high"
            })


if __name__ == "__main__":
    unittest.main()

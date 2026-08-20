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

    def test_audio_requires_calibration_and_sustained_observation(self):
        engine = EdgeAiEngine()
        uncertain = engine.observe_audio({
            "attempt_id": "a1", "label": "near_voice", "voice_confidence": 0.9,
            "signal_quality": 0.9, "calibrated": False, "near_voice": True,
            "background_voice": False, "allowed_ambient": False,
            "baseline_deviation": 4.0, "duration_ms": 1000,
        })
        self.assertEqual("uncertain", uncertain["state"])
        result = None
        for _ in range(3):
            result = engine.observe_audio({
                "attempt_id": "a1", "label": "near_voice", "voice_confidence": 0.9,
                "signal_quality": 0.9, "calibrated": True, "near_voice": True,
                "background_voice": False, "allowed_ambient": False,
                "baseline_deviation": 4.0, "duration_ms": 1000,
            })
        self.assertEqual("needs_review", result["state"])
        self.assertEqual([], result["proposed_actions"])
        self.assertFalse(result["stores_raw_media"])

    def test_corroborating_signals_request_human_review(self):
        engine = EdgeAiEngine()
        engine.review_event({"attempt_id": "a1", "event_type": "sustained_gaze_head_pose_deviation", "confidence": 1})
        result = engine.review_event({"attempt_id": "a1", "event_type": "yolo_phone_detected", "confidence": 1})
        self.assertEqual("human_review", result.disposition)
        self.assertTrue(result.requires_human_review)
        self.assertEqual(("capture_review_snapshot",), result.proposed_actions)
        self.assertEqual(("attention", "environment"), result.signal_groups)

    def test_low_quality_event_is_not_fused(self):
        result = EdgeAiEngine().review_event({
            "attempt_id": "a1", "event_type": "multiple_people_detected",
            "confidence": 1.0, "signal_quality": 0.2,
        })
        self.assertFalse(result.requires_human_review)
        self.assertEqual(0, result.risk_score)

    def test_repeated_event_has_bounded_influence(self):
        engine = EdgeAiEngine()
        result = None
        for _ in range(20):
            result = engine.review_event({
                "attempt_id": "a1", "event_type": "gaze_head_pose_deviation",
                "confidence": 0.8, "signal_quality": 0.9,
            })
        self.assertLess(result.risk_score, 30)

    def test_identity_and_audio_are_explained_as_separate_groups(self):
        engine = EdgeAiEngine()
        engine.review_event({
            "attempt_id": "a1", "event_type": "camera_view_needs_review",
            "confidence": 0.8, "signal_quality": 0.9,
        })
        result = engine.review_event({
            "attempt_id": "a1", "event_type": "audio_voice_isolation_alert",
            "confidence": 0.9, "signal_quality": 0.9,
        })
        self.assertEqual(("identity_presence", "audio"), result.signal_groups)
        self.assertIn("Corroborating signals", result.reasons[-1])

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

    def test_protocol_accepts_normalized_audio_observation(self):
        response = handle_request(EdgeAiEngine(), {
            "protocol_version": "1.0", "request_id": "audio-1",
            "type": "observe_audio", "payload": {
                "attempt_id": "a1", "label": "quiet_or_low_noise",
                "voice_confidence": 0.1, "signal_quality": 0.9,
                "calibrated": True, "near_voice": False,
                "background_voice": False, "allowed_ambient": True,
                "baseline_deviation": 0.2, "duration_ms": 1000,
            },
        })
        self.assertTrue(response["ok"])
        self.assertEqual("normal", response["result"]["state"])
        self.assertFalse(response["result"]["stores_raw_media"])

    def test_invalid_confidence_is_rejected(self):
        with self.assertRaisesRegex(ValueError, "confidence"):
            EdgeAiEngine().review_event({
                "attempt_id": "a1", "event_type": "gaze_head_pose_deviation", "confidence": "high"
            })


if __name__ == "__main__":
    unittest.main()

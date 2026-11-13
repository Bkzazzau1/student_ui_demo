"""Calibration maths on synthetic embeddings (no images, no faces)."""

import math
import random
import unittest

from ai_runtime import face_identity_calibration as cal


def _unit(vector):
    norm = math.sqrt(sum(value * value for value in vector))
    return [value / norm for value in vector]


def _volunteers(count, probes_per_device=6, references=7, noise=0.08, seed=1, devices=("laptop", "tablet")):
    rng = random.Random(seed)
    dimension = 64
    people = {}
    for index in range(count):
        base = _unit([rng.gauss(0, 1) for _ in range(dimension)])

        def sample():
            return _unit([b + rng.gauss(0, noise) for b in base])

        people[f"v{index:02d}"] = {
            "references": [sample() for _ in range(references)],
            "probes": {device: [sample() for _ in range(probes_per_device)] for device in devices},
        }
    return people


class CalibrationTests(unittest.TestCase):
    def test_match_score_is_mean_of_two_best(self):
        refs = [[1.0, 0.0], [0.0, 1.0], [math.sqrt(0.5), math.sqrt(0.5)]]
        self.assertAlmostEqual(cal.match_score([1.0, 0.0], refs), (1.0 + math.sqrt(0.5)) / 2)

    def test_separated_people_get_a_threshold_that_meets_the_target(self):
        report = cal.calibrate(_volunteers(40), target_far=0.001)
        recommended = report["recommended"]
        self.assertTrue(recommended["meets_target"])
        # The claim is about the 95% upper bound, not just this sample.
        self.assertLessEqual(recommended["far"], recommended["far_upper_95"])
        self.assertLessEqual(recommended["far_upper_95"], 0.001)
        self.assertLess(recommended["frr"], 0.01)
        self.assertEqual(set(report["per_device"]), {"laptop", "tablet"})
        self.assertLess(recommended["session_frr"], 0.01)

    def test_a_small_study_cannot_claim_a_low_far(self):
        report = cal.calibrate(_volunteers(4, probes_per_device=3), target_far=0.001)
        self.assertFalse(report["recommended"]["meets_target"])

    def test_volunteers_without_enough_references_are_excluded(self):
        people = _volunteers(6)
        people["v00"]["references"] = people["v00"]["references"][:2]
        report = cal.calibrate(people, target_far=0.01)
        self.assertEqual(report["excluded_too_few_references"], ["v00"])
        self.assertEqual(report["enrolled"], 5)

    def test_rates_count_errors_at_a_threshold(self):
        rows = [("a", "a", 0.9, True), ("a", "a", 0.4, True), ("a", "b", 0.6, False), ("a", "b", 0.1, False)]
        result = cal.rates(rows, 0.5)
        self.assertEqual(result["frr"], 0.5)
        self.assertEqual(result["far"], 0.5)

    def test_consensus_needs_two_matches(self):
        rows = [("a", "a", s, True) for s in (0.9, 0.2, 0.8, 0.9, 0.1, 0.2)]
        sessions = cal.consensus_sessions(rows, threshold=0.5)
        self.assertEqual(sessions["sessions_genuine"], 2)
        self.assertAlmostEqual(sessions["session_frr"], 0.5)

    def test_no_comparisons_is_reported(self):
        self.assertIn("error", cal.calibrate({}, target_far=0.001))


if __name__ == "__main__":
    unittest.main()

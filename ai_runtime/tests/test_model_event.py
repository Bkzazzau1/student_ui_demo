import unittest

from ai_runtime.model_event import MODEL_EVENT_SCHEMA_VERSION, ModelEventV1


CORE_FIELDS = {
    "schema_version",
    "session_id",
    "event_id",
    "source_frame_id",
    "capture_timestamp_ns",
    "inference_timestamp_ns",
    "model_id",
    "model_version",
    "track_id",
    "class_id",
    "confidence",
    "quality",
    "geometry",
    "validity_interval",
    "metadata",
}


def sample_payload():
    return {
        "schema_version": MODEL_EVENT_SCHEMA_VERSION,
        "session_id": "session-001",
        "event_id": "event-001",
        "source_frame_id": 42,
        "capture_timestamp_ns": 10_200_000_000,
        "inference_timestamp_ns": 10_451_000_000,
        "model_id": "e1-object-detector",
        "model_version": "1.0.0",
        "track_id": "PERSON_TRACK_001",
        "class_id": "phone_visible",
        "confidence": 0.91,
        "quality": 0.88,
        "geometry": {
            "coordinate_space": "normalized_frame",
            "bounding_box": {"x": 0.60, "y": 0.55, "width": 0.12, "height": 0.20},
            "keypoints": [
                {"x": 0.66, "y": 0.64, "confidence": 0.80, "label": "object_center"}
            ],
            "vector": None,
            "region_id": "lower_right",
        },
        "validity_interval": {
            "start_timestamp_ns": 10_200_000_000,
            "end_timestamp_ns": 10_700_000_000,
        },
        "metadata": {"modality": "vision", "observable_behaviour_only": True},
    }


class ModelEventV1Tests(unittest.TestCase):
    def test_round_trip_preserves_frozen_core_fields_and_timestamps(self):
        event = ModelEventV1.from_dict(sample_payload())
        encoded = event.to_dict()

        self.assertEqual(CORE_FIELDS, set(encoded.keys()))
        self.assertEqual(10_200_000_000, encoded["capture_timestamp_ns"])
        self.assertEqual(10_451_000_000, encoded["inference_timestamp_ns"])
        self.assertEqual(sample_payload(), encoded)

    def test_unknown_optional_evidence_remains_null(self):
        payload = sample_payload()
        payload.update({
            "source_frame_id": None,
            "track_id": None,
            "confidence": None,
            "quality": None,
            "geometry": None,
        })

        encoded = ModelEventV1.from_dict(payload).to_dict()
        self.assertIsNone(encoded["source_frame_id"])
        self.assertIsNone(encoded["track_id"])
        self.assertIsNone(encoded["confidence"])
        self.assertIsNone(encoded["quality"])
        self.assertIsNone(encoded["geometry"])

    def test_missing_frozen_core_field_is_rejected(self):
        payload = sample_payload()
        del payload["quality"]

        with self.assertRaisesRegex(ValueError, "missing ModelEventV1 core fields: quality"):
            ModelEventV1.from_dict(payload)

    def test_inference_before_capture_is_rejected(self):
        payload = sample_payload()
        payload["inference_timestamp_ns"] = payload["capture_timestamp_ns"] - 1

        with self.assertRaisesRegex(ValueError, "inference_timestamp_ns"):
            ModelEventV1.from_dict(payload)

    def test_invalid_confidence_and_validity_interval_are_rejected(self):
        payload = sample_payload()
        payload["confidence"] = 1.1
        with self.assertRaisesRegex(ValueError, "confidence"):
            ModelEventV1.from_dict(payload)

        payload = sample_payload()
        payload["validity_interval"]["end_timestamp_ns"] = (
            payload["validity_interval"]["start_timestamp_ns"] - 1
        )
        with self.assertRaisesRegex(ValueError, "validity_interval.end_timestamp_ns"):
            ModelEventV1.from_dict(payload)


if __name__ == "__main__":
    unittest.main()

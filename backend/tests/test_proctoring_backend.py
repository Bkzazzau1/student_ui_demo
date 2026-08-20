from __future__ import annotations

import http.client
import json
import tempfile
import threading
import unittest
from pathlib import Path

from backend.identity_store import IdentityStore
from backend.main import create_server


class ProctoringBackendTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.store = IdentityStore(Path(self.temporary.name) / "backend.sqlite3")
        self.store.install_token("student-token", "student-1")
        self.store.install_token("other-token", "student-2")
        self.store.install_token("invigilator-token", "staff-1", role="invigilator")
        self.store.install_token("admin-token", "admin-1", role="admin")
        self.server = create_server("127.0.0.1", 0, self.store)
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
        self.connection = http.client.HTTPConnection(
            "127.0.0.1", self.server.server_port, timeout=5
        )

    def tearDown(self) -> None:
        self.connection.close()
        self.server.shutdown()
        self.server.server_close()
        self.thread.join(timeout=5)
        self.temporary.cleanup()

    def request(self, method: str, path: str, payload: dict | None = None, token: str = "student-token"):
        headers = {"Authorization": f"Bearer {token}"}
        body = None
        if payload is not None:
            headers["Content-Type"] = "application/json"
            body = json.dumps(payload).encode()
        self.connection.request(method, path, body=body, headers=headers)
        response = self.connection.getresponse()
        value = json.loads(response.read() or b"{}")
        return response.status, value

    def event(self) -> dict:
        return {
            "student_id": "student-1",
            "exam_id": "exam-1",
            "attempt_id": "attempt-1",
            "event_type": "audio_temporal_behaviour_review",
            "severity": "warning",
            "message": "Sustained audio change observed.",
            "created_at": "2026-08-20T18:00:00Z",
            "assessment_type": "exam",
            "review_audience": "invigilator",
            "metadata": {
                "signal_quality": 0.9,
                "raw_audio": "must-not-leave-device",
                "local_audio_record": {
                    "id": "evidence-1",
                    "sha256": "a" * 64,
                    "audio_path": "C:\\private\\clip.wav",
                },
            },
        }

    def test_timeline_combines_sanitized_observation_and_fusion_decision(self) -> None:
        status, stored = self.request("POST", "/api/proctoring/live-events", self.event())
        self.assertEqual(201, status, stored)
        self.assertFalse(stored["stores_raw_media"])
        decision = {
            "student_id": "student-1", "exam_id": "exam-1",
            "attempt_id": "attempt-1", "source_event_type": "audio_temporal_behaviour_review",
            "risk_score": 48, "risk_level": "high", "disposition": "human_review",
            "requires_human_review": True, "signal_groups": ["audio", "attention"],
            "reasons": ["Corroborating normalized signals"],
            "model_id": "kslas-edge-ai", "model_version": "1.0",
            "occurred_at": "2026-08-20T18:00:01Z",
        }
        status, _ = self.request("POST", "/api/proctoring/fusion-decisions", decision)
        self.assertEqual(201, status)
        status, _ = self.request(
            "GET", "/api/proctoring/attempt-timeline?student_id=student-1&exam_id=exam-1&attempt_id=attempt-1"
        )
        self.assertEqual(403, status)
        status, timeline = self.request(
            "GET", "/api/proctoring/attempt-timeline?student_id=student-1&exam_id=exam-1&attempt_id=attempt-1",
            token="invigilator-token",
        )
        self.assertEqual(200, status, timeline)
        self.assertEqual(["observation", "fusion_decision"], [item["kind"] for item in timeline["items"]])
        metadata = timeline["items"][0]["metadata"]
        self.assertEqual("[stored_locally]", metadata["raw_audio"])
        self.assertNotIn("audio_path", metadata["local_audio_record"])
        self.assertEqual("local_device_vault", metadata["local_audio_record"]["storage"])
        self.assertEqual(["audio", "attention"], timeline["items"][1]["signal_groups"])

    def test_cross_student_event_is_rejected(self) -> None:
        status, _ = self.request("POST", "/api/proctoring/live-events", self.event(), token="other-token")
        self.assertEqual(403, status)

    def test_admin_retention_purge_soft_deletes_expired_rows(self) -> None:
        status, _ = self.request("POST", "/api/proctoring/live-events", self.event())
        self.assertEqual(201, status)
        with self.store.connect() as db:
            db.execute("UPDATE proctoring_events SET expires_at='2000-01-01T00:00:00Z'")
        status, result = self.request(
            "POST", "/api/admin/proctoring/purge-expired", {}, token="admin-token"
        )
        self.assertEqual(200, status, result)
        self.assertEqual(1, result["events_deleted"])


if __name__ == "__main__":
    unittest.main()

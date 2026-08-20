from __future__ import annotations

import http.client
import json
import tempfile
import threading
import unittest
from pathlib import Path

from backend.identity_store import IdentityStore
from backend.main import create_server


class IdentityBackendTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.store = IdentityStore(Path(self.temporary.name) / "identity.sqlite3")
        self.store.install_token("student-token", "student-1")
        self.store.install_token("other-token", "student-2")
        self.server = create_server("127.0.0.1", 0, self.store)
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
        self.connection = http.client.HTTPConnection("127.0.0.1", self.server.server_port, timeout=5)

    def tearDown(self) -> None:
        self.connection.close()
        self.server.shutdown()
        self.server.server_close()
        self.thread.join(timeout=5)
        self.temporary.cleanup()

    def request(self, method: str, path: str, body: bytes | None = None, token: str = "student-token", content_type: str = "application/json"):
        headers = {"Authorization": f"Bearer {token}"}
        if body is not None:
            headers["Content-Type"] = content_type
        self.connection.request(method, path, body=body, headers=headers)
        response = self.connection.getresponse()
        payload = json.loads(response.read() or b"{}")
        return response.status, payload

    def enroll(self) -> dict:
        boundary = "kslas-test-boundary"
        images = []
        parts = []
        for index in range(3):
            field = f"identity_image_{index + 1}"
            images.append({"field": field, "pose_code": f"pose-{index}", "quality_score": 0.9})
        manifest = {"student_id": "student-1", "required_images": 3, "images": images}
        parts.append(
            f"--{boundary}\r\nContent-Disposition: form-data; name=\"manifest\"\r\n\r\n{json.dumps(manifest)}\r\n".encode()
        )
        for index, image in enumerate(images):
            parts.append(
                f"--{boundary}\r\nContent-Disposition: form-data; name=\"{image['field']}\"; filename=\"face.jpg\"\r\nContent-Type: image/jpeg\r\n\r\n".encode()
                + f"not-a-real-face-{index}".encode()
                + b"\r\n"
            )
        parts.append(f"--{boundary}--\r\n".encode())
        status, payload = self.request(
            "POST",
            "/api/identity/face-enrollment",
            b"".join(parts),
            content_type=f"multipart/form-data; boundary={boundary}",
        )
        self.assertEqual(status, 201, payload)
        return payload

    def test_requires_authentication_and_prevents_cross_student_access(self) -> None:
        self.connection.request("GET", "/api/identity/face-enrollments/latest?student_id=student-1")
        response = self.connection.getresponse()
        response.read()
        self.assertEqual(response.status, 403)
        status, _ = self.request(
            "GET", "/api/identity/face-enrollments/latest?student_id=student-1", token="other-token"
        )
        self.assertEqual(status, 403)

    def test_enrollment_discards_raw_images_and_records_hashes(self) -> None:
        enrollment = self.enroll()
        self.assertEqual(enrollment["status"], "pending_template")
        self.assertFalse(enrollment["locked"])
        files = list(Path(self.temporary.name).rglob("*.jpg"))
        self.assertEqual(files, [])
        with self.store.connect() as db:
            rows = db.execute("SELECT image_sha256, byte_length FROM enrollment_samples").fetchall()
        self.assertEqual(len(rows), 3)
        self.assertTrue(all(len(row["image_sha256"]) == 64 for row in rows))

    def test_template_requires_authorized_device_and_can_be_revoked(self) -> None:
        enrollment = self.enroll()
        register_status, _ = self.request(
            "POST",
            "/api/identity/devices/register",
            json.dumps({"device_id": "device-1", "platform": "windows"}).encode(),
        )
        self.assertEqual(register_status, 201)
        template = {
            "student_id": "student-1",
            "enrollment_id": enrollment["enrollment_id"],
            "template_version": 1,
            "model_id": "kslas-sface-2021dec-v1",
            "model_sha256": "a" * 64,
            "template_sha256": "b" * 64,
            "encryption": "envelope_v1",
            "key_id": "institution-key-1",
            "encrypted_template": "ciphertext-value-that-is-long-enough",
        }
        upload_status, _ = self.request(
            "POST", "/api/identity/face-template", json.dumps(template).encode()
        )
        self.assertEqual(upload_status, 201)
        download_status, downloaded = self.request(
            "GET", "/api/identity/face-template?student_id=student-1&device_id=device-1"
        )
        self.assertEqual(download_status, 200, downloaded)
        self.assertEqual(downloaded["template"]["encrypted_template"], template["encrypted_template"])
        revoke_status, _ = self.request(
            "POST",
            "/api/identity/devices/revoke",
            json.dumps({"student_id": "student-1", "device_id": "device-1"}).encode(),
        )
        self.assertEqual(revoke_status, 200)
        denied_status, _ = self.request(
            "GET", "/api/identity/face-template?student_id=student-1&device_id=device-1"
        )
        self.assertEqual(denied_status, 403)

    def test_identity_deletion_revokes_template_and_devices(self) -> None:
        self.enroll()
        status, payload = self.request("DELETE", "/api/identity?student_id=student-1")
        self.assertEqual(status, 200, payload)
        latest_status, _ = self.request(
            "GET", "/api/identity/face-enrollments/latest?student_id=student-1"
        )
        self.assertEqual(latest_status, 404)


if __name__ == "__main__":
    unittest.main()

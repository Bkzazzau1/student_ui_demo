from __future__ import annotations

import hashlib
import json
import os
from email.parser import BytesParser
from email.policy import default
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any
from urllib.parse import parse_qs, urlparse

from .identity_store import IdentityStore, Principal
from .proctoring_store import ProctoringStore

MAX_BODY_BYTES = 24 * 1024 * 1024


class IdentityApiHandler(BaseHTTPRequestHandler):
    server_version = "KSLASIdentity/1.0"
    store: IdentityStore
    proctoring_store: ProctoringStore

    def do_GET(self) -> None:
        try:
            self._dispatch_get()
        except Exception as error:  # centralized mapping; no stack traces to clients
            self._error(error)

    def do_POST(self) -> None:
        try:
            self._dispatch_post()
        except Exception as error:
            self._error(error)

    def do_DELETE(self) -> None:
        try:
            self._dispatch_delete()
        except Exception as error:
            self._error(error)

    def _dispatch_get(self) -> None:
        parsed = urlparse(self.path)
        if parsed.path == "/health":
            self._json(HTTPStatus.OK, {"status": "ready", "stores_raw_biometrics": False})
            return
        principal = self._principal()
        query = parse_qs(parsed.query)
        if parsed.path == "/api/identity/face-enrollments/latest":
            student_id = self._required_query(query, "student_id")
            self._require_student(principal, student_id)
            value = self.store.latest_enrollment(student_id)
            self._json(HTTPStatus.OK, value) if value else self._json(HTTPStatus.NOT_FOUND, {"error": "not_found"})
            return
        if parsed.path == "/api/identity/face-template":
            student_id = self._required_query(query, "student_id")
            device_id = self._required_query(query, "device_id")
            self._json(HTTPStatus.OK, self.store.download_template(principal, student_id, device_id))
            return
        if parsed.path == "/api/admin/identity/audit":
            if principal.role != "admin":
                raise PermissionError("administrator role is required")
            student_id = self._required_query(query, "student_id")
            limit = int(query.get("limit", ["200"])[0])
            self._json(HTTPStatus.OK, {"events": self.store.audit_events(student_id, limit)})
            return
        if parsed.path == "/api/proctoring/attempt-timeline":
            student_id = self._required_query(query, "student_id")
            exam_id = self._required_query(query, "exam_id")
            attempt_id = self._required_query(query, "attempt_id")
            self._json(HTTPStatus.OK, self.proctoring_store.timeline(principal, student_id, exam_id, attempt_id))
            return
        self._json(HTTPStatus.NOT_FOUND, {"error": "not_found"})

    def _dispatch_post(self) -> None:
        principal = self._principal()
        path = urlparse(self.path).path
        if path == "/api/identity/face-enrollment":
            manifest, files = self._multipart()
            image_manifest = manifest.get("images")
            if not isinstance(image_manifest, list):
                raise ValueError("manifest images must be an array")
            samples = []
            for item in image_manifest:
                if not isinstance(item, dict):
                    raise ValueError("image manifest entry must be an object")
                field = str(item.get("field", ""))
                content = files.get(field)
                if content is None:
                    raise ValueError(f"missing multipart image field {field}")
                samples.append(
                    {
                        "pose_code": str(item.get("pose_code", "")),
                        "quality_score": float(item.get("quality_score", 0.0)),
                        "image_sha256": hashlib.sha256(content).hexdigest(),
                        "byte_length": len(content),
                    }
                )
            self._json(HTTPStatus.CREATED, self.store.create_enrollment(principal, manifest, samples))
            return
        payload = self._json_body()
        if path == "/api/identity/devices/register":
            self._json(
                HTTPStatus.CREATED,
                self.store.register_device(
                    principal,
                    self._required(payload, "device_id"),
                    self._required(payload, "platform"),
                    payload.get("public_key"),
                ),
            )
            return
        if path == "/api/identity/devices/revoke":
            student_id = self._required(payload, "student_id")
            self._require_student(principal, student_id)
            revoked = self.store.revoke_device(principal, student_id, self._required(payload, "device_id"))
            self._json(HTTPStatus.OK, {"revoked": revoked})
            return
        if path == "/api/identity/face-template":
            self._json(HTTPStatus.CREATED, self.store.put_template(principal, payload))
            return
        if path == "/api/admin/identity/purge-expired":
            self._json(HTTPStatus.OK, self.store.purge_expired(principal))
            return
        if path == "/api/proctoring/live-events":
            self._json(HTTPStatus.CREATED, self.proctoring_store.add_event(principal, payload))
            return
        if path == "/api/proctoring/fusion-decisions":
            self._json(HTTPStatus.CREATED, self.proctoring_store.add_fusion_decision(principal, payload))
            return
        if path == "/api/admin/proctoring/purge-expired":
            self._json(HTTPStatus.OK, self.proctoring_store.purge_expired(principal))
            return
        self._json(HTTPStatus.NOT_FOUND, {"error": "not_found"})

    def _dispatch_delete(self) -> None:
        principal = self._principal()
        parsed = urlparse(self.path)
        if parsed.path != "/api/identity":
            self._json(HTTPStatus.NOT_FOUND, {"error": "not_found"})
            return
        student_id = self._required_query(parse_qs(parsed.query), "student_id")
        self.store.delete_identity(principal, student_id)
        self._json(HTTPStatus.OK, {"deleted": True, "student_id": student_id})

    def _principal(self) -> Principal:
        authorization = self.headers.get("Authorization", "")
        if not authorization.startswith("Bearer "):
            raise PermissionError("Bearer access token is required")
        principal = self.store.authenticate(authorization[7:].strip())
        if principal is None:
            raise PermissionError("access token is invalid or expired")
        return principal

    def _require_student(self, principal: Principal, student_id: str) -> None:
        if not self.store.authorize_student(principal, student_id):
            raise PermissionError("student identity does not match access token")

    def _read_body(self) -> bytes:
        length = int(self.headers.get("Content-Length", "0"))
        if length <= 0 or length > MAX_BODY_BYTES:
            raise ValueError("request body has an invalid length")
        return self.rfile.read(length)

    def _json_body(self) -> dict[str, Any]:
        if "application/json" not in self.headers.get("Content-Type", ""):
            raise ValueError("Content-Type must be application/json")
        value = json.loads(self._read_body())
        if not isinstance(value, dict):
            raise ValueError("JSON body must be an object")
        return value

    def _multipart(self) -> tuple[dict[str, Any], dict[str, bytes]]:
        content_type = self.headers.get("Content-Type", "")
        if not content_type.startswith("multipart/form-data"):
            raise ValueError("Content-Type must be multipart/form-data")
        message = BytesParser(policy=default).parsebytes(
            f"Content-Type: {content_type}\r\nMIME-Version: 1.0\r\n\r\n".encode() + self._read_body()
        )
        manifest: dict[str, Any] | None = None
        files: dict[str, bytes] = {}
        for part in message.iter_parts():
            name = part.get_param("name", header="content-disposition")
            content = part.get_payload(decode=True) or b""
            if name == "manifest":
                parsed = json.loads(content.decode("utf-8"))
                if not isinstance(parsed, dict):
                    raise ValueError("manifest must be a JSON object")
                manifest = parsed
            elif name:
                files[name] = content
        if manifest is None:
            raise ValueError("multipart manifest is required")
        return manifest, files

    def _required(self, value: dict[str, Any], key: str) -> str:
        result = str(value.get(key, "")).strip()
        if not result:
            raise ValueError(f"{key} is required")
        return result

    def _required_query(self, query: dict[str, list[str]], key: str) -> str:
        value = query.get(key, [""])[0].strip()
        if not value:
            raise ValueError(f"{key} is required")
        return value

    def _json(self, status: HTTPStatus, value: Any) -> None:
        body = json.dumps(value, separators=(",", ":")).encode()
        self.send_response(status.value)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.end_headers()
        self.wfile.write(body)

    def _error(self, error: Exception) -> None:
        if isinstance(error, PermissionError):
            status, code = HTTPStatus.FORBIDDEN, "forbidden"
        elif isinstance(error, LookupError):
            status, code = HTTPStatus.NOT_FOUND, "not_found"
        elif isinstance(error, (ValueError, json.JSONDecodeError)):
            status, code = HTTPStatus.BAD_REQUEST, "invalid_request"
        else:
            status, code = HTTPStatus.INTERNAL_SERVER_ERROR, "internal_error"
        message = str(error) if status != HTTPStatus.INTERNAL_SERVER_ERROR else "internal server error"
        self._json(status, {"error": code, "message": message})

    def log_message(self, format: str, *args: object) -> None:
        return


def create_server(host: str, port: int, store: IdentityStore) -> ThreadingHTTPServer:
    handler = type("ConfiguredIdentityApiHandler", (IdentityApiHandler,), {"store": store, "proctoring_store": ProctoringStore(store)})
    return ThreadingHTTPServer((host, port), handler)


def main() -> None:
    database = os.environ.get("KSLAS_IDENTITY_DB", "backend/data/identity.sqlite3")
    store = IdentityStore(database)
    tokens = json.loads(os.environ.get("KSLAS_API_TOKENS_JSON", "{}"))
    for token, identity in tokens.items():
        if isinstance(identity, str):
            store.install_token(token, identity)
        elif isinstance(identity, dict):
            store.install_token(token, str(identity["student_id"]), str(identity.get("role", "student")), int(identity.get("hours", 12)))
    host = os.environ.get("KSLAS_BACKEND_HOST", "127.0.0.1")
    port = int(os.environ.get("KSLAS_BACKEND_PORT", "8080"))
    server = create_server(host, port, store)
    print(f"K-SLAS identity backend listening on http://{host}:{port}", flush=True)
    server.serve_forever()


if __name__ == "__main__":
    main()

from __future__ import annotations

import hashlib
import json
import secrets
import sqlite3
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any


def utc_now() -> datetime:
    return datetime.now(timezone.utc)


def iso(value: datetime) -> str:
    return value.astimezone(timezone.utc).isoformat().replace("+00:00", "Z")


@dataclass(frozen=True)
class Principal:
    student_id: str
    role: str = "student"


class ClosingConnection(sqlite3.Connection):
    def __exit__(self, exc_type: object, exc_value: object, traceback: object) -> bool:
        try:
            return bool(super().__exit__(exc_type, exc_value, traceback))
        finally:
            self.close()


class IdentityStore:
    def __init__(self, database_path: str | Path) -> None:
        self.database_path = str(database_path)
        self._initialize()

    def connect(self) -> sqlite3.Connection:
        connection = sqlite3.connect(
            self.database_path, timeout=15, factory=ClosingConnection
        )
        connection.row_factory = sqlite3.Row
        connection.execute("PRAGMA foreign_keys = ON")
        connection.execute("PRAGMA journal_mode = WAL")
        return connection

    def _initialize(self) -> None:
        Path(self.database_path).parent.mkdir(parents=True, exist_ok=True)
        with self.connect() as db:
            db.executescript(
                """
                CREATE TABLE IF NOT EXISTS api_tokens (
                    token_hash TEXT PRIMARY KEY,
                    student_id TEXT NOT NULL,
                    role TEXT NOT NULL,
                    expires_at TEXT NOT NULL,
                    revoked_at TEXT
                );
                CREATE TABLE IF NOT EXISTS devices (
                    device_id TEXT NOT NULL,
                    student_id TEXT NOT NULL,
                    platform TEXT NOT NULL,
                    public_key TEXT,
                    authorized_at TEXT NOT NULL,
                    last_seen_at TEXT NOT NULL,
                    revoked_at TEXT,
                    PRIMARY KEY (device_id, student_id)
                );
                CREATE TABLE IF NOT EXISTS enrollments (
                    enrollment_id TEXT PRIMARY KEY,
                    student_id TEXT NOT NULL,
                    status TEXT NOT NULL,
                    required_images INTEGER NOT NULL,
                    uploaded_images INTEGER NOT NULL,
                    captured_at TEXT,
                    created_at TEXT NOT NULL,
                    expires_at TEXT NOT NULL,
                    deleted_at TEXT
                );
                CREATE INDEX IF NOT EXISTS enrollment_student_idx
                    ON enrollments(student_id, created_at DESC);
                CREATE TABLE IF NOT EXISTS enrollment_samples (
                    enrollment_id TEXT NOT NULL,
                    pose_code TEXT NOT NULL,
                    quality_score REAL NOT NULL,
                    image_sha256 TEXT NOT NULL,
                    byte_length INTEGER NOT NULL,
                    PRIMARY KEY (enrollment_id, pose_code),
                    FOREIGN KEY (enrollment_id) REFERENCES enrollments(enrollment_id)
                );
                CREATE TABLE IF NOT EXISTS face_templates (
                    student_id TEXT PRIMARY KEY,
                    enrollment_id TEXT NOT NULL,
                    template_version INTEGER NOT NULL,
                    model_id TEXT NOT NULL,
                    model_sha256 TEXT NOT NULL,
                    template_sha256 TEXT NOT NULL,
                    encryption TEXT NOT NULL,
                    key_id TEXT NOT NULL,
                    encrypted_template TEXT NOT NULL,
                    created_at TEXT NOT NULL,
                    expires_at TEXT NOT NULL,
                    revoked_at TEXT,
                    FOREIGN KEY (enrollment_id) REFERENCES enrollments(enrollment_id)
                );
                CREATE TABLE IF NOT EXISTS audit_events (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    occurred_at TEXT NOT NULL,
                    actor_student_id TEXT NOT NULL,
                    actor_role TEXT NOT NULL,
                    action TEXT NOT NULL,
                    target_student_id TEXT NOT NULL,
                    device_id TEXT,
                    outcome TEXT NOT NULL,
                    details_json TEXT NOT NULL
                );
                """
            )

    def install_token(
        self, token: str, student_id: str, role: str = "student", hours: int = 12
    ) -> None:
        digest = hashlib.sha256(token.encode()).hexdigest()
        with self.connect() as db:
            db.execute(
                "INSERT OR REPLACE INTO api_tokens VALUES (?, ?, ?, ?, NULL)",
                (digest, student_id, role, iso(utc_now() + timedelta(hours=hours))),
            )

    def authenticate(self, token: str) -> Principal | None:
        digest = hashlib.sha256(token.encode()).hexdigest()
        with self.connect() as db:
            row = db.execute(
                "SELECT * FROM api_tokens WHERE token_hash = ?", (digest,)
            ).fetchone()
        if not row or row["revoked_at"] or row["expires_at"] <= iso(utc_now()):
            return None
        return Principal(row["student_id"], row["role"])

    def authorize_student(self, principal: Principal, student_id: str) -> bool:
        return principal.role == "admin" or secrets.compare_digest(
            principal.student_id, student_id
        )

    def register_device(
        self, principal: Principal, device_id: str, platform: str, public_key: str | None
    ) -> dict[str, Any]:
        now = iso(utc_now())
        with self.connect() as db:
            db.execute(
                """INSERT INTO devices VALUES (?, ?, ?, ?, ?, ?, NULL)
                   ON CONFLICT(device_id, student_id) DO UPDATE SET
                   platform=excluded.platform, public_key=excluded.public_key,
                   last_seen_at=excluded.last_seen_at, revoked_at=NULL""",
                (device_id, principal.student_id, platform, public_key, now, now),
            )
        self.audit(principal, "device.register", principal.student_id, device_id, "allowed")
        return {"device_id": device_id, "student_id": principal.student_id, "authorized": True}

    def device_authorized(self, student_id: str, device_id: str) -> bool:
        with self.connect() as db:
            row = db.execute(
                "SELECT revoked_at FROM devices WHERE student_id=? AND device_id=?",
                (student_id, device_id),
            ).fetchone()
        return bool(row and row["revoked_at"] is None)

    def revoke_device(self, principal: Principal, student_id: str, device_id: str) -> bool:
        now = iso(utc_now())
        with self.connect() as db:
            changed = db.execute(
                "UPDATE devices SET revoked_at=? WHERE student_id=? AND device_id=? AND revoked_at IS NULL",
                (now, student_id, device_id),
            ).rowcount
        self.audit(principal, "device.revoke", student_id, device_id, "allowed")
        return changed > 0

    def create_enrollment(
        self,
        principal: Principal,
        manifest: dict[str, Any],
        samples: list[dict[str, Any]],
    ) -> dict[str, Any]:
        student_id = str(manifest.get("student_id", "")).strip()
        required = int(manifest.get("required_images", 6))
        if not self.authorize_student(principal, student_id):
            raise PermissionError("student identity does not match access token")
        if required < 3 or required > 12 or len(samples) != required:
            raise ValueError("enrollment requires the declared number of samples")
        poses = {str(sample["pose_code"]) for sample in samples}
        if len(poses) != len(samples):
            raise ValueError("enrollment pose codes must be unique")
        enrollment_id = secrets.token_urlsafe(18)
        now = utc_now()
        with self.connect() as db:
            db.execute(
                "INSERT INTO enrollments VALUES (?, ?, ?, ?, ?, ?, ?, ?, NULL)",
                (
                    enrollment_id,
                    student_id,
                    "pending_template",
                    required,
                    len(samples),
                    manifest.get("captured_at"),
                    iso(now),
                    iso(now + timedelta(days=365)),
                ),
            )
            db.executemany(
                "INSERT INTO enrollment_samples VALUES (?, ?, ?, ?, ?)",
                [
                    (
                        enrollment_id,
                        str(sample["pose_code"]),
                        float(sample["quality_score"]),
                        str(sample["image_sha256"]),
                        int(sample["byte_length"]),
                    )
                    for sample in samples
                ],
            )
        self.audit(principal, "enrollment.create", student_id, None, "allowed")
        return self.latest_enrollment(student_id) or {}

    def latest_enrollment(self, student_id: str) -> dict[str, Any] | None:
        with self.connect() as db:
            row = db.execute(
                """SELECT * FROM enrollments WHERE student_id=? AND deleted_at IS NULL
                   ORDER BY created_at DESC LIMIT 1""",
                (student_id,),
            ).fetchone()
            if not row:
                return None
            samples = db.execute(
                "SELECT pose_code, quality_score FROM enrollment_samples WHERE enrollment_id=?",
                (row["enrollment_id"],),
            ).fetchall()
        return {
            "enrollment_id": row["enrollment_id"],
            "student_id": row["student_id"],
            "status": row["status"],
            "locked": row["status"] == "active_locked",
            "message": "Enrollment is active." if row["status"] == "active_locked" else "Enrollment is waiting for an encrypted template.",
            "required_images": row["required_images"],
            "uploaded_images": row["uploaded_images"],
            "expires_at": row["expires_at"],
            "images": [
                {"pose_code": sample["pose_code"], "quality_score": sample["quality_score"], "view_url": ""}
                for sample in samples
            ],
        }

    def put_template(self, principal: Principal, package: dict[str, Any]) -> dict[str, Any]:
        student_id = str(package.get("student_id", "")).strip()
        enrollment_id = str(package.get("enrollment_id", "")).strip()
        if not self.authorize_student(principal, student_id):
            raise PermissionError("student identity does not match access token")
        if package.get("encryption") != "envelope_v1":
            raise ValueError("only envelope_v1 encrypted templates are accepted")
        for name in ("model_sha256", "template_sha256"):
            value = str(package.get(name, ""))
            if len(value) != 64 or any(char not in "0123456789abcdefABCDEF" for char in value):
                raise ValueError(f"{name} must be a SHA-256 hexadecimal digest")
        encrypted = str(package.get("encrypted_template", ""))
        if len(encrypted) < 32 or len(encrypted) > 1_000_000:
            raise ValueError("encrypted template has an invalid length")
        now = utc_now()
        expires = iso(now + timedelta(days=365))
        with self.connect() as db:
            enrollment = db.execute(
                "SELECT student_id FROM enrollments WHERE enrollment_id=? AND deleted_at IS NULL",
                (enrollment_id,),
            ).fetchone()
            if not enrollment or enrollment["student_id"] != student_id:
                raise ValueError("enrollment does not belong to this student")
            db.execute(
                """INSERT OR REPLACE INTO face_templates VALUES
                   (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NULL)""",
                (
                    student_id,
                    enrollment_id,
                    int(package.get("template_version", 1)),
                    str(package.get("model_id", "")),
                    str(package["model_sha256"]).lower(),
                    str(package["template_sha256"]).lower(),
                    "envelope_v1",
                    str(package.get("key_id", "")),
                    encrypted,
                    iso(now),
                    expires,
                ),
            )
            db.execute(
                "UPDATE enrollments SET status='active_locked' WHERE enrollment_id=?",
                (enrollment_id,),
            )
        self.audit(principal, "template.upload", student_id, None, "allowed")
        return self.get_template(student_id)

    def get_template(self, student_id: str) -> dict[str, Any]:
        with self.connect() as db:
            row = db.execute(
                "SELECT * FROM face_templates WHERE student_id=? AND revoked_at IS NULL",
                (student_id,),
            ).fetchone()
        if not row or row["expires_at"] <= iso(utc_now()):
            raise LookupError("active face template was not found")
        return dict(row)

    def download_template(
        self, principal: Principal, student_id: str, device_id: str
    ) -> dict[str, Any]:
        if not self.authorize_student(principal, student_id):
            raise PermissionError("student identity does not match access token")
        if not self.device_authorized(student_id, device_id):
            self.audit(principal, "template.download", student_id, device_id, "denied")
            raise PermissionError("device is not authorized for this student")
        package = self.get_template(student_id)
        self.audit(principal, "template.download", student_id, device_id, "allowed")
        return {"template": package}

    def delete_identity(self, principal: Principal, student_id: str) -> None:
        if not self.authorize_student(principal, student_id):
            raise PermissionError("student identity does not match access token")
        now = iso(utc_now())
        with self.connect() as db:
            db.execute("UPDATE enrollments SET deleted_at=? WHERE student_id=?", (now, student_id))
            db.execute("UPDATE face_templates SET revoked_at=? WHERE student_id=?", (now, student_id))
            db.execute("UPDATE devices SET revoked_at=? WHERE student_id=?", (now, student_id))
        self.audit(principal, "identity.delete", student_id, None, "allowed")

    def audit_events(self, student_id: str, limit: int = 200) -> list[dict[str, Any]]:
        with self.connect() as db:
            rows = db.execute(
                """SELECT occurred_at, actor_student_id, actor_role, action,
                          target_student_id, device_id, outcome, details_json
                   FROM audit_events WHERE target_student_id=?
                   ORDER BY id DESC LIMIT ?""",
                (student_id, max(1, min(limit, 1000))),
            ).fetchall()
        return [
            {
                **{key: row[key] for key in row.keys() if key != "details_json"},
                "details": json.loads(row["details_json"]),
            }
            for row in rows
        ]

    def purge_expired(self, principal: Principal) -> dict[str, int]:
        if principal.role != "admin":
            raise PermissionError("administrator role is required")
        now = iso(utc_now())
        with self.connect() as db:
            templates = db.execute(
                "UPDATE face_templates SET revoked_at=? WHERE expires_at<=? AND revoked_at IS NULL",
                (now, now),
            ).rowcount
            enrollments = db.execute(
                "UPDATE enrollments SET deleted_at=? WHERE expires_at<=? AND deleted_at IS NULL",
                (now, now),
            ).rowcount
        self.audit(principal, "retention.purge", principal.student_id, None, "allowed", {"templates": templates, "enrollments": enrollments})
        return {"templates_revoked": templates, "enrollments_deleted": enrollments}

    def audit(
        self,
        principal: Principal,
        action: str,
        target_student_id: str,
        device_id: str | None,
        outcome: str,
        details: dict[str, Any] | None = None,
    ) -> None:
        with self.connect() as db:
            db.execute(
                "INSERT INTO audit_events(occurred_at, actor_student_id, actor_role, action, target_student_id, device_id, outcome, details_json) VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
                (iso(utc_now()), principal.student_id, principal.role, action, target_student_id, device_id, outcome, json.dumps(details or {}, separators=(",", ":"))),
            )

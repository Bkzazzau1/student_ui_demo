# K-SLAS identity backend

The service stores enrollment metadata and client-encrypted face templates. Raw
enrollment photographs are hashed during request processing and discarded.

## Development run

```powershell
$env:KSLAS_API_TOKENS_JSON='{"local-student-token":"KASU/STU/2026/001"}'
python -m backend.main
```

Production deployments must provide tokens from the institution identity
provider, terminate TLS at a trusted reverse proxy, protect the SQLite file (or
replace it with the institution database), rotate envelope-encryption keys, and
back up audit records. Do not expose this development HTTP listener publicly.

Implemented endpoints:

- `GET /health`
- `POST /api/identity/devices/register`
- `POST /api/identity/devices/revoke`
- `POST /api/identity/face-enrollment`
- `GET /api/identity/face-enrollments/latest`
- `POST /api/identity/face-template`
- `GET /api/identity/face-template`
- `DELETE /api/identity`
- `GET /api/admin/identity/audit`
- `POST /api/admin/identity/purge-expired`

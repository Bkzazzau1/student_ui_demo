# K-SLAS Edge AI Runtime

This directory contains the local Python reasoning layer. It consumes normalized
exam events, keeps bounded attempt-level context, and returns explainable review
recommendations. It does not access cameras, microphones, files, or operating
system controls directly; Dart supplies events and Rust remains the authority
for device actions and durable evidence.

## Run

From the repository root:

```powershell
python -m ai_runtime
```

The process uses newline-delimited JSON over standard input/output. Each request
must contain `protocol_version`, `request_id`, and `type`.

```json
{"protocol_version":"1.0","request_id":"1","type":"health"}
{"protocol_version":"1.0","request_id":"2","type":"review_event","payload":{"attempt_id":"attempt-1","event_type":"gaze_head_pose_deviation","confidence":0.82,"occurred_at":"2026-08-19T12:00:00Z"}}
```

Run tests with:

```powershell
python -m unittest discover -s ai_runtime/tests -v
```


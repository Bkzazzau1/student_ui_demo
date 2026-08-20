from __future__ import annotations

import json
import sys
from typing import Any, TextIO

from .engine import EdgeAiEngine

PROTOCOL_VERSION = "1.0"


def handle_request(engine: EdgeAiEngine, request: dict[str, Any]) -> dict[str, Any]:
    request_id = request.get("request_id")
    if request.get("protocol_version") != PROTOCOL_VERSION:
        raise ValueError(f"protocol_version must be {PROTOCOL_VERSION}")
    if not isinstance(request_id, str) or not request_id:
        raise ValueError("request_id must be a non-empty string")

    request_type = request.get("type")
    if request_type == "health":
        result = {"status": "ready", "runtime": "kslas-edge-ai", "stores_raw_media": False}
    elif request_type == "review_event":
        payload = request.get("payload")
        if not isinstance(payload, dict):
            raise ValueError("payload must be an object")
        result = engine.review_event(payload).to_dict()
    elif request_type == "observe_gaze":
        payload = request.get("payload")
        if not isinstance(payload, dict):
            raise ValueError("payload must be an object")
        result = engine.observe_gaze(payload)
    elif request_type == "clear_attempt":
        payload = request.get("payload")
        if not isinstance(payload, dict):
            raise ValueError("payload must be an object")
        attempt_id = payload.get("attempt_id")
        if not isinstance(attempt_id, str) or not attempt_id:
            raise ValueError("attempt_id must be a non-empty string")
        result = {"cleared": engine.clear_attempt(attempt_id)}
    else:
        raise ValueError("unsupported request type")
    return {"protocol_version": PROTOCOL_VERSION, "request_id": request_id, "ok": True, "result": result}


def serve(input_stream: TextIO, output_stream: TextIO) -> None:
    engine = EdgeAiEngine()
    for line in input_stream:
        if not line.strip():
            continue
        request_id: Any = None
        try:
            request = json.loads(line)
            if not isinstance(request, dict):
                raise ValueError("request must be an object")
            request_id = request.get("request_id")
            response = handle_request(engine, request)
        except (ValueError, json.JSONDecodeError) as error:
            response = {
                "protocol_version": PROTOCOL_VERSION,
                "request_id": request_id,
                "ok": False,
                "error": {"code": "invalid_request", "message": str(error)},
            }
        output_stream.write(json.dumps(response, separators=(",", ":")) + "\n")
        output_stream.flush()


def main() -> None:
    serve(sys.stdin, sys.stdout)

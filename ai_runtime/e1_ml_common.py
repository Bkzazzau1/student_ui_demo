"""Shared development-only E1 artifact helpers; no runtime imports."""

import hashlib
import json
import math
from pathlib import Path


def load(path):
    value = json.loads(Path(path).read_text(encoding="utf-8"),
                       parse_constant=lambda value: fail(f"Non-finite JSON: {value}"))
    if not isinstance(value, dict):
        raise ValueError("Expected a JSON object")
    return value


def fail(message):
    raise ValueError(message)


def save(path, value):
    path = Path(path)
    text = json.dumps(value, indent=2, sort_keys=True, allow_nan=False) + "\n"
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("x", encoding="utf-8") as handle:
        handle.write(text)


def sha256(path):
    with Path(path).open("rb") as handle:
        return hashlib.file_digest(handle, "sha256").hexdigest()


def number(value, name, minimum=0, maximum=1):
    if (isinstance(value, bool) or not isinstance(value, (int, float))
            or not math.isfinite(value) or not minimum <= value <= maximum):
        raise ValueError(f"Invalid {name}: {value!r}")
    return value


def integer(value, name, minimum=1):
    if type(value) is not int or value < minimum:
        raise ValueError(f"{name} must be an integer >= {minimum}")
    return value


def required(value, name):
    if not isinstance(value, str) or not value.strip():
        raise ValueError(f"{name} must be non-empty text")
    return value

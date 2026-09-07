from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any, Mapping

MODEL_EVENT_SCHEMA_VERSION = "1.0"


@dataclass(frozen=True)
class BoundingBoxV1:
    x: float
    y: float
    width: float
    height: float

    @classmethod
    def from_dict(cls, value: Mapping[str, Any]) -> "BoundingBoxV1":
        box = cls(
            x=_finite_number(value.get("x"), "geometry.bounding_box.x"),
            y=_finite_number(value.get("y"), "geometry.bounding_box.y"),
            width=_finite_number(value.get("width"), "geometry.bounding_box.width"),
            height=_finite_number(value.get("height"), "geometry.bounding_box.height"),
        )
        if box.width < 0 or box.height < 0:
            raise ValueError("geometry bounding-box width/height must be non-negative")
        return box

    def to_dict(self) -> dict[str, float]:
        return {"x": self.x, "y": self.y, "width": self.width, "height": self.height}


@dataclass(frozen=True)
class KeypointV1:
    x: float
    y: float
    confidence: float | None = None
    label: str | None = None

    @classmethod
    def from_dict(cls, value: Mapping[str, Any], index: int) -> "KeypointV1":
        confidence = _optional_unit_interval(
            value.get("confidence"), f"geometry.keypoints[{index}].confidence"
        )
        label = _optional_text(value.get("label"), f"geometry.keypoints[{index}].label")
        return cls(
            x=_finite_number(value.get("x"), f"geometry.keypoints[{index}].x"),
            y=_finite_number(value.get("y"), f"geometry.keypoints[{index}].y"),
            confidence=confidence,
            label=label,
        )

    def to_dict(self) -> dict[str, Any]:
        return {
            "x": self.x,
            "y": self.y,
            "confidence": self.confidence,
            "label": self.label,
        }


@dataclass(frozen=True)
class ModelGeometryV1:
    coordinate_space: str | None = None
    bounding_box: BoundingBoxV1 | None = None
    keypoints: tuple[KeypointV1, ...] = ()
    vector: tuple[float, ...] | None = None
    region_id: str | None = None

    @classmethod
    def from_dict(cls, value: Mapping[str, Any]) -> "ModelGeometryV1":
        coordinate_space = _optional_text(
            value.get("coordinate_space"), "geometry.coordinate_space"
        )
        region_id = _optional_text(value.get("region_id"), "geometry.region_id")

        box_value = value.get("bounding_box")
        if box_value is not None and not isinstance(box_value, Mapping):
            raise ValueError("geometry.bounding_box must be an object or null")
        bounding_box = BoundingBoxV1.from_dict(box_value) if box_value is not None else None

        keypoint_values = value.get("keypoints", [])
        if not isinstance(keypoint_values, list):
            raise ValueError("geometry.keypoints must be an array")
        keypoints: list[KeypointV1] = []
        for index, item in enumerate(keypoint_values):
            if not isinstance(item, Mapping):
                raise ValueError(f"geometry.keypoints[{index}] must be an object")
            keypoints.append(KeypointV1.from_dict(item, index))

        vector_value = value.get("vector")
        vector: tuple[float, ...] | None = None
        if vector_value is not None:
            if not isinstance(vector_value, list):
                raise ValueError("geometry.vector must be an array or null")
            vector = tuple(
                _finite_number(item, f"geometry.vector[{index}]")
                for index, item in enumerate(vector_value)
            )

        return cls(
            coordinate_space=coordinate_space,
            bounding_box=bounding_box,
            keypoints=tuple(keypoints),
            vector=vector,
            region_id=region_id,
        )

    def to_dict(self) -> dict[str, Any]:
        return {
            "coordinate_space": self.coordinate_space,
            "bounding_box": self.bounding_box.to_dict() if self.bounding_box else None,
            "keypoints": [keypoint.to_dict() for keypoint in self.keypoints],
            "vector": list(self.vector) if self.vector is not None else None,
            "region_id": self.region_id,
        }


@dataclass(frozen=True)
class ValidityIntervalV1:
    start_timestamp_ns: int
    end_timestamp_ns: int | None = None

    @classmethod
    def from_dict(cls, value: Mapping[str, Any]) -> "ValidityIntervalV1":
        start = _non_negative_int(value.get("start_timestamp_ns"), "validity_interval.start_timestamp_ns")
        end_value = value.get("end_timestamp_ns")
        end = (
            _non_negative_int(end_value, "validity_interval.end_timestamp_ns")
            if end_value is not None
            else None
        )
        interval = cls(start_timestamp_ns=start, end_timestamp_ns=end)
        interval.validate()
        return interval

    def validate(self) -> None:
        if self.end_timestamp_ns is not None and self.end_timestamp_ns < self.start_timestamp_ns:
            raise ValueError(
                "validity_interval.end_timestamp_ns must be greater than or equal to start_timestamp_ns"
            )

    def to_dict(self) -> dict[str, int | None]:
        return {
            "start_timestamp_ns": self.start_timestamp_ns,
            "end_timestamp_ns": self.end_timestamp_ns,
        }


@dataclass(frozen=True)
class ModelEventV1:
    schema_version: str
    session_id: str
    event_id: str
    source_frame_id: int | None
    capture_timestamp_ns: int
    inference_timestamp_ns: int
    model_id: str
    model_version: str
    track_id: str | None
    class_id: str
    confidence: float | None
    quality: float | None
    geometry: ModelGeometryV1 | None
    validity_interval: ValidityIntervalV1
    metadata: dict[str, Any] = field(default_factory=dict)

    @classmethod
    def from_dict(cls, value: Mapping[str, Any]) -> "ModelEventV1":
        _require_core_fields(value)

        source_frame_value = value.get("source_frame_id")
        source_frame_id = (
            _non_negative_int(source_frame_value, "source_frame_id")
            if source_frame_value is not None
            else None
        )

        geometry_value = value.get("geometry")
        if geometry_value is not None and not isinstance(geometry_value, Mapping):
            raise ValueError("geometry must be an object or null")
        geometry = ModelGeometryV1.from_dict(geometry_value) if geometry_value is not None else None

        validity_value = value.get("validity_interval")
        if not isinstance(validity_value, Mapping):
            raise ValueError("validity_interval must be an object")

        metadata_value = value.get("metadata")
        if not isinstance(metadata_value, dict):
            raise ValueError("metadata must be an object")

        event = cls(
            schema_version=_required_text(value.get("schema_version"), "schema_version"),
            session_id=_required_text(value.get("session_id"), "session_id"),
            event_id=_required_text(value.get("event_id"), "event_id"),
            source_frame_id=source_frame_id,
            capture_timestamp_ns=_non_negative_int(
                value.get("capture_timestamp_ns"), "capture_timestamp_ns"
            ),
            inference_timestamp_ns=_non_negative_int(
                value.get("inference_timestamp_ns"), "inference_timestamp_ns"
            ),
            model_id=_required_text(value.get("model_id"), "model_id"),
            model_version=_required_text(value.get("model_version"), "model_version"),
            track_id=_optional_text(value.get("track_id"), "track_id"),
            class_id=_required_text(value.get("class_id"), "class_id"),
            confidence=_optional_unit_interval(value.get("confidence"), "confidence"),
            quality=_optional_unit_interval(value.get("quality"), "quality"),
            geometry=geometry,
            validity_interval=ValidityIntervalV1.from_dict(validity_value),
            metadata=dict(metadata_value),
        )
        event.validate()
        return event

    def validate(self) -> None:
        if self.schema_version != MODEL_EVENT_SCHEMA_VERSION:
            raise ValueError(f"schema_version must be {MODEL_EVENT_SCHEMA_VERSION}")
        _required_text(self.session_id, "session_id")
        _required_text(self.event_id, "event_id")
        _required_text(self.model_id, "model_id")
        _required_text(self.model_version, "model_version")
        _required_text(self.class_id, "class_id")
        if self.track_id is not None:
            _required_text(self.track_id, "track_id")
        _non_negative_int(self.capture_timestamp_ns, "capture_timestamp_ns")
        _non_negative_int(self.inference_timestamp_ns, "inference_timestamp_ns")
        if self.inference_timestamp_ns < self.capture_timestamp_ns:
            raise ValueError(
                "inference_timestamp_ns must be greater than or equal to capture_timestamp_ns"
            )
        _optional_unit_interval(self.confidence, "confidence")
        _optional_unit_interval(self.quality, "quality")
        self.validity_interval.validate()

    def to_dict(self) -> dict[str, Any]:
        self.validate()
        return {
            "schema_version": self.schema_version,
            "session_id": self.session_id,
            "event_id": self.event_id,
            "source_frame_id": self.source_frame_id,
            "capture_timestamp_ns": self.capture_timestamp_ns,
            "inference_timestamp_ns": self.inference_timestamp_ns,
            "model_id": self.model_id,
            "model_version": self.model_version,
            "track_id": self.track_id,
            "class_id": self.class_id,
            "confidence": self.confidence,
            "quality": self.quality,
            "geometry": self.geometry.to_dict() if self.geometry else None,
            "validity_interval": self.validity_interval.to_dict(),
            "metadata": dict(self.metadata),
        }


_CORE_FIELDS = {
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


def _require_core_fields(value: Mapping[str, Any]) -> None:
    missing = sorted(_CORE_FIELDS - set(value.keys()))
    if missing:
        raise ValueError("missing ModelEventV1 core fields: " + ", ".join(missing))


def _required_text(value: Any, field_name: str) -> str:
    if not isinstance(value, str) or not value.strip():
        raise ValueError(f"{field_name} must be a non-empty string")
    return value.strip()


def _optional_text(value: Any, field_name: str) -> str | None:
    if value is None:
        return None
    return _required_text(value, field_name)


def _non_negative_int(value: Any, field_name: str) -> int:
    if isinstance(value, bool) or not isinstance(value, int):
        raise ValueError(f"{field_name} must be an integer")
    if value < 0:
        raise ValueError(f"{field_name} must be non-negative")
    return value


def _finite_number(value: Any, field_name: str) -> float:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise ValueError(f"{field_name} must be a number")
    number = float(value)
    if number != number or number in (float("inf"), float("-inf")):
        raise ValueError(f"{field_name} must be finite")
    return number


def _optional_unit_interval(value: Any, field_name: str) -> float | None:
    if value is None:
        return None
    number = _finite_number(value, field_name)
    if not 0.0 <= number <= 1.0:
        raise ValueError(f"{field_name} must be between 0 and 1")
    return number

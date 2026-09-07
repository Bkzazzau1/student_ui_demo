use std::collections::BTreeMap;

use serde::{Deserialize, Serialize};
use serde_json::Value;

pub const MODEL_EVENT_SCHEMA_VERSION: &str = "1.0";
pub const MODEL_EVENT_CORE_FIELDS: [&str; 15] = [
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
];

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct BoundingBoxV1 {
    pub x: f32,
    pub y: f32,
    pub width: f32,
    pub height: f32,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct KeypointV1 {
    pub x: f32,
    pub y: f32,
    #[serde(default)]
    pub confidence: Option<f32>,
    #[serde(default)]
    pub label: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Default)]
pub struct ModelGeometryV1 {
    #[serde(default)]
    pub coordinate_space: Option<String>,
    #[serde(default)]
    pub bounding_box: Option<BoundingBoxV1>,
    #[serde(default)]
    pub keypoints: Vec<KeypointV1>,
    #[serde(default)]
    pub vector: Option<Vec<f32>>,
    #[serde(default)]
    pub region_id: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct ValidityIntervalV1 {
    pub start_timestamp_ns: u64,
    #[serde(default)]
    pub end_timestamp_ns: Option<u64>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct ModelEventV1 {
    pub schema_version: String,
    pub session_id: String,
    pub event_id: String,
    #[serde(default)]
    pub source_frame_id: Option<u64>,
    pub capture_timestamp_ns: u64,
    pub inference_timestamp_ns: u64,
    pub model_id: String,
    pub model_version: String,
    #[serde(default)]
    pub track_id: Option<String>,
    pub class_id: String,
    #[serde(default)]
    pub confidence: Option<f32>,
    #[serde(default)]
    pub quality: Option<f32>,
    #[serde(default)]
    pub geometry: Option<ModelGeometryV1>,
    pub validity_interval: ValidityIntervalV1,
    #[serde(default)]
    pub metadata: BTreeMap<String, Value>,
}

impl ModelEventV1 {
    pub fn validate(&self) -> Result<(), String> {
        if self.schema_version != MODEL_EVENT_SCHEMA_VERSION {
            return Err(format!(
                "schema_version must be {MODEL_EVENT_SCHEMA_VERSION}"
            ));
        }
        require_text(&self.session_id, "session_id")?;
        require_text(&self.event_id, "event_id")?;
        require_text(&self.model_id, "model_id")?;
        require_text(&self.model_version, "model_version")?;
        require_text(&self.class_id, "class_id")?;
        if let Some(track_id) = &self.track_id {
            require_text(track_id, "track_id")?;
        }
        if self.inference_timestamp_ns < self.capture_timestamp_ns {
            return Err(
                "inference_timestamp_ns must be greater than or equal to capture_timestamp_ns"
                    .into(),
            );
        }
        validate_unit_interval(self.confidence, "confidence")?;
        validate_unit_interval(self.quality, "quality")?;
        self.validity_interval.validate()?;
        if let Some(geometry) = &self.geometry {
            geometry.validate()?;
        }
        Ok(())
    }

    pub fn to_json(&self) -> Result<String, String> {
        self.validate()?;
        serde_json::to_string(self).map_err(|error| error.to_string())
    }

    pub fn from_json(value: &str) -> Result<Self, String> {
        let raw: Value = serde_json::from_str(value).map_err(|error| error.to_string())?;
        let object = raw
            .as_object()
            .ok_or_else(|| "ModelEventV1 must be a JSON object".to_string())?;
        let missing: Vec<&str> = MODEL_EVENT_CORE_FIELDS
            .iter()
            .copied()
            .filter(|field| !object.contains_key(*field))
            .collect();
        if !missing.is_empty() {
            return Err(format!(
                "missing ModelEventV1 core fields: {}",
                missing.join(", ")
            ));
        }
        let event: Self = serde_json::from_value(raw).map_err(|error| error.to_string())?;
        event.validate()?;
        Ok(event)
    }
}

impl ValidityIntervalV1 {
    pub fn validate(&self) -> Result<(), String> {
        if let Some(end_timestamp_ns) = self.end_timestamp_ns {
            if end_timestamp_ns < self.start_timestamp_ns {
                return Err(
                    "validity_interval.end_timestamp_ns must be greater than or equal to start_timestamp_ns"
                        .into(),
                );
            }
        }
        Ok(())
    }
}

impl ModelGeometryV1 {
    pub fn validate(&self) -> Result<(), String> {
        if let Some(coordinate_space) = &self.coordinate_space {
            require_text(coordinate_space, "geometry.coordinate_space")?;
        }
        if let Some(region_id) = &self.region_id {
            require_text(region_id, "geometry.region_id")?;
        }
        if let Some(bounding_box) = &self.bounding_box {
            validate_finite(bounding_box.x, "geometry.bounding_box.x")?;
            validate_finite(bounding_box.y, "geometry.bounding_box.y")?;
            validate_finite(bounding_box.width, "geometry.bounding_box.width")?;
            validate_finite(bounding_box.height, "geometry.bounding_box.height")?;
            if bounding_box.width < 0.0 || bounding_box.height < 0.0 {
                return Err("geometry bounding-box width/height must be non-negative".into());
            }
        }
        for (index, keypoint) in self.keypoints.iter().enumerate() {
            validate_finite(keypoint.x, &format!("geometry.keypoints[{index}].x"))?;
            validate_finite(keypoint.y, &format!("geometry.keypoints[{index}].y"))?;
            validate_unit_interval(
                keypoint.confidence,
                &format!("geometry.keypoints[{index}].confidence"),
            )?;
            if let Some(label) = &keypoint.label {
                require_text(label, &format!("geometry.keypoints[{index}].label"))?;
            }
        }
        if let Some(vector) = &self.vector {
            for (index, value) in vector.iter().enumerate() {
                validate_finite(*value, &format!("geometry.vector[{index}]"))?;
            }
        }
        Ok(())
    }
}

fn require_text(value: &str, field: &str) -> Result<(), String> {
    if value.trim().is_empty() {
        return Err(format!("{field} must be a non-empty string"));
    }
    Ok(())
}

fn validate_unit_interval(value: Option<f32>, field: &str) -> Result<(), String> {
    if let Some(value) = value {
        validate_finite(value, field)?;
        if !(0.0..=1.0).contains(&value) {
            return Err(format!("{field} must be between 0 and 1"));
        }
    }
    Ok(())
}

fn validate_finite(value: f32, field: &str) -> Result<(), String> {
    if !value.is_finite() {
        return Err(format!("{field} must be finite"));
    }
    Ok(())
}

use chrono::Utc;
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::fs;
use std::path::{Path, PathBuf};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct NativeEvidenceRecord {
    pub id: String,
    pub student_id: String,
    pub exam_id: String,
    pub attempt_id: String,
    pub event_type: String,
    pub file_type: String,
    pub file_path: String,
    pub sha256: String,
    pub size_bytes: u64,
    pub created_at: String,
    pub review_reason: String,
    pub metadata_json: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct NativeEvidenceBundle {
    pub student_id: String,
    pub exam_id: String,
    pub attempt_id: String,
    pub directory_path: String,
    pub records: Vec<NativeEvidenceRecord>,
    pub updated_at: String,
}

pub fn sha256_hex(bytes: Vec<u8>) -> String {
    let mut hasher = Sha256::new();
    hasher.update(bytes);
    hex::encode(hasher.finalize())
}

pub fn save_evidence_bytes(
    base_dir: String,
    student_id: String,
    exam_id: String,
    attempt_id: String,
    event_type: String,
    file_type: String,
    review_reason: String,
    bytes: Vec<u8>,
    metadata_json: String,
) -> Result<String, String> {
    let now = Utc::now();
    let directory = bundle_directory(&base_dir, &student_id, &exam_id, &attempt_id);
    fs::create_dir_all(&directory).map_err(|error| error.to_string())?;

    let safe_event = safe_name(&event_type);
    let safe_type = match safe_name(&file_type).is_empty() {
        true => String::from("bin"),
        false => safe_name(&file_type),
    };
    let id = format!("{}_{}", now.timestamp_micros(), safe_event);
    let file_path = directory.join(format!("{}.{}", id, safe_type));
    fs::write(&file_path, &bytes).map_err(|error| error.to_string())?;

    let record = NativeEvidenceRecord {
        id,
        student_id: student_id.clone(),
        exam_id: exam_id.clone(),
        attempt_id: attempt_id.clone(),
        event_type,
        file_type: safe_type,
        file_path: file_path.to_string_lossy().to_string(),
        sha256: sha256_hex(bytes.clone()),
        size_bytes: bytes.len() as u64,
        created_at: now.to_rfc3339(),
        review_reason,
        metadata_json,
    };

    append_manifest(&directory, record).map_err(|error| error.to_string())
}

pub fn read_evidence_bundle(
    base_dir: String,
    student_id: String,
    exam_id: String,
    attempt_id: String,
) -> Result<String, String> {
    let directory = bundle_directory(&base_dir, &student_id, &exam_id, &attempt_id);
    let manifest_path = directory.join("manifest.json");
    if !manifest_path.exists() {
        let bundle = NativeEvidenceBundle {
            student_id,
            exam_id,
            attempt_id,
            directory_path: directory.to_string_lossy().to_string(),
            records: Vec::new(),
            updated_at: Utc::now().to_rfc3339(),
        };
        return serde_json::to_string_pretty(&bundle).map_err(|error| error.to_string());
    }

    fs::read_to_string(manifest_path).map_err(|error| error.to_string())
}

fn append_manifest(directory: &Path, record: NativeEvidenceRecord) -> Result<String, Box<dyn std::error::Error>> {
    let manifest_path = directory.join("manifest.json");
    let mut bundle = if manifest_path.exists() {
        let raw = fs::read_to_string(&manifest_path)?;
        serde_json::from_str::<NativeEvidenceBundle>(&raw).unwrap_or_else(|_| empty_bundle(directory, &record))
    } else {
        empty_bundle(directory, &record)
    };

    bundle.records.push(record);
    bundle.updated_at = Utc::now().to_rfc3339();
    let encoded = serde_json::to_string_pretty(&bundle)?;
    fs::write(&manifest_path, &encoded)?;
    Ok(encoded)
}

fn empty_bundle(directory: &Path, record: &NativeEvidenceRecord) -> NativeEvidenceBundle {
    NativeEvidenceBundle {
        student_id: record.student_id.clone(),
        exam_id: record.exam_id.clone(),
        attempt_id: record.attempt_id.clone(),
        directory_path: directory.to_string_lossy().to_string(),
        records: Vec::new(),
        updated_at: Utc::now().to_rfc3339(),
    }
}

fn bundle_directory(base_dir: &str, student_id: &str, exam_id: &str, attempt_id: &str) -> PathBuf {
    Path::new(base_dir)
        .join(safe_name(student_id))
        .join(safe_name(exam_id))
        .join(safe_name(attempt_id))
}

fn safe_name(value: &str) -> String {
    let mut output = String::new();
    let mut previous_underscore = false;
    for character in value.trim().chars() {
        let allowed = character.is_ascii_alphanumeric() || matches!(character, '.' | '_' | '-');
        let next = if allowed { character } else { '_' };
        if next == '_' && previous_underscore {
            continue;
        }
        previous_underscore = next == '_';
        output.push(next);
    }
    output.trim_matches('_').to_string()
}

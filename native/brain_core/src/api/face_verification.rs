use flutter_rust_bridge::frb;
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};

const TEMPLATE_VERSION: i32 = 1;

#[frb]
#[derive(Clone, Debug, Serialize, Deserialize, PartialEq)]
pub struct FaceTemplateStatus {
    pub valid: bool,
    pub student_id: String,
    pub enrollment_id: String,
    pub model_id: String,
    pub model_sha256: String,
    pub embedding_dimension: i32,
    pub sample_count: i32,
    pub quality_score: f32,
    pub template_sha256: String,
    pub reason: String,
}

#[frb]
#[derive(Clone, Debug, Serialize, Deserialize, PartialEq)]
pub struct FaceVerificationResult {
    pub state: String,
    pub similarity: f32,
    pub threshold: f32,
    pub signal_quality: f32,
    pub reliable: bool,
    pub reason: String,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
struct PortableFaceTemplate {
    template_version: i32,
    student_id: String,
    enrollment_id: String,
    model_id: String,
    model_sha256: String,
    preprocessing_version: String,
    embedding_dimension: usize,
    reference_embedding: Vec<f32>,
    sample_count: usize,
    quality_score: f32,
    created_at_ms: i64,
    expires_at_ms: i64,
    template_sha256: String,
}

#[frb(sync)]
pub fn build_portable_face_template(
    student_id: String,
    enrollment_id: String,
    model_id: String,
    model_sha256: String,
    preprocessing_version: String,
    embeddings: Vec<Vec<f32>>,
    quality_score: f32,
    created_at_ms: i64,
    expires_at_ms: i64,
) -> Result<String, String> {
    validate_identity_fields(&student_id, &enrollment_id, &model_id, &model_sha256)?;
    if embeddings.len() < 3 || embeddings.len() > 32 {
        return Err("face template requires between 3 and 32 reliable samples".into());
    }
    let dimension = embeddings[0].len();
    if !(64..=2048).contains(&dimension) {
        return Err("embedding dimension must be between 64 and 2048".into());
    }
    if expires_at_ms <= created_at_ms {
        return Err("template expiration must be after creation".into());
    }
    let mut centroid = vec![0.0_f32; dimension];
    for embedding in &embeddings {
        if embedding.len() != dimension {
            return Err("all face embeddings must use the same dimension".into());
        }
        let normalized = normalize(embedding)?;
        for (target, value) in centroid.iter_mut().zip(normalized) {
            *target += value;
        }
    }
    let reference_embedding = normalize(&centroid)?;
    let mut template = PortableFaceTemplate {
        template_version: TEMPLATE_VERSION,
        student_id,
        enrollment_id,
        model_id,
        model_sha256: model_sha256.to_ascii_lowercase(),
        preprocessing_version,
        embedding_dimension: dimension,
        reference_embedding,
        sample_count: embeddings.len(),
        quality_score: quality_score.clamp(0.0, 1.0),
        created_at_ms,
        expires_at_ms,
        template_sha256: String::new(),
    };
    template.template_sha256 = template_digest(&template)?;
    serde_json::to_string(&template).map_err(|error| error.to_string())
}

#[frb(sync)]
pub fn validate_portable_face_template(
    template_json: String,
    expected_student_id: String,
    expected_model_id: String,
    expected_model_sha256: String,
    now_ms: i64,
) -> FaceTemplateStatus {
    let parsed = serde_json::from_str::<PortableFaceTemplate>(&template_json);
    let Ok(template) = parsed else {
        return invalid_status("face template JSON is invalid");
    };
    let reason = validate_template(
        &template,
        &expected_student_id,
        &expected_model_id,
        &expected_model_sha256,
        now_ms,
    )
    .err();
    FaceTemplateStatus {
        valid: reason.is_none(),
        student_id: template.student_id,
        enrollment_id: template.enrollment_id,
        model_id: template.model_id,
        model_sha256: template.model_sha256,
        embedding_dimension: template.embedding_dimension as i32,
        sample_count: template.sample_count as i32,
        quality_score: template.quality_score,
        template_sha256: template.template_sha256,
        reason: reason.unwrap_or_else(|| "portable face template is valid".into()),
    }
}

#[frb(sync)]
pub fn verify_face_embedding_1_to_1(
    template_json: String,
    probe_embedding: Vec<f32>,
    signal_quality: f32,
    match_threshold: f32,
    now_ms: i64,
) -> FaceVerificationResult {
    let Ok(template) = serde_json::from_str::<PortableFaceTemplate>(&template_json) else {
        return uncertain(
            "face template JSON is invalid",
            signal_quality,
            match_threshold,
        );
    };
    if let Err(reason) = validate_template(
        &template,
        &template.student_id,
        &template.model_id,
        &template.model_sha256,
        now_ms,
    ) {
        return uncertain(&reason, signal_quality, match_threshold);
    }
    if signal_quality < 0.65 {
        return uncertain(
            "face sample quality is too low",
            signal_quality,
            match_threshold,
        );
    }
    if probe_embedding.len() != template.embedding_dimension {
        return uncertain(
            "probe embedding is incompatible with the enrolled model",
            signal_quality,
            match_threshold,
        );
    }
    let Ok(probe) = normalize(&probe_embedding) else {
        return uncertain(
            "probe embedding is invalid",
            signal_quality,
            match_threshold,
        );
    };
    let similarity = probe
        .iter()
        .zip(&template.reference_embedding)
        .map(|(left, right)| left * right)
        .sum::<f32>()
        .clamp(-1.0, 1.0);
    let threshold = match_threshold.clamp(0.0, 1.0);
    let verified = similarity >= threshold;
    FaceVerificationResult {
        state: if verified {
            "identity_verified"
        } else {
            "identity_mismatch_sample"
        }
        .into(),
        similarity,
        threshold,
        signal_quality: signal_quality.clamp(0.0, 1.0),
        reliable: true,
        reason: if verified {
            "probe matches the enrolled one-to-one template"
        } else {
            "reliable probe did not meet the calibrated threshold; more samples are required"
        }
        .into(),
    }
}

fn validate_template(
    template: &PortableFaceTemplate,
    student_id: &str,
    model_id: &str,
    model_sha256: &str,
    now_ms: i64,
) -> Result<(), String> {
    if template.template_version != TEMPLATE_VERSION {
        return Err("unsupported face template version".into());
    }
    if template.student_id != student_id {
        return Err("face template belongs to a different student".into());
    }
    if template.model_id != model_id || template.model_sha256 != model_sha256.to_ascii_lowercase() {
        return Err("face template model is incompatible with this device runtime".into());
    }
    if now_ms >= template.expires_at_ms {
        return Err("face template has expired".into());
    }
    if template.reference_embedding.len() != template.embedding_dimension {
        return Err("face template dimension is invalid".into());
    }
    let expected = template_digest(template)?;
    if expected != template.template_sha256 {
        return Err("face template integrity check failed".into());
    }
    normalize(&template.reference_embedding)?;
    Ok(())
}

fn template_digest(template: &PortableFaceTemplate) -> Result<String, String> {
    let mut unsigned = template.clone();
    unsigned.template_sha256.clear();
    let bytes = serde_json::to_vec(&unsigned).map_err(|error| error.to_string())?;
    Ok(hex_digest(&bytes))
}

fn normalize(values: &[f32]) -> Result<Vec<f32>, String> {
    if values.is_empty() || values.iter().any(|value| !value.is_finite()) {
        return Err("embedding contains invalid values".into());
    }
    let norm = values.iter().map(|value| value * value).sum::<f32>().sqrt();
    if norm < 1e-6 {
        return Err("embedding magnitude is too small".into());
    }
    Ok(values.iter().map(|value| value / norm).collect())
}

fn validate_identity_fields(
    student: &str,
    enrollment: &str,
    model: &str,
    digest: &str,
) -> Result<(), String> {
    if student.trim().is_empty() || enrollment.trim().is_empty() || model.trim().is_empty() {
        return Err("student, enrollment, and model identifiers are required".into());
    }
    if digest.len() != 64
        || !digest
            .chars()
            .all(|character| character.is_ascii_hexdigit())
    {
        return Err("model_sha256 must be a 64-character hexadecimal digest".into());
    }
    Ok(())
}

fn hex_digest(bytes: &[u8]) -> String {
    Sha256::digest(bytes)
        .iter()
        .map(|byte| format!("{byte:02x}"))
        .collect()
}

fn uncertain(reason: &str, quality: f32, threshold: f32) -> FaceVerificationResult {
    FaceVerificationResult {
        state: "identity_uncertain".into(),
        similarity: 0.0,
        threshold: threshold.clamp(0.0, 1.0),
        signal_quality: quality.clamp(0.0, 1.0),
        reliable: false,
        reason: reason.into(),
    }
}

fn invalid_status(reason: &str) -> FaceTemplateStatus {
    FaceTemplateStatus {
        valid: false,
        student_id: String::new(),
        enrollment_id: String::new(),
        model_id: String::new(),
        model_sha256: String::new(),
        embedding_dimension: 0,
        sample_count: 0,
        quality_score: 0.0,
        template_sha256: String::new(),
        reason: reason.into(),
    }
}

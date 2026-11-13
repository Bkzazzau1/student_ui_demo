//! Official Face ID: the school-approved, school-signed face template that
//! every exam identity check is compared against.
//!
//! Trust model:
//!
//! * A student submits face photos at registration. School staff review the
//!   photos in the school's own system and approve or reject them.
//! * On approval the school builds the template from the approved photos and
//!   signs it (Ed25519). The device never decides that a template is
//!   official: it only accepts a template whose signature verifies against a
//!   key it already trusts.
//! * At exam time the device downloads the signed template, and every 1:1
//!   comparison below re-verifies the signature and checks that the template
//!   belongs to the logged-in student, the installed model, and the installed
//!   preprocessing. A template that fails any check is never matched against.
//!
//! The signature covers the exact payload bytes carried in the envelope, so
//! any issuer (this crate, a Python service, a university system) can produce
//! templates without needing a byte-identical JSON serializer.

use ed25519_dalek::{Signature, Signer, SigningKey, VerifyingKey};
use flutter_rust_bridge::frb;
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};

pub const OFFICIAL_TEMPLATE_SCHEMA: &str = "kslas.official_face_template.v2";
pub const SIGNED_ENVELOPE_FORMAT: &str = "kslas.signed_official_face_template.v1";
const SIGNING_DOMAIN: &[u8] = b"kslas.official_face_template.v2\n";
const MIN_REFERENCES: usize = 3;
const MAX_REFERENCES: usize = 32;
const MAX_ISSUE_CLOCK_SKEW_MS: i64 = 24 * 60 * 60 * 1000;

#[frb]
#[derive(Clone, Debug, Serialize, Deserialize, PartialEq)]
pub struct OfficialFaceTemplateStatus {
    pub valid: bool,
    pub reason: String,
    pub template_id: String,
    pub institution_id: String,
    pub student_id: String,
    pub submission_id: String,
    pub key_id: String,
    pub key_environment: String,
    pub model_id: String,
    pub preprocessing_version: String,
    pub build_source: String,
    pub reference_count: i32,
    pub embedding_dimension: i32,
    pub approved_at_ms: i64,
    pub expires_at_ms: i64,
    pub envelope_sha256: String,
}

#[frb]
#[derive(Clone, Debug, Serialize, Deserialize, PartialEq)]
pub struct OfficialFaceMatchResult {
    /// `identity_verified`, `identity_mismatch_sample`, or
    /// `identity_uncertain`. Uncertain is never a mismatch: it means the
    /// template or the sample could not support a decision.
    pub state: String,
    /// Mean of the two best reference similarities (the decision score).
    pub similarity: f32,
    /// Similarity to the reference centroid, reported for evidence and
    /// calibration only.
    pub centroid_similarity: f32,
    pub threshold: f32,
    pub signal_quality: f32,
    pub reliable: bool,
    pub template_id: String,
    pub envelope_sha256: String,
    pub reason: String,
}

/// What the (sample) school signs after staff approve a submission.
#[frb]
#[derive(Clone, Debug, Serialize, Deserialize, PartialEq)]
pub struct OfficialTemplateIssueRequest {
    pub template_id: String,
    pub institution_id: String,
    pub student_id: String,
    pub submission_id: String,
    pub model_id: String,
    pub model_sha256: String,
    pub preprocessing_version: String,
    pub references: Vec<Vec<f32>>,
    pub reference_labels: Vec<String>,
    pub quality_score: f32,
    pub build_source: String,
    pub approved_by: String,
    pub approved_at_ms: i64,
    pub issued_at_ms: i64,
    pub expires_at_ms: i64,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
struct OfficialFaceTemplatePayload {
    schema: String,
    template_id: String,
    institution_id: String,
    student_id: String,
    submission_id: String,
    model_id: String,
    model_sha256: String,
    preprocessing_version: String,
    embedding_dimension: usize,
    centroid: Vec<f32>,
    references: Vec<Vec<f32>>,
    reference_labels: Vec<String>,
    quality_score: f32,
    build_source: String,
    approved_by: String,
    approved_at_ms: i64,
    issued_at_ms: i64,
    expires_at_ms: i64,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
struct SignedEnvelope {
    format: String,
    key_id: String,
    payload: String,
    signature_hex: String,
}

#[derive(Clone, Debug, Deserialize)]
struct TrustedKey {
    key_id: String,
    public_key_hex: String,
    #[serde(default)]
    environment: String,
}

struct Expectations<'a> {
    student_id: &'a str,
    model_id: &'a str,
    model_sha256: &'a str,
    preprocessing_version: &'a str,
    now_ms: i64,
}

struct VerifiedTemplate {
    payload: OfficialFaceTemplatePayload,
    key_id: String,
    key_environment: String,
    envelope_sha256: String,
}

#[frb(sync)]
pub fn verify_official_face_template(
    envelope_json: String,
    trusted_keys_json: String,
    expected_student_id: String,
    expected_model_id: String,
    expected_model_sha256: String,
    expected_preprocessing_version: String,
    now_ms: i64,
) -> OfficialFaceTemplateStatus {
    let expectations = Expectations {
        student_id: &expected_student_id,
        model_id: &expected_model_id,
        model_sha256: &expected_model_sha256,
        preprocessing_version: &expected_preprocessing_version,
        now_ms,
    };
    match verify_envelope(&envelope_json, &trusted_keys_json, &expectations) {
        Ok(verified) => status_from(&verified, true, "official face template is valid"),
        Err(reason) => invalid_status(&reason),
    }
}

#[frb(sync)]
#[allow(clippy::too_many_arguments)]
pub fn match_official_face_template_1_to_1(
    envelope_json: String,
    trusted_keys_json: String,
    expected_student_id: String,
    expected_model_id: String,
    expected_model_sha256: String,
    expected_preprocessing_version: String,
    probe_embedding: Vec<f32>,
    signal_quality: f32,
    min_signal_quality: f32,
    match_threshold: f32,
    now_ms: i64,
) -> OfficialFaceMatchResult {
    let threshold = match_threshold.clamp(0.0, 1.0);
    let quality = signal_quality.clamp(0.0, 1.0);
    let expectations = Expectations {
        student_id: &expected_student_id,
        model_id: &expected_model_id,
        model_sha256: &expected_model_sha256,
        preprocessing_version: &expected_preprocessing_version,
        now_ms,
    };
    let verified = match verify_envelope(&envelope_json, &trusted_keys_json, &expectations) {
        Ok(verified) => verified,
        Err(reason) => return uncertain(&reason, quality, threshold, "", ""),
    };
    let template_id = verified.payload.template_id.clone();
    let digest = verified.envelope_sha256.clone();
    if quality < min_signal_quality.clamp(0.0, 1.0) {
        return uncertain(
            "face sample quality is too low",
            quality,
            threshold,
            &template_id,
            &digest,
        );
    }
    if probe_embedding.len() != verified.payload.embedding_dimension {
        return uncertain(
            "probe embedding is incompatible with the official template",
            quality,
            threshold,
            &template_id,
            &digest,
        );
    }
    let Ok(probe) = normalize(&probe_embedding) else {
        return uncertain(
            "probe embedding is invalid",
            quality,
            threshold,
            &template_id,
            &digest,
        );
    };
    let mut scores = Vec::with_capacity(verified.payload.references.len());
    for reference in &verified.payload.references {
        // References were normalized and validated in `verify_envelope`.
        scores.push(dot(&probe, reference));
    }
    scores.sort_by(|a, b| b.total_cmp(a));
    let similarity = ((scores[0] + scores[1]) / 2.0).clamp(-1.0, 1.0);
    let centroid_similarity = dot(&probe, &verified.payload.centroid).clamp(-1.0, 1.0);
    let matched = similarity >= threshold;
    OfficialFaceMatchResult {
        state: if matched {
            "identity_verified"
        } else {
            "identity_mismatch_sample"
        }
        .into(),
        similarity,
        centroid_similarity,
        threshold,
        signal_quality: quality,
        reliable: true,
        template_id,
        envelope_sha256: digest,
        reason: if matched {
            "live sample matches the official face template"
        } else {
            "reliable live sample did not reach the match threshold"
        }
        .into(),
    }
}

/// Public key for a sample-school signing seed. The local sample school uses
/// this to publish the key the app trusts in testing builds. Production
/// builds trust only keys issued by the real school system.
#[frb(sync)]
pub fn sample_school_public_key_hex(signing_seed_hex: String) -> Result<String, String> {
    let signing = signing_key_from_hex(&signing_seed_hex)?;
    Ok(to_hex(signing.verifying_key().as_bytes()))
}

/// Builds and signs an official template on behalf of the LOCAL SAMPLE
/// SCHOOL ONLY. The real school system signs templates on its own servers
/// with a key that never reaches student devices.
#[frb(sync)]
pub fn issue_sample_school_official_template(
    request: OfficialTemplateIssueRequest,
    signing_seed_hex: String,
    key_id: String,
) -> Result<String, String> {
    let signing = signing_key_from_hex(&signing_seed_hex)?;
    if key_id.trim().is_empty() {
        return Err("key_id is required".into());
    }
    let payload = build_payload(request)?;
    let payload_json = serde_json::to_string(&payload).map_err(|error| error.to_string())?;
    let signature = signing.sign(&signed_message(&payload_json));
    let envelope = SignedEnvelope {
        format: SIGNED_ENVELOPE_FORMAT.into(),
        key_id,
        payload: payload_json,
        signature_hex: to_hex(&signature.to_bytes()),
    };
    serde_json::to_string(&envelope).map_err(|error| error.to_string())
}

fn build_payload(
    request: OfficialTemplateIssueRequest,
) -> Result<OfficialFaceTemplatePayload, String> {
    for (name, value) in [
        ("template_id", &request.template_id),
        ("institution_id", &request.institution_id),
        ("student_id", &request.student_id),
        ("submission_id", &request.submission_id),
        ("model_id", &request.model_id),
        ("preprocessing_version", &request.preprocessing_version),
        ("build_source", &request.build_source),
        ("approved_by", &request.approved_by),
    ] {
        if value.trim().is_empty() {
            return Err(format!("{name} is required"));
        }
    }
    validate_sha256_hex(&request.model_sha256)?;
    if request.expires_at_ms <= request.issued_at_ms {
        return Err("template expiration must be after issue time".into());
    }
    if request.approved_at_ms > request.issued_at_ms {
        return Err("template cannot be issued before it is approved".into());
    }
    let count = request.references.len();
    if !(MIN_REFERENCES..=MAX_REFERENCES).contains(&count) {
        return Err(format!(
            "official template requires between {MIN_REFERENCES} and {MAX_REFERENCES} reference embeddings"
        ));
    }
    if !request.reference_labels.is_empty() && request.reference_labels.len() != count {
        return Err("reference_labels must be empty or match the reference count".into());
    }
    let dimension = request.references[0].len();
    if !(64..=2048).contains(&dimension) {
        return Err("embedding dimension must be between 64 and 2048".into());
    }
    let mut references = Vec::with_capacity(count);
    let mut sum = vec![0.0_f32; dimension];
    for reference in &request.references {
        if reference.len() != dimension {
            return Err("all reference embeddings must use the same dimension".into());
        }
        let normalized = normalize(reference)?;
        for (total, value) in sum.iter_mut().zip(&normalized) {
            *total += value;
        }
        references.push(normalized);
    }
    Ok(OfficialFaceTemplatePayload {
        schema: OFFICIAL_TEMPLATE_SCHEMA.into(),
        template_id: request.template_id,
        institution_id: request.institution_id,
        student_id: request.student_id,
        submission_id: request.submission_id,
        model_id: request.model_id,
        model_sha256: request.model_sha256.to_ascii_lowercase(),
        preprocessing_version: request.preprocessing_version,
        embedding_dimension: dimension,
        centroid: normalize(&sum)?,
        references,
        reference_labels: request.reference_labels,
        quality_score: request.quality_score.clamp(0.0, 1.0),
        build_source: request.build_source,
        approved_by: request.approved_by,
        approved_at_ms: request.approved_at_ms,
        issued_at_ms: request.issued_at_ms,
        expires_at_ms: request.expires_at_ms,
    })
}

fn verify_envelope(
    envelope_json: &str,
    trusted_keys_json: &str,
    expected: &Expectations<'_>,
) -> Result<VerifiedTemplate, String> {
    let envelope: SignedEnvelope = serde_json::from_str(envelope_json)
        .map_err(|_| "official face template envelope is invalid".to_string())?;
    if envelope.format != SIGNED_ENVELOPE_FORMAT {
        return Err("unsupported official face template envelope".into());
    }
    let keys: Vec<TrustedKey> = serde_json::from_str(trusted_keys_json)
        .map_err(|_| "trusted key list is invalid".to_string())?;
    let key = keys
        .iter()
        .find(|key| key.key_id == envelope.key_id)
        .ok_or_else(|| "official face template is signed by an untrusted key".to_string())?;
    let public_key: [u8; 32] = from_hex(&key.public_key_hex)?
        .try_into()
        .map_err(|_| "trusted public key must be 32 bytes".to_string())?;
    let verifying = VerifyingKey::from_bytes(&public_key)
        .map_err(|_| "trusted public key is invalid".to_string())?;
    let signature_bytes: [u8; 64] = from_hex(&envelope.signature_hex)?
        .try_into()
        .map_err(|_| "template signature must be 64 bytes".to_string())?;
    let signature = Signature::from_bytes(&signature_bytes);
    verifying
        .verify_strict(&signed_message(&envelope.payload), &signature)
        .map_err(|_| "official face template signature is invalid".to_string())?;

    let payload: OfficialFaceTemplatePayload = serde_json::from_str(&envelope.payload)
        .map_err(|_| "official face template payload is invalid".to_string())?;
    if payload.schema != OFFICIAL_TEMPLATE_SCHEMA {
        return Err("unsupported official face template schema".into());
    }
    if payload.student_id != expected.student_id {
        return Err("official face template belongs to a different student".into());
    }
    if payload.model_id != expected.model_id
        || payload.model_sha256 != expected.model_sha256.to_ascii_lowercase()
    {
        return Err("official face template was built for a different face model".into());
    }
    if payload.preprocessing_version != expected.preprocessing_version {
        return Err("official face template was built with different face alignment".into());
    }
    if expected.now_ms >= payload.expires_at_ms {
        return Err("official face template has expired".into());
    }
    if payload.issued_at_ms > expected.now_ms + MAX_ISSUE_CLOCK_SKEW_MS {
        return Err("official face template is not valid yet; check the device clock".into());
    }
    let dimension = payload.embedding_dimension;
    let count = payload.references.len();
    if !(64..=2048).contains(&dimension)
        || payload.centroid.len() != dimension
        || !(MIN_REFERENCES..=MAX_REFERENCES).contains(&count)
        || payload
            .references
            .iter()
            .any(|reference| reference.len() != dimension)
    {
        return Err("official face template dimensions are invalid".into());
    }
    let mut payload = payload;
    payload.centroid = normalize(&payload.centroid)?;
    for reference in payload.references.iter_mut() {
        *reference = normalize(reference)?;
    }
    Ok(VerifiedTemplate {
        payload,
        key_id: key.key_id.clone(),
        key_environment: key.environment.clone(),
        envelope_sha256: hex_sha256(envelope_json.as_bytes()),
    })
}

fn signed_message(payload_json: &str) -> Vec<u8> {
    let mut message = Vec::with_capacity(SIGNING_DOMAIN.len() + payload_json.len());
    message.extend_from_slice(SIGNING_DOMAIN);
    message.extend_from_slice(payload_json.as_bytes());
    message
}

fn signing_key_from_hex(seed_hex: &str) -> Result<SigningKey, String> {
    let seed: [u8; 32] = from_hex(seed_hex)?
        .try_into()
        .map_err(|_| "signing seed must be 32 bytes".to_string())?;
    Ok(SigningKey::from_bytes(&seed))
}

fn status_from(
    verified: &VerifiedTemplate,
    valid: bool,
    reason: &str,
) -> OfficialFaceTemplateStatus {
    let payload = &verified.payload;
    OfficialFaceTemplateStatus {
        valid,
        reason: reason.into(),
        template_id: payload.template_id.clone(),
        institution_id: payload.institution_id.clone(),
        student_id: payload.student_id.clone(),
        submission_id: payload.submission_id.clone(),
        key_id: verified.key_id.clone(),
        key_environment: verified.key_environment.clone(),
        model_id: payload.model_id.clone(),
        preprocessing_version: payload.preprocessing_version.clone(),
        build_source: payload.build_source.clone(),
        reference_count: payload.references.len() as i32,
        embedding_dimension: payload.embedding_dimension as i32,
        approved_at_ms: payload.approved_at_ms,
        expires_at_ms: payload.expires_at_ms,
        envelope_sha256: verified.envelope_sha256.clone(),
    }
}

fn invalid_status(reason: &str) -> OfficialFaceTemplateStatus {
    OfficialFaceTemplateStatus {
        valid: false,
        reason: reason.into(),
        template_id: String::new(),
        institution_id: String::new(),
        student_id: String::new(),
        submission_id: String::new(),
        key_id: String::new(),
        key_environment: String::new(),
        model_id: String::new(),
        preprocessing_version: String::new(),
        build_source: String::new(),
        reference_count: 0,
        embedding_dimension: 0,
        approved_at_ms: 0,
        expires_at_ms: 0,
        envelope_sha256: String::new(),
    }
}

fn uncertain(
    reason: &str,
    quality: f32,
    threshold: f32,
    template_id: &str,
    envelope_sha256: &str,
) -> OfficialFaceMatchResult {
    OfficialFaceMatchResult {
        state: "identity_uncertain".into(),
        similarity: 0.0,
        centroid_similarity: 0.0,
        threshold,
        signal_quality: quality,
        reliable: false,
        template_id: template_id.into(),
        envelope_sha256: envelope_sha256.into(),
        reason: reason.into(),
    }
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

fn dot(left: &[f32], right: &[f32]) -> f32 {
    left.iter().zip(right).map(|(a, b)| a * b).sum()
}

fn validate_sha256_hex(digest: &str) -> Result<(), String> {
    if digest.len() != 64
        || !digest
            .chars()
            .all(|character| character.is_ascii_hexdigit())
    {
        return Err("model_sha256 must be a 64-character hexadecimal digest".into());
    }
    Ok(())
}

fn hex_sha256(bytes: &[u8]) -> String {
    to_hex(&Sha256::digest(bytes))
}

fn to_hex(bytes: &[u8]) -> String {
    bytes.iter().map(|byte| format!("{byte:02x}")).collect()
}

fn from_hex(text: &str) -> Result<Vec<u8>, String> {
    let text = text.trim();
    if !text.len().is_multiple_of(2) || !text.chars().all(|character| character.is_ascii_hexdigit())
    {
        return Err("value is not valid hexadecimal".into());
    }
    (0..text.len())
        .step_by(2)
        .map(|index| {
            u8::from_str_radix(&text[index..index + 2], 16)
                .map_err(|_| "value is not valid hexadecimal".to_string())
        })
        .collect()
}

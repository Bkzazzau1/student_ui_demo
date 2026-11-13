use brain_core::api::official_face_id::{
    OfficialTemplateIssueRequest, issue_sample_school_official_template,
    match_official_face_template_1_to_1, sample_school_public_key_hex,
    verify_official_face_template,
};

const SEED: &str = "0101010101010101010101010101010101010101010101010101010101010101";
const OTHER_SEED: &str = "0202020202020202020202020202020202020202020202020202020202020202";
const MODEL: &str = "kslas-sface-2021dec-v1";
const PREPROCESSING: &str = "sface-align-v2";
const DAY_MS: i64 = 24 * 60 * 60 * 1000;

fn model_sha() -> String {
    "a".repeat(64)
}

fn vector(index: usize) -> Vec<f32> {
    let mut values = vec![0.0; 128];
    values[index] = 1.0;
    values
}

fn request(references: Vec<Vec<f32>>) -> OfficialTemplateIssueRequest {
    let labels = (0..references.len())
        .map(|index| format!("pose-{index}"))
        .collect();
    OfficialTemplateIssueRequest {
        template_id: "template-1".into(),
        institution_id: "sample-school".into(),
        student_id: "STD/2026/001".into(),
        submission_id: "submission-1".into(),
        model_id: MODEL.into(),
        model_sha256: model_sha(),
        preprocessing_version: PREPROCESSING.into(),
        references,
        reference_labels: labels,
        quality_score: 0.9,
        build_source: "rebuilt_from_approved_photos".into(),
        approved_by: "registrar-1".into(),
        approved_at_ms: 1_000,
        issued_at_ms: 2_000,
        expires_at_ms: 2_000 + 365 * DAY_MS,
    }
}

fn trusted_keys(seed: &str, key_id: &str) -> String {
    let public = sample_school_public_key_hex(seed.into()).unwrap();
    format!(r#"[{{"key_id":"{key_id}","public_key_hex":"{public}","environment":"sample"}}]"#)
}

fn issue() -> String {
    issue_sample_school_official_template(
        request(vec![vector(0), vector(0), vector(1)]),
        SEED.into(),
        "sample-key-1".into(),
    )
    .unwrap()
}

fn verify(
    envelope: &str,
    keys: &str,
    student: &str,
    preprocessing: &str,
    now: i64,
) -> (bool, String) {
    let status = verify_official_face_template(
        envelope.into(),
        keys.into(),
        student.into(),
        MODEL.into(),
        model_sha(),
        preprocessing.into(),
        now,
    );
    (status.valid, status.reason)
}

#[test]
fn signed_template_verifies_for_its_student_model_and_alignment() {
    let envelope = issue();
    let status = verify_official_face_template(
        envelope,
        trusted_keys(SEED, "sample-key-1"),
        "STD/2026/001".into(),
        MODEL.into(),
        model_sha(),
        PREPROCESSING.into(),
        5_000,
    );
    assert!(status.valid, "{}", status.reason);
    assert_eq!(status.template_id, "template-1");
    assert_eq!(status.reference_count, 3);
    assert_eq!(status.key_environment, "sample");
    assert_eq!(status.build_source, "rebuilt_from_approved_photos");
    assert_eq!(status.envelope_sha256.len(), 64);
}

#[test]
fn template_is_rejected_for_another_student_model_or_alignment() {
    let envelope = issue();
    let keys = trusted_keys(SEED, "sample-key-1");
    let (valid, reason) = verify(&envelope, &keys, "STD/2026/002", PREPROCESSING, 5_000);
    assert!(!valid);
    assert!(reason.contains("different student"), "{reason}");

    let (valid, reason) = verify(&envelope, &keys, "STD/2026/001", "sface-align-v1", 5_000);
    assert!(!valid);
    assert!(reason.contains("alignment"), "{reason}");

    let status = verify_official_face_template(
        envelope,
        keys,
        "STD/2026/001".into(),
        "another-model".into(),
        model_sha(),
        PREPROCESSING.into(),
        5_000,
    );
    assert!(!status.valid);
    assert!(status.reason.contains("face model"), "{}", status.reason);
}

#[test]
fn edited_payload_breaks_the_signature() {
    let envelope = issue();
    // Swap the student inside the signed payload without re-signing.
    let tampered = envelope.replace("STD/2026/001", "STD/2026/009");
    let (valid, reason) = verify(
        &tampered,
        &trusted_keys(SEED, "sample-key-1"),
        "STD/2026/009",
        PREPROCESSING,
        5_000,
    );
    assert!(!valid);
    assert!(reason.contains("signature"), "{reason}");
}

#[test]
fn untrusted_or_wrong_keys_are_rejected() {
    let envelope = issue();
    let (valid, reason) = verify(
        &envelope,
        &trusted_keys(SEED, "another-key-id"),
        "STD/2026/001",
        PREPROCESSING,
        5_000,
    );
    assert!(!valid);
    assert!(reason.contains("untrusted"), "{reason}");

    let (valid, reason) = verify(
        &envelope,
        &trusted_keys(OTHER_SEED, "sample-key-1"),
        "STD/2026/001",
        PREPROCESSING,
        5_000,
    );
    assert!(!valid);
    assert!(reason.contains("signature"), "{reason}");

    let (valid, _) = verify(&envelope, "not json", "STD/2026/001", PREPROCESSING, 5_000);
    assert!(!valid);
}

#[test]
fn expired_or_future_templates_are_rejected() {
    let envelope = issue();
    let keys = trusted_keys(SEED, "sample-key-1");
    let (valid, reason) = verify(
        &envelope,
        &keys,
        "STD/2026/001",
        PREPROCESSING,
        2_000 + 365 * DAY_MS,
    );
    assert!(!valid);
    assert!(reason.contains("expired"), "{reason}");

    let (valid, reason) = verify(
        &envelope,
        &keys,
        "STD/2026/001",
        PREPROCESSING,
        2_000 - 2 * DAY_MS,
    );
    assert!(!valid);
    assert!(reason.contains("clock"), "{reason}");
}

#[test]
fn issuing_requires_enough_consistent_references() {
    let too_few = issue_sample_school_official_template(
        request(vec![vector(0), vector(0)]),
        SEED.into(),
        "sample-key-1".into(),
    );
    assert!(too_few.is_err());

    let mixed = issue_sample_school_official_template(
        request(vec![vector(0), vector(0), vec![1.0; 64]]),
        SEED.into(),
        "sample-key-1".into(),
    );
    assert!(mixed.is_err());

    let mut not_approved = request(vec![vector(0), vector(0), vector(1)]);
    not_approved.approved_at_ms = 9_000;
    assert!(issue_sample_school_official_template(not_approved, SEED.into(), "k".into()).is_err());

    assert!(sample_school_public_key_hex("abc".into()).is_err());
}

fn probe(envelope: &str, keys: &str, embedding: Vec<f32>, quality: f32) -> (String, f32, f32) {
    let result = match_official_face_template_1_to_1(
        envelope.into(),
        keys.into(),
        "STD/2026/001".into(),
        MODEL.into(),
        model_sha(),
        PREPROCESSING.into(),
        embedding,
        quality,
        0.65,
        0.55,
        5_000,
    );
    (result.state, result.similarity, result.centroid_similarity)
}

#[test]
fn match_uses_mean_of_two_best_references() {
    let envelope = issue();
    let keys = trusted_keys(SEED, "sample-key-1");

    // Two references equal vector(0): top-2 mean is 1.0.
    let (state, similarity, centroid) = probe(&envelope, &keys, vector(0), 0.9);
    assert_eq!(state, "identity_verified");
    assert!((similarity - 1.0).abs() < 1e-5);
    assert!(centroid < similarity);

    // Only one reference equals vector(1): top-2 mean is 0.5 (below 0.55).
    let (state, similarity, _) = probe(&envelope, &keys, vector(1), 0.9);
    assert_eq!(state, "identity_mismatch_sample");
    assert!((similarity - 0.5).abs() < 1e-5);

    let (state, _, _) = probe(&envelope, &keys, vector(7), 0.9);
    assert_eq!(state, "identity_mismatch_sample");
}

#[test]
fn match_is_uncertain_when_template_or_sample_cannot_support_a_decision() {
    let envelope = issue();
    let keys = trusted_keys(SEED, "sample-key-1");
    let (state, _, _) = probe(&envelope, &keys, vector(0), 0.4);
    assert_eq!(state, "identity_uncertain");

    let (state, _, _) = probe(&envelope, &keys, vec![1.0; 64], 0.9);
    assert_eq!(state, "identity_uncertain");

    let (state, _, _) = probe(&envelope, &keys, vec![0.0; 128], 0.9);
    assert_eq!(state, "identity_uncertain");

    let tampered = envelope.replace("pose-0", "pose-x");
    let (state, _, _) = probe(&tampered, &keys, vector(0), 0.9);
    assert_eq!(state, "identity_uncertain");
}

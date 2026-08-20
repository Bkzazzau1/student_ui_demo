use brain_core::api::face_verification::{
    build_portable_face_template, validate_portable_face_template, verify_face_embedding_1_to_1,
};

fn vector(index: usize) -> Vec<f32> {
    let mut values = vec![0.0; 64];
    values[index] = 1.0;
    values
}

#[test]
fn builds_valid_versioned_template_and_matches_same_identity() {
    let digest = "a".repeat(64);
    let template = build_portable_face_template(
        "student-1".into(),
        "enrollment-1".into(),
        "model-v1".into(),
        digest.clone(),
        "rgb-aligned-v1".into(),
        vec![vector(0), vector(0), vector(0)],
        0.9,
        100,
        1000,
    )
    .unwrap();
    let status = validate_portable_face_template(
        template.clone(),
        "student-1".into(),
        "model-v1".into(),
        digest,
        200,
    );
    assert!(status.valid);
    let result = verify_face_embedding_1_to_1(template, vector(0), 0.9, 0.7, 200);
    assert_eq!(result.state, "identity_verified");
    assert!(result.reliable);
}

#[test]
fn mismatch_is_a_sample_not_an_accusation() {
    let template = build_portable_face_template(
        "student-1".into(),
        "enrollment-1".into(),
        "model-v1".into(),
        "b".repeat(64),
        "rgb-aligned-v1".into(),
        vec![vector(0), vector(0), vector(0)],
        0.9,
        100,
        1000,
    )
    .unwrap();
    let result = verify_face_embedding_1_to_1(template, vector(1), 0.9, 0.7, 200);
    assert_eq!(result.state, "identity_mismatch_sample");
    assert!(result.reliable);
}

#[test]
fn rejects_cross_student_and_expired_templates() {
    let template = build_portable_face_template(
        "student-1".into(),
        "enrollment-1".into(),
        "model-v1".into(),
        "c".repeat(64),
        "rgb-aligned-v1".into(),
        vec![vector(0), vector(0), vector(0)],
        0.9,
        100,
        1000,
    )
    .unwrap();
    assert!(
        !validate_portable_face_template(
            template.clone(),
            "student-2".into(),
            "model-v1".into(),
            "c".repeat(64),
            200,
        )
        .valid
    );
    assert!(
        !validate_portable_face_template(
            template,
            "student-1".into(),
            "model-v1".into(),
            "c".repeat(64),
            1000,
        )
        .valid
    );
}

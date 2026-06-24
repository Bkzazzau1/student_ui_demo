use std::path::Path;

use brain_core::api::{
    evidence_sha256_hex, read_evidence_bundle, save_evidence_bytes, EvidenceVaultBundle,
};

#[test]
fn hashes_evidence_bytes() {
    let digest = evidence_sha256_hex(b"kslas".to_vec());
    assert_eq!(digest.len(), 64);
    assert!(digest.chars().all(|character| character.is_ascii_hexdigit()));
}

#[test]
fn saves_evidence_and_reads_manifest() {
    let base_dir = std::env::temp_dir()
        .join(format!("kslas_evidence_vault_test_{}", std::process::id()))
        .to_string_lossy()
        .to_string();

    let manifest_json = save_evidence_bytes(
        base_dir.clone(),
        "KASU/STU/2026/001".to_string(),
        "CSC 401".to_string(),
        "attempt 1".to_string(),
        "voice noticed".to_string(),
        "json".to_string(),
        "Record saved for review".to_string(),
        br#"{"event":"voice noticed"}"#.to_vec(),
        "{}".to_string(),
    )
    .expect("evidence should save");

    let bundle: EvidenceVaultBundle = serde_json::from_str(&manifest_json)
        .expect("manifest should decode");
    assert_eq!(bundle.records.len(), 1);
    assert_eq!(bundle.records[0].student_id, "KASU/STU/2026/001");
    assert_eq!(bundle.records[0].event_type, "voice noticed");
    assert!(Path::new(&bundle.records[0].file_path).exists());

    let loaded_json = read_evidence_bundle(
        base_dir,
        "KASU/STU/2026/001".to_string(),
        "CSC 401".to_string(),
        "attempt 1".to_string(),
    )
    .expect("bundle should load");
    let loaded: EvidenceVaultBundle = serde_json::from_str(&loaded_json)
        .expect("loaded manifest should decode");
    assert_eq!(loaded.records.len(), 1);
}

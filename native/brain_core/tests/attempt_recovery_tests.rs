use brain_core::api::{attempt_checksum, verify_attempt_snapshot};

#[test]
fn checksum_is_stable_for_same_payload() {
    let payload = r#"{"attempt_id":"a1","answers":{"q1":"A"}}"#.to_string();
    let first = attempt_checksum(payload.clone());
    let second = attempt_checksum(payload);

    assert_eq!(first, second);
    assert_eq!(first.len(), 64);
}

#[test]
fn verifies_valid_snapshot_checksum() {
    let payload = r#"{"attempt_id":"a1","answers":{"q1":"A"}}"#.to_string();
    let checksum = attempt_checksum(payload.clone());
    let result = verify_attempt_snapshot(payload.clone(), checksum.clone(), "primary".to_string());

    assert_eq!(result.payload_json, payload);
    assert_eq!(result.checksum, checksum);
    assert_eq!(result.recovered_from, "primary");
    assert!(result.checksum_valid);
}

#[test]
fn rejects_invalid_snapshot_checksum() {
    let payload = r#"{"attempt_id":"a1","answers":{"q1":"A"}}"#.to_string();
    let result = verify_attempt_snapshot(
        payload,
        "bad_checksum".to_string(),
        "backup".to_string(),
    );

    assert_eq!(result.recovered_from, "backup");
    assert!(!result.checksum_valid);
}

use flutter_rust_bridge::frb;
use sha2::{Digest, Sha256};

#[frb]
#[derive(Clone, Debug)]
pub struct NativeAttemptRecoveryCheck {
    pub checksum: String,
    pub checksum_valid: bool,
    pub payload_json: String,
    pub recovered_from: String,
}

#[frb(sync)]
pub fn attempt_checksum(payload_json: String) -> String {
    sha256_hex(payload_json.as_bytes())
}

#[frb(sync)]
pub fn verify_attempt_snapshot(
    payload_json: String,
    checksum: String,
    recovered_from: String,
) -> NativeAttemptRecoveryCheck {
    let computed = attempt_checksum(payload_json.clone());
    NativeAttemptRecoveryCheck {
        checksum: computed.clone(),
        checksum_valid: constant_time_eq(&computed, checksum.trim()),
        payload_json,
        recovered_from,
    }
}

fn sha256_hex(bytes: &[u8]) -> String {
    let digest = Sha256::digest(bytes);
    digest.iter().map(|byte| format!("{:02x}", byte)).collect()
}

fn constant_time_eq(left: &str, right: &str) -> bool {
    let left_bytes = left.as_bytes();
    let right_bytes = right.as_bytes();
    if left_bytes.len() != right_bytes.len() {
        return false;
    }

    let mut diff = 0_u8;
    for (left_byte, right_byte) in left_bytes.iter().zip(right_bytes.iter()) {
        diff |= left_byte ^ right_byte;
    }
    diff == 0
}

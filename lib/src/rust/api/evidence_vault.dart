// Dart-facing contract for the Rust evidence vault.
//
// This file documents the API shape expected from flutter_rust_bridge codegen.
// After running flutter_rust_bridge_codegen, the generated bridge should expose
// equivalent functions backed by `rust/src/lib.rs`.

class NativeEvidenceVaultApiContract {
  const NativeEvidenceVaultApiContract();
}

/// Expected Rust-backed function:
///
/// saveEvidenceBytes(
///   baseDir,
///   studentId,
///   examId,
///   attemptId,
///   eventType,
///   fileType,
///   reviewReason,
///   bytes,
///   metadataJson,
/// ) -> String manifestJson
///
/// The returned string is the updated manifest JSON after saving the file.

/// Expected Rust-backed function:
///
/// readEvidenceBundle(
///   baseDir,
///   studentId,
///   examId,
///   attemptId,
/// ) -> String manifestJson
///
/// The returned string is the evidence bundle manifest JSON.

/// Expected Rust-backed function:
///
/// sha256Hex(bytes) -> String
///
/// The returned string is the SHA-256 digest in lowercase hexadecimal form.

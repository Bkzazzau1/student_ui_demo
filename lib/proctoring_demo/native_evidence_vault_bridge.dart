import 'dart:typed_data';

import '../rust/api/evidence_vault.dart' as native_evidence_vault;
import '../rust/frb_generated.dart';

abstract class NativeEvidenceVaultBridge {
  Future<String?> saveBytes({
    required String baseDir,
    required String studentId,
    required String examId,
    required String attemptId,
    required String eventType,
    required String fileType,
    required String reviewReason,
    required Uint8List bytes,
    required String metadataJson,
  });

  Future<String?> readBundle({
    required String baseDir,
    required String studentId,
    required String examId,
    required String attemptId,
  });
}

class DisabledNativeEvidenceVaultBridge implements NativeEvidenceVaultBridge {
  const DisabledNativeEvidenceVaultBridge();

  @override
  Future<String?> saveBytes({
    required String baseDir,
    required String studentId,
    required String examId,
    required String attemptId,
    required String eventType,
    required String fileType,
    required String reviewReason,
    required Uint8List bytes,
    required String metadataJson,
  }) async {
    return null;
  }

  @override
  Future<String?> readBundle({
    required String baseDir,
    required String studentId,
    required String examId,
    required String attemptId,
  }) async {
    return null;
  }
}

class GeneratedNativeEvidenceVaultBridge implements NativeEvidenceVaultBridge {
  const GeneratedNativeEvidenceVaultBridge();

  static Future<bool>? _nativeReady;

  @override
  Future<String?> saveBytes({
    required String baseDir,
    required String studentId,
    required String examId,
    required String attemptId,
    required String eventType,
    required String fileType,
    required String reviewReason,
    required Uint8List bytes,
    required String metadataJson,
  }) async {
    if (!await _ensureNativeReady()) return null;
    try {
      return native_evidence_vault.saveEvidenceBytes(
        baseDir: baseDir,
        studentId: studentId,
        examId: examId,
        attemptId: attemptId,
        eventType: eventType,
        fileType: fileType,
        reviewReason: reviewReason,
        bytes: bytes.toList(growable: false),
        metadataJson: metadataJson,
      );
    } catch (_) {
      return null;
    }
  }

  @override
  Future<String?> readBundle({
    required String baseDir,
    required String studentId,
    required String examId,
    required String attemptId,
  }) async {
    if (!await _ensureNativeReady()) return null;
    try {
      return native_evidence_vault.readEvidenceBundle(
        baseDir: baseDir,
        studentId: studentId,
        examId: examId,
        attemptId: attemptId,
      );
    } catch (_) {
      return null;
    }
  }

  static Future<bool> _ensureNativeReady() {
    return _nativeReady ??= () async {
      try {
        await BrainCoreApi.init();
        return true;
      } catch (_) {
        return false;
      }
    }();
  }
}

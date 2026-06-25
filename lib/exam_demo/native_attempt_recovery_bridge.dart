import '../rust/api/attempt_recovery.dart' as native_recovery;
import '../rust/frb_generated.dart';

class NativeAttemptRecoveryCheckSnapshot {
  const NativeAttemptRecoveryCheckSnapshot({
    required this.checksum,
    required this.checksumValid,
    required this.payloadJson,
    required this.recoveredFrom,
  });

  final String checksum;
  final bool checksumValid;
  final String payloadJson;
  final String recoveredFrom;
}

abstract class NativeAttemptRecoveryBridge {
  Future<String?> checksum(String payloadJson);

  NativeAttemptRecoveryCheckSnapshot? verifySnapshot({
    required String payloadJson,
    required String checksum,
    required String recoveredFrom,
  });
}

class DisabledNativeAttemptRecoveryBridge
    implements NativeAttemptRecoveryBridge {
  const DisabledNativeAttemptRecoveryBridge();

  @override
  Future<String?> checksum(String payloadJson) async => null;

  @override
  NativeAttemptRecoveryCheckSnapshot? verifySnapshot({
    required String payloadJson,
    required String checksum,
    required String recoveredFrom,
  }) {
    return null;
  }
}

class GeneratedNativeAttemptRecoveryBridge
    implements NativeAttemptRecoveryBridge {
  const GeneratedNativeAttemptRecoveryBridge();

  static Future<void>? _nativeInit;
  static bool _nativeReady = false;
  static bool _nativeFailed = false;

  @override
  Future<String?> checksum(String payloadJson) async {
    if (!await _ensureNativeReady()) return null;
    try {
      return native_recovery.attemptChecksum(payloadJson: payloadJson);
    } catch (_) {
      return null;
    }
  }

  @override
  NativeAttemptRecoveryCheckSnapshot? verifySnapshot({
    required String payloadJson,
    required String checksum,
    required String recoveredFrom,
  }) {
    _startNativeInit();
    if (!_nativeReady) return null;
    try {
      final result = native_recovery.verifyAttemptSnapshot(
        payloadJson: payloadJson,
        checksum: checksum,
        recoveredFrom: recoveredFrom,
      );
      return NativeAttemptRecoveryCheckSnapshot(
        checksum: result.checksum,
        checksumValid: result.checksumValid,
        payloadJson: result.payloadJson,
        recoveredFrom: result.recoveredFrom,
      );
    } catch (_) {
      return null;
    }
  }

  static Future<bool> _ensureNativeReady() async {
    if (_nativeReady) return true;
    if (_nativeFailed) return false;
    _startNativeInit();
    await _nativeInit;
    return _nativeReady;
  }

  static void _startNativeInit() {
    if (_nativeReady || _nativeFailed || _nativeInit != null) return;
    _nativeInit = BrainCoreApi.init()
        .then((_) {
          _nativeReady = true;
        })
        .catchError((_) {
          _nativeFailed = true;
        });
  }
}

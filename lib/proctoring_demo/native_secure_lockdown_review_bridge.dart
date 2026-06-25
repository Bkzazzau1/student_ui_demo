import '../rust/api/lockdown.dart' as native_lockdown;
import '../rust/frb_generated.dart';

class NativeLockdownFindingSnapshot {
  const NativeLockdownFindingSnapshot({
    required this.code,
    required this.message,
    required this.severity,
  });

  final String code;
  final String message;
  final String severity;

  Map<String, Object?> toJson() => <String, Object?>{
    'code': code,
    'message': message,
    'severity': severity,
  };
}

class NativeSecureLockdownReviewSnapshot {
  const NativeSecureLockdownReviewSnapshot({
    required this.ready,
    required this.platformSupported,
    required this.platformName,
    required this.displayCount,
    required this.prohibitedProcesses,
    required this.findings,
  });

  final bool ready;
  final bool platformSupported;
  final String platformName;
  final int? displayCount;
  final List<String> prohibitedProcesses;
  final List<NativeLockdownFindingSnapshot> findings;

  Map<String, Object?> toJson() => <String, Object?>{
    'ready': ready,
    'platform_supported': platformSupported,
    'platform_name': platformName,
    'display_count': displayCount,
    'prohibited_processes': prohibitedProcesses,
    'findings': findings.map((finding) => finding.toJson()).toList(),
  };
}

abstract class NativeSecureLockdownReviewBridge {
  Future<NativeSecureLockdownReviewSnapshot?> check();
}

class DisabledNativeSecureLockdownReviewBridge
    implements NativeSecureLockdownReviewBridge {
  const DisabledNativeSecureLockdownReviewBridge();

  @override
  Future<NativeSecureLockdownReviewSnapshot?> check() async => null;
}

class GeneratedNativeSecureLockdownReviewBridge
    implements NativeSecureLockdownReviewBridge {
  const GeneratedNativeSecureLockdownReviewBridge();

  static Future<bool>? _nativeReady;

  @override
  Future<NativeSecureLockdownReviewSnapshot?> check() async {
    if (!await _ensureNativeReady()) return null;
    try {
      final result = await native_lockdown.runSecureLockdownReview(
        platformName: 'auto',
      );
      return NativeSecureLockdownReviewSnapshot(
        ready: result.ready,
        platformSupported: result.platformSupported,
        platformName: result.platformName,
        displayCount: result.displayCount,
        prohibitedProcesses: result.prohibitedProcesses,
        findings: result.findings
            .map(
              (finding) => NativeLockdownFindingSnapshot(
                code: finding.code,
                message: finding.message,
                severity: finding.severity,
              ),
            )
            .toList(growable: false),
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

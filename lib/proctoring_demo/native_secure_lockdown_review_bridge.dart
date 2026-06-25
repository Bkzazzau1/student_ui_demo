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

/// Temporary non-breaking adapter while flutter_rust_bridge Dart bindings are
/// regenerated for `native/brain_core/src/api/lockdown.rs`.
///
/// After codegen, this should call:
///
/// `await runSecureLockdownReview(platformName: 'auto')`
///
/// and map the generated native result into [NativeSecureLockdownReviewSnapshot].
class GeneratedNativeSecureLockdownReviewBridge
    implements NativeSecureLockdownReviewBridge {
  const GeneratedNativeSecureLockdownReviewBridge();

  @override
  Future<NativeSecureLockdownReviewSnapshot?> check() async {
    return null;
  }
}

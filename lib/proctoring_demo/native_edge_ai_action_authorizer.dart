import '../rust/api/ai_action_policy.dart' as native;
import '../rust/frb_generated.dart';
import 'edge_ai_review_coordinator.dart';

class NativeEdgeAiActionAuthorizer implements EdgeAiActionAuthorizer {
  Future<void>? _initialization;

  Future<void> _ensureInitialized() {
    return _initialization ??= BrainCoreApi.init();
  }

  @override
  Future<EdgeAiActionAuthorization> authorize({
    required String action,
    required bool examActive,
  }) async {
    try {
      await _ensureInitialized();
      final result = native.authorizeAiAction(
        action: action,
        examActive: examActive,
      );
      return EdgeAiActionAuthorization(
        action: result.action,
        allowed: result.allowed,
        requiresUserConsent: result.requiresUserConsent,
        reason: result.reason,
      );
    } catch (error) {
      return EdgeAiActionAuthorization(
        action: action,
        allowed: false,
        requiresUserConsent: false,
        reason: 'Rust action authorization failed: $error',
      );
    }
  }
}

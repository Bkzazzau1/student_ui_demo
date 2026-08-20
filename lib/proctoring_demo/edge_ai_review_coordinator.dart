import 'dart:async';

import 'live_proctoring_event_service.dart';
import 'python_edge_ai_service.dart';

class EdgeAiActionAuthorization {
  const EdgeAiActionAuthorization({
    required this.action,
    required this.allowed,
    required this.requiresUserConsent,
    required this.reason,
  });

  final String action;
  final bool allowed;
  final bool requiresUserConsent;
  final String reason;
}

abstract class EdgeAiActionAuthorizer {
  Future<EdgeAiActionAuthorization> authorize({
    required String action,
    required bool examActive,
  });
}

typedef EdgeAiApprovedActionHandler =
    Future<void> Function(
      String action,
      LiveProctoringEvent sourceEvent,
      EdgeAiReviewDecision decision,
    );

class EdgeAiCoordinationResult {
  const EdgeAiCoordinationResult({
    required this.decision,
    required this.authorizations,
    required this.executedActions,
  });

  final EdgeAiReviewDecision decision;
  final List<EdgeAiActionAuthorization> authorizations;
  final List<String> executedActions;
}

/// Enforces the Python -> Rust -> application action path.
///
/// Python can propose actions, but this coordinator calls the Rust-backed
/// authorizer before an application callback can execute one. Consent-required
/// actions are returned to the UI and are never executed automatically.
class EdgeAiReviewCoordinator {
  EdgeAiReviewCoordinator({
    required EdgeAiReviewer reviewer,
    required EdgeAiActionAuthorizer authorizer,
    required EdgeAiApprovedActionHandler onApprovedAction,
  }) : _reviewer = reviewer,
       _authorizer = authorizer,
       _onApprovedAction = onApprovedAction;

  final EdgeAiReviewer _reviewer;
  final EdgeAiActionAuthorizer _authorizer;
  final EdgeAiApprovedActionHandler _onApprovedAction;

  Future<EdgeAiCoordinationResult> process(
    LiveProctoringEvent event, {
    required bool examActive,
  }) async {
    final decision = await _reviewer.review(event);
    final authorizations = <EdgeAiActionAuthorization>[];
    final executedActions = <String>[];

    for (final action in decision.proposedActions.toSet()) {
      final authorization = await _authorizer.authorize(
        action: action,
        examActive: examActive,
      );
      authorizations.add(authorization);
      if (!authorization.allowed || authorization.requiresUserConsent) continue;
      await _onApprovedAction(action, event, decision);
      executedActions.add(action);
    }

    return EdgeAiCoordinationResult(
      decision: decision,
      authorizations: List.unmodifiable(authorizations),
      executedActions: List.unmodifiable(executedActions),
    );
  }

  Future<bool> clearAttempt(String attemptId) =>
      _reviewer.clearAttempt(attemptId);

  Future<void> observeGaze({
    required String attemptId,
    required Map<String, Object?> observation,
  }) => _reviewer.observeGaze(attemptId, observation);

  Future<Map<String, Object?>> observeAudio({
    required String attemptId,
    required Map<String, Object?> observation,
  }) => _reviewer.observeAudio(attemptId, observation);

  Future<void> dispose() => _reviewer.dispose();
}

/// Safe startup fallback used until generated Rust bindings are available.
/// It ensures an unavailable native bridge can never become implicit approval.
class DenyAllEdgeAiActionAuthorizer implements EdgeAiActionAuthorizer {
  const DenyAllEdgeAiActionAuthorizer();

  @override
  Future<EdgeAiActionAuthorization> authorize({
    required String action,
    required bool examActive,
  }) async {
    return EdgeAiActionAuthorization(
      action: action,
      allowed: false,
      requiresUserConsent: false,
      reason: 'Rust action authorization is unavailable',
    );
  }
}

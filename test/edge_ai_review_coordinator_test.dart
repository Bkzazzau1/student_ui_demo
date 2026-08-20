import 'package:flutter_test/flutter_test.dart';
import 'package:students_ui_demo/proctoring_demo/edge_ai_review_coordinator.dart';
import 'package:students_ui_demo/proctoring_demo/live_proctoring_event_service.dart';
import 'package:students_ui_demo/proctoring_demo/python_edge_ai_service.dart';

void main() {
  LiveProctoringEvent event() => LiveProctoringEvent(
    studentId: 'student-1',
    examId: 'exam-1',
    attemptId: 'attempt-1',
    eventType: 'yolo_phone_detected',
    severity: 'high',
    message: 'Phone-shaped object needs review',
    createdAt: DateTime.utc(2026, 8, 19),
  );

  test('executes a Rust-approved action', () async {
    final executed = <String>[];
    final coordinator = EdgeAiReviewCoordinator(
      reviewer: _FakeReviewer(['capture_review_snapshot']),
      authorizer: _FakeAuthorizer(allowed: true),
      onApprovedAction: (action, sourceEvent, decision) async {
        executed.add(action);
      },
    );

    final result = await coordinator.process(event(), examActive: true);
    expect(result.executedActions, ['capture_review_snapshot']);
    expect(executed, ['capture_review_snapshot']);
  });

  test('never executes a denied action', () async {
    var executed = false;
    final coordinator = EdgeAiReviewCoordinator(
      reviewer: _FakeReviewer(['run_shell_command']),
      authorizer: _FakeAuthorizer(allowed: false),
      onApprovedAction: (action, sourceEvent, decision) async {
        executed = true;
      },
    );

    final result = await coordinator.process(event(), examActive: true);
    expect(result.executedActions, isEmpty);
    expect(executed, isFalse);
  });

  test('does not automatically execute consent-required action', () async {
    var executed = false;
    final coordinator = EdgeAiReviewCoordinator(
      reviewer: _FakeReviewer(['request_identity_recheck']),
      authorizer: _FakeAuthorizer(allowed: true, requiresConsent: true),
      onApprovedAction: (action, sourceEvent, decision) async {
        executed = true;
      },
    );

    final result = await coordinator.process(event(), examActive: true);
    expect(result.authorizations.single.requiresUserConsent, isTrue);
    expect(executed, isFalse);
  });

  test('deny-all fallback fails closed', () async {
    final authorization = await const DenyAllEdgeAiActionAuthorizer().authorize(
      action: 'capture_review_snapshot',
      examActive: true,
    );
    expect(authorization.allowed, isFalse);
  });
}

class _FakeReviewer implements EdgeAiReviewer {
  _FakeReviewer(this.actions);

  final List<String> actions;

  @override
  Future<void> observeGaze(
    String attemptId,
    Map<String, Object?> observation,
  ) async {}

  @override
  Future<EdgeAiReviewDecision> review(LiveProctoringEvent event) async =>
      EdgeAiReviewDecision(
        riskScore: 50,
        riskLevel: 'high',
        disposition: 'human_review',
        reasons: const ['test'],
        proposedActions: actions,
        requiresHumanReview: true,
      );

  @override
  Future<bool> clearAttempt(String attemptId) async => true;

  @override
  Future<void> dispose() async {}
}

class _FakeAuthorizer implements EdgeAiActionAuthorizer {
  _FakeAuthorizer({required this.allowed, this.requiresConsent = false});

  final bool allowed;
  final bool requiresConsent;

  @override
  Future<EdgeAiActionAuthorization> authorize({
    required String action,
    required bool examActive,
  }) async => EdgeAiActionAuthorization(
    action: action,
    allowed: allowed,
    requiresUserConsent: requiresConsent,
    reason: 'test',
  );
}

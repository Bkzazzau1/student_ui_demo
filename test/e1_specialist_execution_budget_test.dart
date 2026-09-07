import 'package:flutter_test/flutter_test.dart';
import 'package:students_ui_demo/proctoring_demo/e1_small_object_specialist.dart';
import 'package:students_ui_demo/proctoring_demo/e1_specialist_execution_budget.dart';

E1SmallObjectSpecialistRequest _request({
  required int captureTimestampNs,
  required String strategy,
  required E1SmallObjectTarget target,
  double x = 0.1,
  String sessionId = 'attempt-1',
}) {
  return E1SmallObjectSpecialistRequest(
    sessionId: sessionId,
    sourceFrameId: captureTimestampNs,
    captureTimestampNs: captureTimestampNs,
    imageWidth: 100,
    imageHeight: 100,
    targets: <E1SmallObjectTarget>{target},
    reason: 'execution_budget_test',
    roiHint: E1SpecialistRoiHint(
      strategy: strategy,
      anchorCanonicalObjectId: 'test_anchor',
      boundingBox: <String, double>{
        'x': x,
        'y': 0.1,
        'width': 0.2,
        'height': 0.2,
      },
    ),
  );
}

List<E1SmallObjectSpecialistRequest> _threeRoutes(int captureTimestampNs) {
  return <E1SmallObjectSpecialistRequest>[
    _request(
      captureTimestampNs: captureTimestampNs,
      strategy: 'person_head_earbud',
      target: E1SmallObjectTarget.earbud,
    ),
    _request(
      captureTimestampNs: captureTimestampNs,
      strategy: 'person_arm_watch',
      target: E1SmallObjectTarget.smartwatch,
    ),
    _request(
      captureTimestampNs: captureTimestampNs,
      strategy: 'desk_anchor_union',
      target: E1SmallObjectTarget.calculator,
    ),
  ];
}

void main() {
  test(
    'uses monotonic capture time for cooldown and rejects stale captures',
    () {
      final budget = E1SpecialistExecutionBudget(
        minCaptureIntervalNs: 900,
        maxRequestsPerFrame: 2,
      );

      final first = budget.reserve(
        sessionId: 'attempt-1',
        captureTimestampNs: 1000,
        requests: _threeRoutes(1000),
      );
      expect(first, hasLength(2));
      budget.complete(sessionId: 'attempt-1', captureTimestampNs: 1000);

      expect(
        budget.reserve(
          sessionId: 'attempt-1',
          captureTimestampNs: 1500,
          requests: _threeRoutes(1500),
        ),
        isEmpty,
      );
      expect(
        budget.reserve(
          sessionId: 'attempt-1',
          captureTimestampNs: 900,
          requests: _threeRoutes(900),
        ),
        isEmpty,
      );

      final next = budget.reserve(
        sessionId: 'attempt-1',
        captureTimestampNs: 1900,
        requests: _threeRoutes(1900),
      );
      expect(next, hasLength(2));
    },
  );

  test('rotates fairly across earbud, watch, and desk routes', () {
    final budget = E1SpecialistExecutionBudget(
      minCaptureIntervalNs: 0,
      maxRequestsPerFrame: 2,
    );

    Set<String> strategies(List<E1SmallObjectSpecialistRequest> requests) =>
        requests.map((request) => request.roiHint.strategy).toSet();

    final first = budget.reserve(
      sessionId: 'attempt-1',
      captureTimestampNs: 1000,
      requests: _threeRoutes(1000),
    );
    expect(
      strategies(first),
      equals(<String>{'person_head_earbud', 'person_arm_watch'}),
    );
    budget.complete(sessionId: 'attempt-1', captureTimestampNs: 1000);

    final second = budget.reserve(
      sessionId: 'attempt-1',
      captureTimestampNs: 1001,
      requests: _threeRoutes(1001),
    );
    expect(
      strategies(second),
      equals(<String>{'desk_anchor_union', 'person_head_earbud'}),
    );
    budget.complete(sessionId: 'attempt-1', captureTimestampNs: 1001);

    final third = budget.reserve(
      sessionId: 'attempt-1',
      captureTimestampNs: 1002,
      requests: _threeRoutes(1002),
    );
    expect(
      strategies(third),
      equals(<String>{'person_arm_watch', 'desk_anchor_union'}),
    );
  });

  test('rotates between multiple ROIs sharing one specialist route', () {
    final budget = E1SpecialistExecutionBudget(
      minCaptureIntervalNs: 0,
      maxRequestsPerFrame: 1,
    );

    List<E1SmallObjectSpecialistRequest> people(int captureTimestampNs) =>
        <E1SmallObjectSpecialistRequest>[
          _request(
            captureTimestampNs: captureTimestampNs,
            strategy: 'person_head_earbud',
            target: E1SmallObjectTarget.earbud,
            x: 0.1,
          ),
          _request(
            captureTimestampNs: captureTimestampNs,
            strategy: 'person_head_earbud',
            target: E1SmallObjectTarget.earbud,
            x: 0.6,
          ),
        ];

    final first = budget.reserve(
      sessionId: 'attempt-1',
      captureTimestampNs: 10,
      requests: people(10),
    );
    expect(first.single.roiHint.roi!.x, 0.1);
    budget.complete(sessionId: 'attempt-1', captureTimestampNs: 10);

    final second = budget.reserve(
      sessionId: 'attempt-1',
      captureTimestampNs: 11,
      requests: people(11),
    );
    expect(second.single.roiHint.roi!.x, 0.6);
    budget.complete(sessionId: 'attempt-1', captureTimestampNs: 11);

    final third = budget.reserve(
      sessionId: 'attempt-1',
      captureTimestampNs: 12,
      requests: people(12),
    );
    expect(third.single.roiHint.roi!.x, 0.1);
  });

  test('in-flight reservation blocks overlapping specialist batches', () {
    final budget = E1SpecialistExecutionBudget(
      minCaptureIntervalNs: 0,
      maxRequestsPerFrame: 2,
    );

    final first = budget.reserve(
      sessionId: 'attempt-1',
      captureTimestampNs: 100,
      requests: _threeRoutes(100),
    );
    expect(first, isNotEmpty);
    expect(budget.inFlight, isTrue);

    final overlapping = budget.reserve(
      sessionId: 'attempt-1',
      captureTimestampNs: 101,
      requests: _threeRoutes(101),
    );
    expect(overlapping, isEmpty);

    budget.complete(sessionId: 'attempt-1', captureTimestampNs: 100);
    expect(budget.inFlight, isFalse);

    final afterCompletion = budget.reserve(
      sessionId: 'attempt-1',
      captureTimestampNs: 101,
      requests: _threeRoutes(101),
    );
    expect(afterCompletion, isNotEmpty);
  });

  test('clearSession resets capture-time cooldown and fairness state', () {
    final budget = E1SpecialistExecutionBudget(
      minCaptureIntervalNs: 1000,
      maxRequestsPerFrame: 1,
    );

    final first = budget.reserve(
      sessionId: 'attempt-1',
      captureTimestampNs: 5000,
      requests: _threeRoutes(5000),
    );
    expect(first, hasLength(1));
    budget.complete(sessionId: 'attempt-1', captureTimestampNs: 5000);
    budget.clearSession('attempt-1');

    final restarted = budget.reserve(
      sessionId: 'attempt-1',
      captureTimestampNs: 10,
      requests: _threeRoutes(10),
    );
    expect(restarted, hasLength(1));
    expect(restarted.single.roiHint.strategy, 'person_head_earbud');
  });
}

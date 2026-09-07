import 'e1_small_object_specialist.dart';

/// Bounds live specialist inference without creating, suppressing, or
/// reinterpreting evidence.
///
/// Scheduling is anchored to the original monotonic camera capture timestamp.
/// A request skipped here remains simply unobserved/UNKNOWN; it must never be
/// translated into negative evidence about the target object.
class E1SpecialistExecutionBudget {
  E1SpecialistExecutionBudget({
    this.minCaptureIntervalNs = 900000000,
    this.maxRequestsPerFrame = 2,
  });

  /// Initial engineering cooldown between specialist batches. This is an
  /// execution bound, not an evidential or behavioural threshold, and can be
  /// tuned later from device calibration data.
  final int minCaptureIntervalNs;

  /// Maximum number of distinct specialist routes executed for one source
  /// frame. At most one request is chosen from each route in a batch.
  final int maxRequestsPerFrame;

  String? _sessionId;
  int? _lastReservedCaptureTimestampNs;
  int? _reservedCaptureTimestampNs;
  bool _inFlight = false;
  int _routeCursor = 0;
  final Map<String, int> _requestCursorByRoute = <String, int>{};

  bool get inFlight => _inFlight;
  int? get lastReservedCaptureTimestampNs => _lastReservedCaptureTimestampNs;

  /// Reserves a bounded specialist batch for [captureTimestampNs].
  ///
  /// Duplicate/stale captures, captures still inside the cooldown, and calls
  /// arriving while another specialist batch is in flight are not scheduled.
  List<E1SmallObjectSpecialistRequest> reserve({
    required String sessionId,
    required int captureTimestampNs,
    required Iterable<E1SmallObjectSpecialistRequest> requests,
  }) {
    if (sessionId.trim().isEmpty ||
        captureTimestampNs < 0 ||
        minCaptureIntervalNs < 0 ||
        maxRequestsPerFrame <= 0) {
      return const <E1SmallObjectSpecialistRequest>[];
    }

    if (_sessionId != sessionId) {
      if (_inFlight) {
        return const <E1SmallObjectSpecialistRequest>[];
      }
      _resetForSession(sessionId);
    }
    if (_inFlight) {
      return const <E1SmallObjectSpecialistRequest>[];
    }

    final lastCapture = _lastReservedCaptureTimestampNs;
    if (lastCapture != null) {
      if (captureTimestampNs <= lastCapture) {
        return const <E1SmallObjectSpecialistRequest>[];
      }
      if (captureTimestampNs - lastCapture < minCaptureIntervalNs) {
        return const <E1SmallObjectSpecialistRequest>[];
      }
    }

    final eligible = requests
        .where(
          (request) =>
              request.isValid &&
              request.sessionId == sessionId &&
              request.captureTimestampNs == captureTimestampNs,
        )
        .toList(growable: false);
    if (eligible.isEmpty) {
      return const <E1SmallObjectSpecialistRequest>[];
    }

    final groups = <String, List<E1SmallObjectSpecialistRequest>>{};
    for (final request in eligible) {
      groups
          .putIfAbsent(
            _routeKey(request),
            () => <E1SmallObjectSpecialistRequest>[],
          )
          .add(request);
    }
    if (groups.isEmpty) {
      return const <E1SmallObjectSpecialistRequest>[];
    }

    final routeKeys = groups.keys.toList(growable: false);
    final routeCount = routeKeys.length;
    final start = _routeCursor % routeCount;
    final selectedRouteCount = maxRequestsPerFrame < routeCount
        ? maxRequestsPerFrame
        : routeCount;
    final selected = <E1SmallObjectSpecialistRequest>[];

    for (var offset = 0; offset < selectedRouteCount; offset++) {
      final routeKey = routeKeys[(start + offset) % routeCount];
      final routeRequests = groups[routeKey]!;
      final requestCursor = _requestCursorByRoute[routeKey] ?? 0;
      selected.add(routeRequests[requestCursor % routeRequests.length]);
      _requestCursorByRoute[routeKey] = requestCursor + 1;
    }

    if (selected.isEmpty) {
      return const <E1SmallObjectSpecialistRequest>[];
    }

    _routeCursor = (start + selected.length) % routeCount;
    _lastReservedCaptureTimestampNs = captureTimestampNs;
    _reservedCaptureTimestampNs = captureTimestampNs;
    _inFlight = true;
    return List<E1SmallObjectSpecialistRequest>.unmodifiable(selected);
  }

  /// Releases the in-flight reservation for the exact scheduled batch.
  void complete({required String sessionId, required int captureTimestampNs}) {
    if (_sessionId != sessionId ||
        _reservedCaptureTimestampNs != captureTimestampNs) {
      return;
    }
    _reservedCaptureTimestampNs = null;
    _inFlight = false;
  }

  /// Clears scheduling state only for the matching attempt/session lifecycle.
  void clearSession(String sessionId) {
    if (sessionId.trim().isEmpty || _sessionId != sessionId) return;
    _sessionId = null;
    _lastReservedCaptureTimestampNs = null;
    _reservedCaptureTimestampNs = null;
    _inFlight = false;
    _routeCursor = 0;
    _requestCursorByRoute.clear();
  }

  void _resetForSession(String sessionId) {
    _sessionId = sessionId;
    _lastReservedCaptureTimestampNs = null;
    _reservedCaptureTimestampNs = null;
    _inFlight = false;
    _routeCursor = 0;
    _requestCursorByRoute.clear();
  }

  String _routeKey(E1SmallObjectSpecialistRequest request) {
    final targets =
        request.targets
            .map((target) => target.canonicalObjectId)
            .toList(growable: false)
          ..sort();
    return '${request.roiHint.strategy}|${targets.join(',')}';
  }
}

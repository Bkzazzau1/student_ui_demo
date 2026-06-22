class CameraRuntimeLease {
  const CameraRuntimeLease._({
    required this.owner,
    required this.purpose,
    required this.acquiredAt,
  });

  final String owner;
  final String purpose;
  final DateTime acquiredAt;

  Map<String, Object?> toJson() => <String, Object?>{
        'owner': owner,
        'purpose': purpose,
        'acquired_at': acquiredAt.toUtc().toIso8601String(),
      };
}

/// Coordinates webcam ownership inside the exam runtime.
///
/// Flutter camera plugins commonly fail or freeze when multiple widgets open
/// independent controllers for the same physical webcam. Before adding YOLO,
/// camera ownership must be explicit so live monitoring, review capture, and
/// object detection do not fight each other.
class CameraRuntimeCoordinator {
  CameraRuntimeCoordinator._();

  static final CameraRuntimeCoordinator instance = CameraRuntimeCoordinator._();

  CameraRuntimeLease? _activeLease;

  CameraRuntimeLease? get activeLease => _activeLease;
  bool get isBusy => _activeLease != null;

  bool isOwnedBy(String owner) => _activeLease?.owner == owner;

  CameraRuntimeLease? tryAcquire({
    required String owner,
    required String purpose,
  }) {
    final lease = _activeLease;
    if (lease != null && lease.owner != owner) {
      return null;
    }

    final next = CameraRuntimeLease._(
      owner: owner,
      purpose: purpose,
      acquiredAt: DateTime.now(),
    );
    _activeLease = next;
    return next;
  }

  void release(String owner) {
    final lease = _activeLease;
    if (lease == null || lease.owner != owner) return;
    _activeLease = null;
  }

  Map<String, Object?> currentState() {
    final lease = _activeLease;
    return <String, Object?>{
      'camera_runtime_busy': lease != null,
      if (lease != null) 'active_lease': lease.toJson(),
    };
  }
}

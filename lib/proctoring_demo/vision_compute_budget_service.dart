import 'dart:math' as math;

class VisionComputeBudgetStatus {
  const VisionComputeBudgetStatus({
    required this.targetUtilization,
    required this.estimatedUtilization,
    required this.averageWorkMs,
    required this.dynamicIntervalMs,
    required this.processedFrames,
    required this.skippedFrames,
    required this.throttled,
  });

  final double targetUtilization;
  final double estimatedUtilization;
  final double averageWorkMs;
  final int dynamicIntervalMs;
  final int processedFrames;
  final int skippedFrames;
  final bool throttled;

  Map<String, Object?> toJson() => <String, Object?>{
        'target_utilization': targetUtilization,
        'estimated_utilization': estimatedUtilization,
        'average_work_ms': averageWorkMs,
        'dynamic_interval_ms': dynamicIntervalMs,
        'processed_frames': processedFrames,
        'skipped_frames': skippedFrames,
        'throttled': throttled,
      };
}

class VisionComputeBudgetService {
  VisionComputeBudgetService({
    this.targetUtilization = 0.15,
    this.minIntervalMs = 650,
    this.maxIntervalMs = 2800,
  });

  final double targetUtilization;
  final int minIntervalMs;
  final int maxIntervalMs;

  DateTime? _lastWorkAt;
  double _emaWorkMs = 0;
  int _dynamicIntervalMs = 900;
  int _processedFrames = 0;
  int _skippedFrames = 0;

  bool shouldProcessFrame() {
    final now = DateTime.now();
    final last = _lastWorkAt;
    if (last != null && now.difference(last).inMilliseconds < _dynamicIntervalMs) {
      _skippedFrames++;
      return false;
    }
    _lastWorkAt = now;
    return true;
  }

  void recordWork(Duration duration) {
    final workMs = duration.inMicroseconds / 1000.0;
    _processedFrames++;
    _emaWorkMs = _emaWorkMs == 0 ? workMs : (_emaWorkMs * 0.82) + (workMs * 0.18);
    final estimated = _estimatedUtilization();
    if (estimated > targetUtilization) {
      _dynamicIntervalMs = math.min(maxIntervalMs, _dynamicIntervalMs + 150);
    } else if (estimated < targetUtilization * 0.55) {
      _dynamicIntervalMs = math.max(minIntervalMs, _dynamicIntervalMs - 80);
    }
  }

  VisionComputeBudgetStatus status() {
    return VisionComputeBudgetStatus(
      targetUtilization: targetUtilization,
      estimatedUtilization: _estimatedUtilization(),
      averageWorkMs: _emaWorkMs,
      dynamicIntervalMs: _dynamicIntervalMs,
      processedFrames: _processedFrames,
      skippedFrames: _skippedFrames,
      throttled: _estimatedUtilization() > targetUtilization,
    );
  }

  double _estimatedUtilization() {
    if (_emaWorkMs <= 0 || _dynamicIntervalMs <= 0) return 0;
    return (_emaWorkMs / _dynamicIntervalMs).clamp(0.0, 1.0);
  }
}

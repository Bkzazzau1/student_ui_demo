enum DemoScanStatus { idle, scanning, passed, failed, pendingReview }

class DemoScanTarget {
  const DemoScanTarget({
    required this.name,
    this.captured = false,
    this.framePath,
    this.labels = const <String>[],
  });

  final String name;
  final bool captured;
  final String? framePath;
  final List<String> labels;

  DemoScanTarget copyWith({
    bool? captured,
    String? framePath,
    List<String>? labels,
  }) {
    return DemoScanTarget(
      name: name,
      captured: captured ?? this.captured,
      framePath: framePath ?? this.framePath,
      labels: labels ?? this.labels,
    );
  }
}

class DemoCalibrationEntry {
  const DemoCalibrationEntry({
    required this.target,
    required this.mode,
    required this.lightingScore,
    required this.motionScore,
    required this.sceneScore,
    required this.labels,
    required this.note,
    required this.timestamp,
    this.framePath,
  });

  final String target;
  final String mode;
  final double lightingScore;
  final double motionScore;
  final double sceneScore;
  final List<String> labels;
  final String note;
  final DateTime timestamp;
  final String? framePath;

  Map<String, Object?> toJson() => <String, Object?>{
    'target': target,
    'mode': mode,
    'lighting_score': lightingScore,
    'motion_score': motionScore,
    'scene_score': sceneScore,
    'labels': labels,
    'note': note,
    'timestamp': timestamp.toIso8601String(),
    if (framePath != null) 'frame_path': framePath,
  };
}

class AgenticReviewEvent {
  const AgenticReviewEvent({
    required this.title,
    required this.detail,
    required this.severity,
  });

  final String title;
  final String detail;
  final String severity;
}

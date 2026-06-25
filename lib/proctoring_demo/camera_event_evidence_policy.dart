class CameraEventEvidencePolicy {
  const CameraEventEvidencePolicy();

  static const Set<String> defaultCameraEvidenceEvents = <String>{
    'multiple_people_detected',
    'camera_view_needs_review',
    'gaze_head_pose_deviation',
    'sustained_gaze_head_pose_deviation',
    'continuous_liveness_spoof_risk',
    'object_reflection_shadow_risk',
    'low_light_guidance',
    'camera_reconnect_timeout',
    'camera_runtime_busy',
  };

  bool shouldCapture({
    required String eventType,
    required String severity,
  }) {
    final type = eventType.trim().toLowerCase();
    if (defaultCameraEvidenceEvents.contains(type)) return true;

    final level = severity.trim().toLowerCase();
    final visualType = type.contains('camera') ||
        type.contains('gaze') ||
        type.contains('liveness') ||
        type.contains('object') ||
        type.contains('reflection') ||
        type.contains('shadow') ||
        type.contains('light') ||
        type.contains('people') ||
        type.contains('person');
    return visualType &&
        (level == 'warning' || level == 'high' || level == 'critical');
  }
}

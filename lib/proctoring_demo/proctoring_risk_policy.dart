class ProctoringRiskDecision {
  const ProctoringRiskDecision({
    required this.eventType,
    required this.points,
    required this.level,
    required this.shouldPause,
  });

  final String eventType;
  final int points;
  final String level;
  final bool shouldPause;

  Map<String, Object?> toJson() => <String, Object?>{
        'event_type': eventType,
        'points': points,
        'level': level,
        'should_pause': shouldPause,
      };
}

/// Official local scoring policy for the student app.
///
/// The backend remains the final authority, but local code must use one shared
/// policy so camera, audio, screen, device, and future YOLO object events are
/// treated consistently.
class ProctoringRiskPolicy {
  const ProctoringRiskPolicy._();

  static const String version = '2026.06.pre-yolo.5';

  static String levelForScore(int score) {
    if (score >= 81) return 'critical';
    if (score >= 51) return 'high';
    if (score >= 21) return 'medium';
    return 'low';
  }

  static ProctoringRiskDecision decisionFor(String eventType) {
    final points = pointsFor(eventType);
    final level = levelForScore(points);
    return ProctoringRiskDecision(
      eventType: eventType,
      points: points,
      level: level,
      shouldPause: shouldPause(eventType: eventType, level: level),
    );
  }

  static int pointsFor(String eventType) {
    switch (eventType) {
      case 'exam_started':
      case 'exam_submitted':
      case 'exam_auto_submitted':
      case 'review_clip_captured':
      case 'review_clip_deferred_to_live_camera':
      case 'companion_cam_qr_generated':
      case 'companion_cam_connected':
      case 'object_model_asset_missing':
      case 'object_model_frame_gate_ready':
        return 0;
      case 'exam_screen_focus_changed':
        return 15;
      case 'exam_screen_backgrounded':
        return 35;
      case 'camera_runtime_busy':
      case 'review_clip_camera_busy':
        return 10;
      case 'camera_unavailable':
      case 'camera_reconnect_timeout':
        return 50;
      case 'microphone_unavailable':
      case 'microphone_reconnect_timeout':
        return 35;
      case 'system_monitoring_unavailable':
        return 50;
      case 'gaze_head_pose_monitor_unavailable':
      case 'continuous_liveness_monitor_unavailable':
      case 'object_reflection_shadow_monitor_unavailable':
      case 'review_clip_camera_unavailable':
      case 'review_clip_setup_failed':
      case 'review_clip_capture_failed':
      case 'companion_cam_server_failed':
        return 10;
      case 'camera_view_needs_review':
        return 20;
      case 'multiple_people_detected':
        return 55;
      case 'object_reflection_shadow_warning':
        return 10;
      case 'object_reflection_shadow_risk':
        return 35;
      case 'continuous_liveness_continuity_loss':
        return 15;
      case 'continuous_liveness_spoof_risk':
        return 50;
      case 'audio_voice_isolation_alert':
        return 35;
      case 'background_voice_environment_warning':
        return 10;
      case 'audio_repeated_fingerprint_detected':
        return 15;
      case 'gaze_head_pose_deviation':
        return 20;
      case 'companion_cam_feed_stale':
        return 30;
      case 'companion_cam_disconnected':
        return 15;
      case 'yolo_phone_detected':
        return 30;
      case 'yolo_book_or_paper_detected':
        return 25;
      case 'yolo_calculator_detected':
        return 20;
      case 'yolo_extra_screen_detected':
        return 35;
      default:
        return 0;
    }
  }

  static bool shouldPause({
    required String eventType,
    required String level,
  }) {
    if (level == 'critical') return true;
    const hardPauseEvents = <String>{
      'camera_unavailable',
      'camera_reconnect_timeout',
      'microphone_unavailable',
      'microphone_reconnect_timeout',
      'exam_screen_backgrounded',
      'companion_cam_feed_stale',
      'multiple_people_detected',
      'object_reflection_shadow_risk',
      'continuous_liveness_spoof_risk',
      'audio_voice_isolation_alert',
      'gaze_head_pose_deviation',
      'system_monitoring_unavailable',
      'yolo_phone_detected',
      'yolo_extra_screen_detected',
    };
    return hardPauseEvents.contains(eventType);
  }

  static String severityForPoints(int points) {
    if (points >= 50) return 'critical';
    if (points >= 30) return 'high';
    if (points >= 10) return 'warning';
    return 'info';
  }
}

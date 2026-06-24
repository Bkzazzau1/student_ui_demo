import 'package:flutter/material.dart';

import 'live_system_lockdown_monitor.dart';

class LiveSystemSecurityMonitor extends StatelessWidget {
  const LiveSystemSecurityMonitor({
    super.key,
    required this.studentId,
    required this.examId,
    required this.attemptId,
    required this.onCriticalEvent,
    this.assessmentType = 'exam',
    this.reviewAudience = 'invigilator',
  });

  final String studentId;
  final String examId;
  final String attemptId;
  final ValueChanged<String> onCriticalEvent;
  final String assessmentType;
  final String reviewAudience;

  @override
  Widget build(BuildContext context) {
    return LiveSystemLockdownMonitor(
      studentId: studentId,
      examId: examId,
      attemptId: attemptId,
      onReviewRequired: onCriticalEvent,
      assessmentType: assessmentType,
      reviewAudience: reviewAudience,
    );
  }
}

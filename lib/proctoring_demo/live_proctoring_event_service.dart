import 'dart:convert';

import 'package:http/http.dart' as http;

class LiveProctoringEvent {
  const LiveProctoringEvent({
    required this.studentId,
    required this.examId,
    required this.attemptId,
    required this.eventType,
    required this.severity,
    required this.message,
    required this.createdAt,
    this.metadata = const <String, Object?>{},
    this.assessmentType = 'exam',
    this.reviewAudience = 'invigilator',
  });

  final String studentId;
  final String examId;
  final String attemptId;
  final String eventType;
  final String severity;
  final String message;
  final DateTime createdAt;
  final Map<String, Object?> metadata;
  final String assessmentType;
  final String reviewAudience;

  Map<String, Object?> toJson() => <String, Object?>{
    'student_id': studentId,
    'exam_id': examId,
    'attempt_id': attemptId,
    'event_type': eventType,
    'severity': severity,
    'message': message,
    'created_at': createdAt.toUtc().toIso8601String(),
    'assessment_type': assessmentType,
    'review_audience': reviewAudience,
    if (metadata.isNotEmpty) 'metadata': metadata,
  };
}

class LiveProctoringEventService {
  LiveProctoringEventService({http.Client? client, required this.baseUrl})
    : _client = client ?? http.Client();

  final http.Client _client;
  final String baseUrl;

  Future<bool> send(LiveProctoringEvent event) async {
    final payload = jsonEncode(event.toJson());
    final attempts = <Uri>[
      Uri.parse('$baseUrl/api/proctoring/live-events'),
      Uri.parse('$baseUrl/api/proctoring/pre-exam-review'),
      Uri.parse(
        '$baseUrl/api/exam-attempts/${event.attemptId}/proctoring-alerts',
      ),
    ];

    for (final uri in attempts) {
      try {
        final response = await _client.post(
          uri,
          headers: const <String, String>{'Content-Type': 'application/json'},
          body: payload,
        );
        if (response.statusCode >= 200 && response.statusCode < 300) {
          return true;
        }
      } catch (_) {
        // Try the next compatible endpoint. The caller will enforce locally if all fail.
      }
    }
    return false;
  }

  void dispose() => _client.close();
}

import 'dart:convert';

import 'package:http/http.dart' as http;

class ExamStartApprovalService {
  ExamStartApprovalService({
    http.Client? client,
    required this.baseUrl,
  }) : _client = client ?? http.Client();

  final http.Client _client;
  final String baseUrl;

  Future<ExamStartApprovalResult> requestStartApproval({
    required String studentId,
    required String examId,
    required String attemptId,
    required String? manifestPath,
    required bool faceIdReady,
    required bool roomScanReady,
    required bool audioReady,
    required bool systemReady,
    Map<String, Object?> audioReview = const <String, Object?>{},
    Map<String, Object?> systemReview = const <String, Object?>{},
  }) async {
    final uri = Uri.parse('$baseUrl/api/proctoring/start-approval');
    final response = await _client.post(
      uri,
      headers: const <String, String>{
        'Content-Type': 'application/json',
      },
      body: jsonEncode(<String, Object?>{
        'student_id': studentId,
        'exam_id': examId,
        'attempt_id': attemptId,
        'manifest_path': manifestPath,
        'face_id_ready': faceIdReady,
        'room_scan_ready': roomScanReady,
        'audio_ready': audioReady,
        'system_ready': systemReady,
        'audio_review': audioReview,
        'system_review': systemReview,
        'source': 'desktop_exam_setup',
      }),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Start approval failed: ${response.statusCode}');
    }

    return ExamStartApprovalResult.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  void dispose() {
    _client.close();
  }
}

class ExamStartApprovalResult {
  const ExamStartApprovalResult({
    required this.status,
    required this.approvalSource,
    required this.aiRecommendation,
    required this.requiresHumanReview,
    required this.examStartToken,
    required this.message,
    required this.issues,
  });

  final String status;
  final String approvalSource;
  final String aiRecommendation;
  final bool requiresHumanReview;
  final String examStartToken;
  final String message;
  final List<String> issues;

  bool get approved =>
      status == 'approved_to_start' || status == 'approved' || status == 'allow';

  bool get hasToken => examStartToken.trim().isNotEmpty;

  factory ExamStartApprovalResult.fromJson(Map<String, dynamic> json) {
    final status = (json['status'] ?? json['decision'] ?? 'manual_review_required')
        .toString();
    return ExamStartApprovalResult(
      status: status,
      approvalSource: json['approval_source']?.toString() ??
          json['source']?.toString() ??
          'backend_rules',
      aiRecommendation: json['ai_recommendation']?.toString() ??
          json['risk_level']?.toString() ??
          'not_available',
      requiresHumanReview:
          json['requires_human_review'] == true || status.contains('review'),
      examStartToken: json['exam_start_token']?.toString() ??
          json['start_token']?.toString() ??
          json['token']?.toString() ??
          '',
      message: json['message']?.toString() ??
          json['summary']?.toString() ??
          'Start approval decision received.',
      issues: ((json['issues'] as List?) ?? const [])
          .map((item) => item.toString())
          .where((item) => item.trim().isNotEmpty)
          .toList(),
    );
  }
}

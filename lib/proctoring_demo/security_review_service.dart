import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

class SecurityReviewService {
  SecurityReviewService({http.Client? client, required this.baseUrl})
    : _client = client ?? http.Client();

  final http.Client _client;
  final String baseUrl;

  Future<SecurityReviewResult> submitPreExamReview({
    required Map<String, dynamic> manifest,
    required Map<String, String> imagePaths,
    String? audioClipPath,
    String? verificationVideoPath,
  }) async {
    final uri = Uri.parse('$baseUrl/api/proctoring/pre-exam-review');
    final request = http.MultipartRequest('POST', uri);
    request.fields['manifest'] = jsonEncode(manifest);

    for (final entry in imagePaths.entries) {
      request.files.add(
        await http.MultipartFile.fromPath(entry.key, entry.value),
      );
    }

    if (audioClipPath != null && audioClipPath.trim().isNotEmpty) {
      final file = File(audioClipPath);
      if (await file.exists()) {
        request.files.add(
          await http.MultipartFile.fromPath('audio_clip', audioClipPath),
        );
      }
    }

    if (verificationVideoPath != null && verificationVideoPath.trim().isNotEmpty) {
      final file = File(verificationVideoPath);
      if (await file.exists()) {
        request.files.add(
          await http.MultipartFile.fromPath('verification_video', verificationVideoPath),
        );
      }
    }

    final streamed = await _client.send(request);
    final response = await http.Response.fromStream(streamed);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Security review failed: ${response.statusCode}');
    }

    return SecurityReviewResult.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }
}

class SecurityReviewResult {
  const SecurityReviewResult({
    required this.reviewId,
    required this.decision,
    required this.riskLevel,
    required this.riskScore,
    required this.summary,
    required this.issues,
    required this.actions,
    required this.source,
    required this.findings,
    this.status = '',
    this.approvalSource = '',
    this.aiRecommendation = '',
    this.requiresHumanReview = false,
    this.examStartToken = '',
  });

  final String reviewId;
  final String decision;
  final String riskLevel;
  final int riskScore;
  final String summary;
  final List<String> issues;
  final List<String> actions;
  final String source;
  final List<SecurityFinding> findings;
  final String status;
  final String approvalSource;
  final String aiRecommendation;
  final bool requiresHumanReview;
  final String examStartToken;

  bool get approved =>
      status == 'approved_to_start' ||
      (status.isEmpty && decision == 'approved');
  bool get approvedToStart =>
      status == 'approved_to_start' && examStartToken.trim().isNotEmpty;
  bool get needsRescan =>
      status == 'rescan_required' || decision == 'rescan_required';
  bool get needsReview =>
      status == 'manual_review_required' ||
      status == 'review_required' ||
      decision == 'review_required';
  bool get blocked => status == 'blocked';
  bool get systemError => status == 'system_error';

  factory SecurityReviewResult.fromJson(Map<String, dynamic> json) {
    return SecurityReviewResult(
      reviewId: json['review_id']?.toString() ?? '',
      decision: json['decision']?.toString() ?? 'review_required',
      riskLevel: json['risk_level']?.toString() ?? 'medium',
      riskScore: int.tryParse(json['risk_score']?.toString() ?? '') ?? 50,
      summary: json['summary']?.toString() ?? 'Review completed.',
      issues: _stringList(json['issues']),
      actions: _stringList(json['actions']),
      source: json['source']?.toString() ?? '',
      findings: ((json['findings'] as List?) ?? const [])
          .whereType<Map>()
          .map(
            (item) => SecurityFinding.fromJson(Map<String, dynamic>.from(item)),
          )
          .toList(),
      status: json['status']?.toString() ?? '',
      approvalSource: json['approval_source']?.toString() ?? '',
      aiRecommendation: json['ai_recommendation']?.toString() ?? '',
      requiresHumanReview: json['requires_human_review'] == true,
      examStartToken: json['exam_start_token']?.toString() ?? '',
    );
  }

  static List<String> _stringList(Object? value) {
    return ((value as List?) ?? const [])
        .map((item) => item.toString().trim())
        .where((item) => item.isNotEmpty)
        .toList();
  }
}

class SecurityFinding {
  const SecurityFinding({
    required this.title,
    required this.detail,
    required this.severity,
  });

  final String title;
  final String detail;
  final String severity;

  factory SecurityFinding.fromJson(Map<String, dynamic> json) {
    return SecurityFinding(
      title: json['title']?.toString() ?? 'Review finding',
      detail: json['detail']?.toString() ?? '',
      severity: json['severity']?.toString() ?? 'info',
    );
  }
}

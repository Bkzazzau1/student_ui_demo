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
    required this.findings,
  });

  final String reviewId;
  final String decision;
  final String riskLevel;
  final int riskScore;
  final String summary;
  final List<SecurityFinding> findings;

  bool get approved => decision == 'approved';
  bool get needsRescan => decision == 'rescan_required';
  bool get needsReview => decision == 'review_required';

  factory SecurityReviewResult.fromJson(Map<String, dynamic> json) {
    return SecurityReviewResult(
      reviewId: json['review_id']?.toString() ?? '',
      decision: json['decision']?.toString() ?? 'review_required',
      riskLevel: json['risk_level']?.toString() ?? 'medium',
      riskScore: int.tryParse(json['risk_score']?.toString() ?? '') ?? 50,
      summary: json['summary']?.toString() ?? 'Review completed.',
      findings: ((json['findings'] as List?) ?? const [])
          .whereType<Map>()
          .map(
            (item) => SecurityFinding.fromJson(Map<String, dynamic>.from(item)),
          )
          .toList(),
    );
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

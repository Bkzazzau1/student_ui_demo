import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

class FaceIdentityEnrollmentApi {
  FaceIdentityEnrollmentApi({
    http.Client? client,
    required this.baseUrl,
  }) : _client = client ?? http.Client();

  final http.Client _client;
  final String baseUrl;

  Future<FaceIdentityEnrollmentResponse> submit({
    required String studentId,
    required List<FaceIdentityEnrollmentImage> images,
  }) async {
    final uri = Uri.parse('$baseUrl/api/identity/face-enrollment');
    final request = http.MultipartRequest('POST', uri);
    request.fields['manifest'] = jsonEncode(<String, Object?>{
      'student_id': studentId,
      'captured_at': DateTime.now().toUtc().toIso8601String(),
      'required_images': images.length,
      'purpose': 'exam_identity_reference',
      'reviewable_by_invigilator': true,
      'images': images
          .map(
            (image) => <String, Object?>{
              'field': image.fieldName,
              'pose_code': image.poseCode,
              'title': image.title,
              'instruction': image.instruction,
              'quality_score': image.qualityScore,
              'file_name': image.fileName,
            },
          )
          .toList(),
    });

    for (final image in images) {
      final file = File(image.path);
      if (!await file.exists()) continue;
      request.files.add(
        await http.MultipartFile.fromPath(image.fieldName, image.path),
      );
    }

    final streamed = await _client.send(request);
    final response = await http.Response.fromStream(streamed);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Identity enrollment failed: ${response.statusCode}');
    }

    final body = response.body.trim().isEmpty
        ? <String, dynamic>{}
        : jsonDecode(response.body) as Map<String, dynamic>;
    return FaceIdentityEnrollmentResponse.fromJson(body);
  }

  void dispose() => _client.close();
}

class FaceIdentityEnrollmentImage {
  const FaceIdentityEnrollmentImage({
    required this.fieldName,
    required this.poseCode,
    required this.title,
    required this.instruction,
    required this.path,
    required this.qualityScore,
  });

  final String fieldName;
  final String poseCode;
  final String title;
  final String instruction;
  final String path;
  final double qualityScore;

  String get fileName {
    final parts = path.split(RegExp(r'[\\/]'));
    return parts.isEmpty ? path : parts.last;
  }
}

class FaceIdentityEnrollmentResponse {
  const FaceIdentityEnrollmentResponse({
    required this.enrollmentId,
    required this.status,
    required this.message,
  });

  final String enrollmentId;
  final String status;
  final String message;

  factory FaceIdentityEnrollmentResponse.fromJson(Map<String, dynamic> json) {
    return FaceIdentityEnrollmentResponse(
      enrollmentId: json['enrollment_id']?.toString() ??
          json['id']?.toString() ??
          'pending-backend-enrollment',
      status: json['status']?.toString() ?? 'submitted',
      message: json['message']?.toString() ?? 'Identity images submitted for review.',
    );
  }
}

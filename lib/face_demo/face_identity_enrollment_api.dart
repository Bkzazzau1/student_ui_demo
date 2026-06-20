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

  Future<FaceIdentityEnrollmentResponse?> fetchLatest({
    required String studentId,
  }) async {
    final uri = Uri.parse('$baseUrl/api/identity/face-enrollments/latest')
        .replace(queryParameters: <String, String>{'student_id': studentId});
    final response = await _client.get(uri);
    if (response.statusCode == 404) return null;
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Identity enrollment sync failed: ${response.statusCode}');
    }
    return FaceIdentityEnrollmentResponse.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

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
      final body = response.body.trim();
      throw Exception(
        body.isEmpty
            ? 'Identity enrollment failed: ${response.statusCode}'
            : 'Identity enrollment failed: ${response.statusCode} $body',
      );
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

class FaceEnrollmentRemoteImage {
  const FaceEnrollmentRemoteImage({
    required this.poseCode,
    required this.title,
    required this.viewUrl,
    required this.qualityScore,
  });

  final String poseCode;
  final String title;
  final String viewUrl;
  final double qualityScore;

  factory FaceEnrollmentRemoteImage.fromJson(Map<String, dynamic> json) {
    return FaceEnrollmentRemoteImage(
      poseCode: json['pose_code']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      viewUrl: json['view_url']?.toString() ?? '',
      qualityScore: double.tryParse(json['quality_score']?.toString() ?? '') ?? 0,
    );
  }
}

class FaceIdentityEnrollmentResponse {
  const FaceIdentityEnrollmentResponse({
    required this.enrollmentId,
    required this.studentId,
    required this.status,
    required this.locked,
    required this.message,
    required this.requiredImages,
    required this.uploadedImages,
    required this.images,
  });

  final String enrollmentId;
  final String studentId;
  final String status;
  final bool locked;
  final String message;
  final int requiredImages;
  final int uploadedImages;
  final List<FaceEnrollmentRemoteImage> images;

  bool get activeLocked => locked && uploadedImages >= requiredImages && enrollmentId.isNotEmpty;

  factory FaceIdentityEnrollmentResponse.fromJson(Map<String, dynamic> json) {
    final images = ((json['images'] as List?) ?? const [])
        .whereType<Map>()
        .map((item) => FaceEnrollmentRemoteImage.fromJson(Map<String, dynamic>.from(item)))
        .toList();
    return FaceIdentityEnrollmentResponse(
      enrollmentId: json['enrollment_id']?.toString() ??
          json['id']?.toString() ??
          '',
      studentId: json['student_id']?.toString() ?? '',
      status: json['status']?.toString() ?? 'submitted',
      locked: json['locked'] == true || json['status']?.toString() == 'active_locked',
      message: json['message']?.toString() ?? 'Identity images submitted for review.',
      requiredImages: int.tryParse(json['required_images']?.toString() ?? '') ?? 6,
      uploadedImages: int.tryParse(json['uploaded_images']?.toString() ?? '') ?? images.length,
      images: images,
    );
  }
}

import 'package:flutter_test/flutter_test.dart';
import 'package:students_ui_demo/face_demo/face_identity_enrollment_api.dart';

void main() {
  test('accepts a complete encrypted portable template package', () {
    final package = FaceTemplateDownload.fromJson(<String, dynamic>{
      'student_id': 'student-1',
      'enrollment_id': 'enrollment-1',
      'template_version': 1,
      'model_id': 'kslas-face-embedding-v1',
      'model_sha256': 'a' * 64,
      'template_sha256': 'b' * 64,
      'encryption': 'envelope_v1',
      'key_id': 'biometric-key-1',
      'encrypted_template': 'opaque-ciphertext',
      'expires_at': '2027-01-01T00:00:00Z',
    });

    expect(package.structurallyValid, isTrue);
    expect(package.studentId, 'student-1');
  });

  test('rejects plaintext or incomplete template packages', () {
    final package = FaceTemplateDownload.fromJson(<String, dynamic>{
      'student_id': 'student-1',
      'template_version': 1,
      'encrypted_template': '',
    });

    expect(package.structurallyValid, isFalse);
  });
}

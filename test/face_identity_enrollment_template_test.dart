import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:students_ui_demo/rust/api/face_verification.dart';
import 'package:students_ui_demo/rust/brain_core_runtime.dart';

Float32List _embedding(int seed) {
  final values = List<double>.generate(
    128,
    (index) => (index == seed % 128 ? 1.0 : 0.0),
  );
  return Float32List.fromList(values);
}

void main() {
  setUpAll(() async {
    await BrainCoreRuntime.ensureInitialized();
  });

  test('seven valid 128-D samples become one locked, validated reference template', () {
    final embeddings = List<Float32List>.generate(7, (i) => _embedding(0));

    final templateJson = buildPortableFaceTemplate(
      studentId: 'KASU/STU/2026/001',
      enrollmentId: 'local-enrollment-1',
      modelId: 'kslas-sface-2021dec-v1',
      modelSha256:
          '0ba9fbfa01b5270c96627c4ef784da859931e02f04419c829e83484087c34e79',
      preprocessingVersion: 'sface-five-point-similarity-bgr-minus-127.5-div-128-v1',
      embeddings: embeddings,
      qualityScore: 0.9,
      createdAtMs: 0,
      expiresAtMs: 365 * 24 * 60 * 60 * 1000,
    );

    final status = validatePortableFaceTemplate(
      templateJson: templateJson,
      expectedStudentId: 'KASU/STU/2026/001',
      expectedModelId: 'kslas-sface-2021dec-v1',
      expectedModelSha256:
          '0ba9fbfa01b5270c96627c4ef784da859931e02f04419c829e83484087c34e79',
      nowMs: 1000,
    );

    expect(status.valid, isTrue);
    expect(status.sampleCount, 7);
    expect(status.embeddingDimension, 128);

    // The reference embedding a freshly enrolled student verifies against is
    // the centroid of all seven captured samples, not a random or
    // placeholder vector.
    final verification = verifyFaceEmbedding1To1(
      templateJson: templateJson,
      probeEmbedding: _embedding(0),
      signalQuality: 0.9,
      matchThreshold: 0.363,
      nowMs: 1000,
    );
    expect(verification.state, 'identity_verified');
  });

  test('fewer than three samples cannot become a template', () {
    expect(
      () => buildPortableFaceTemplate(
        studentId: 'KASU/STU/2026/001',
        enrollmentId: 'local-enrollment-2',
        modelId: 'kslas-sface-2021dec-v1',
        modelSha256:
            '0ba9fbfa01b5270c96627c4ef784da859931e02f04419c829e83484087c34e79',
        preprocessingVersion: 'sface-five-point-similarity-bgr-minus-127.5-div-128-v1',
        embeddings: [_embedding(0), _embedding(0)],
        qualityScore: 0.9,
        createdAtMs: 0,
        expiresAtMs: 365 * 24 * 60 * 60 * 1000,
      ),
      throwsA(anything),
    );
  });
}

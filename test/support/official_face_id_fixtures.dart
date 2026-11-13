import 'dart:typed_data';

import 'package:students_ui_demo/face_demo/face_embedding_pipeline.dart';
import 'package:students_ui_demo/face_demo/face_identity_landmark_matrix.dart';
import 'package:students_ui_demo/face_demo/face_identity_person_gate.dart';
import 'package:students_ui_demo/face_demo/face_identity_quality.dart';
import 'package:students_ui_demo/face_demo/face_identity_verification_service.dart';
import 'package:students_ui_demo/face_demo/native_face_embedding_runtime.dart';
import 'package:students_ui_demo/rust/api/official_face_id.dart';

const String testSeedHex =
    '0101010101010101010101010101010101010101010101010101010101010101';
const String testKeyId = 'test-school-key';

List<double> unitVector(int index, {int dimension = 128}) {
  final values = List<double>.filled(dimension, 0.0);
  values[index] = 1.0;
  return values;
}

String trustedKeysFor({String seed = testSeedHex, String keyId = testKeyId}) {
  final publicKey = sampleSchoolPublicKeyHex(signingSeedHex: seed);
  return '[{"key_id":"$keyId","public_key_hex":"$publicKey","environment":"sample"}]';
}

String issueTemplate({
  required String studentId,
  required List<List<double>> references,
  String preprocessingVersion = NativeFaceEmbeddingRuntime.preprocessingVersion,
  int issuedAtMs = 1000,
  int expiresAtMs = 1000 + 365 * 24 * 60 * 60 * 1000,
}) {
  return issueSampleSchoolOfficialTemplate(
    request: OfficialTemplateIssueRequest(
      templateId: 'tpl-test',
      institutionId: 'test-school',
      studentId: studentId,
      submissionId: 'sub-test',
      modelId: NativeFaceEmbeddingRuntime.modelId,
      modelSha256: NativeFaceEmbeddingRuntime.modelSha256,
      preprocessingVersion: preprocessingVersion,
      references: references
          .map((reference) => Float32List.fromList(reference))
          .toList(growable: false),
      referenceLabels: const <String>[],
      qualityScore: 0.9,
      buildSource: 'rebuilt_from_approved_photos',
      approvedBy: 'test-registrar',
      approvedAtMs: issuedAtMs,
      issuedAtMs: issuedAtMs,
      expiresAtMs: expiresAtMs,
    ),
    signingSeedHex: testSeedHex,
    keyId: testKeyId,
  );
}

OfficialFaceTemplateContext templateContext({
  required String studentId,
  required String envelope,
  String? trustedKeys,
  int nowMs = 5000,
}) {
  final keys = trustedKeys ?? trustedKeysFor();
  return OfficialFaceTemplateContext(
    studentId: studentId,
    envelopeJson: envelope,
    trustedKeysJson: keys,
    status: OfficialFaceTemplateContext.verify(
      studentId: studentId,
      envelopeJson: envelope,
      trustedKeysJson: keys,
      nowMs: nowMs,
    ),
  );
}

/// A template status for tests that never call into Rust.
OfficialFaceTemplateContext fakeTemplateContext(String studentId) =>
    OfficialFaceTemplateContext(
      studentId: studentId,
      envelopeJson: '{}',
      trustedKeysJson: '[]',
      status: OfficialFaceTemplateStatus(
        valid: true,
        reason: 'test',
        templateId: 'tpl-fake',
        institutionId: 'test-school',
        studentId: studentId,
        submissionId: 'sub-fake',
        keyId: testKeyId,
        keyEnvironment: 'sample',
        modelId: NativeFaceEmbeddingRuntime.modelId,
        preprocessingVersion: NativeFaceEmbeddingRuntime.preprocessingVersion,
        buildSource: 'rebuilt_from_approved_photos',
        referenceCount: 7,
        embeddingDimension: 128,
        approvedAtMs: 1000,
        expiresAtMs: 9000000000000,
        envelopeSha256: 'e' * 64,
      ),
    );

const _acceptedPersonGate = FaceIdentityPersonGateResult(
  state: FaceIdentityPersonGateState.accepted,
  personCount: 1,
  personConfidence: 0.95,
  reason: 'ok',
);

FaceEmbeddingPipelineResult pipelineSample(
  List<double> embedding, {
  double quality = 0.9,
}) {
  return FaceEmbeddingPipelineResult(
    embedding: embedding,
    quality: quality,
    faceConfidence: 0.9,
    alignedRgb: Uint8List(112 * 112 * 3),
    yaw: 0,
    pitch: 0,
    eyeOpenness: 0.05,
    smileWidth: 0.5,
    mouthOpenness: 0.02,
    landmarks: FaceLandmarkMatrix.empty(),
    personGate: _acceptedPersonGate,
    qualityGrade: FaceIdentityQualityGrade(
      overallScore: quality,
      level: FaceIdentityQualityLevel.good,
      personPresent: true,
      singlePerson: true,
      facePresent: true,
      landmarksComplete: true,
      eyesVisible: true,
      noseVisible: true,
      mouthVisible: true,
      faceCentered: true,
      faceCoverage: 0.5,
      poseAcceptable: true,
      alignmentAcceptable: true,
      faceConfidence: 0.9,
      personConfidence: 0.95,
      yaw: 0,
      pitch: 0,
      roll: 0,
      failureReasons: const <String>[],
    ),
  );
}

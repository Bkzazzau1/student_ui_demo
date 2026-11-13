import 'demo_exam_models.dart';
import 'demo_exam_service.dart';

/// Proof that the signed-in student just passed the 1:1 identity check for
/// this exam attempt. The school checks it against the uploaded evidence
/// record before releasing questions.
class IdentityPass {
  const IdentityPass({
    required this.studentId,
    required this.examId,
    required this.attemptId,
    required this.evidenceRecordId,
    required this.templateId,
    required this.verifiedAt,
  });

  final String studentId;
  final String examId;
  final String attemptId;
  final String evidenceRecordId;
  final String templateId;
  final DateTime verifiedAt;
}

class ExamQuestionsLocked implements Exception {
  const ExamQuestionsLocked(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Releases exam questions only after identity is confirmed.
///
/// Questions for an identity-checked assessment are not on the device before
/// the check passes; they are fetched with the [IdentityPass]. This sample
/// gate serves the built-in sample questions; the school system will serve
/// the real ones and verify the pass on its side.
class ExamQuestionGate {
  const ExamQuestionGate({this.maxPassAge = const Duration(minutes: 5)});

  final Duration maxPassAge;

  static bool requiresIdentity(DemoAssessment assessment) => assessment.graded;

  Future<List<DemoQuestion>> download({
    required DemoAssessment assessment,
    required String studentId,
    required String attemptId,
    IdentityPass? pass,
    DateTime? now,
  }) async {
    if (requiresIdentity(assessment)) {
      final problem = _problemWith(pass, assessment, studentId, attemptId, now);
      if (problem != null) throw ExamQuestionsLocked(problem);
    }
    return DemoExamService.questionsFor(assessment);
  }

  String? _problemWith(
    IdentityPass? pass,
    DemoAssessment assessment,
    String studentId,
    String attemptId,
    DateTime? now,
  ) {
    if (pass == null) {
      return 'Confirm your identity before the questions can be opened.';
    }
    if (pass.studentId != studentId ||
        pass.examId != assessment.id ||
        pass.attemptId != attemptId) {
      return 'This identity check belongs to a different exam attempt.';
    }
    if (pass.evidenceRecordId.isEmpty || pass.templateId.isEmpty) {
      return 'The identity check result is incomplete. Please check again.';
    }
    final age = (now ?? DateTime.now()).difference(pass.verifiedAt);
    if (age.isNegative || age > maxPassAge) {
      return 'Your identity check has expired. Please confirm it again.';
    }
    return null;
  }
}

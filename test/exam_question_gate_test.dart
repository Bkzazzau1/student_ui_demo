import 'package:flutter_test/flutter_test.dart';
import 'package:students_ui_demo/exam_demo/demo_exam_service.dart';
import 'package:students_ui_demo/exam_demo/exam_question_gate.dart';
import 'package:students_ui_demo/face_demo/official_face_id_models.dart';

void main() {
  const gate = ExamQuestionGate();
  final assessments = DemoExamService.assessments();
  final graded = assessments.firstWhere((assessment) => assessment.graded);
  final now = DateTime.utc(2026, 11, 13, 12);

  IdentityPass pass({
    String studentId = 'STD/1',
    String? examId,
    String attemptId = 'attempt-1',
    Duration age = const Duration(seconds: 30),
  }) => IdentityPass(
    studentId: studentId,
    examId: examId ?? graded.id,
    attemptId: attemptId,
    evidenceRecordId: 'idev-1',
    templateId: 'tpl-1',
    verifiedAt: now.subtract(age),
  );

  Future<Object?> download(IdentityPass? identity) async {
    try {
      return await gate.download(
        assessment: graded,
        studentId: 'STD/1',
        attemptId: 'attempt-1',
        pass: identity,
        now: now,
      );
    } on ExamQuestionsLocked catch (locked) {
      return locked;
    }
  }

  test('graded questions stay locked without a fresh identity pass', () async {
    expect(await download(null), isA<ExamQuestionsLocked>());
    expect(
      await download(pass(age: const Duration(minutes: 6))),
      isA<ExamQuestionsLocked>(),
    );
    expect(
      await download(pass(studentId: 'STD/2')),
      isA<ExamQuestionsLocked>(),
    );
    expect(
      await download(pass(attemptId: 'other')),
      isA<ExamQuestionsLocked>(),
    );
    expect(
      await download(pass(examId: 'other-exam')),
      isA<ExamQuestionsLocked>(),
    );
  });

  test(
    'a fresh pass for this student and attempt releases the questions',
    () async {
      final questions = await download(pass());
      expect(questions, isA<List<Object?>>());
      expect(questions as List, isNotEmpty);
    },
  );

  test('practice without identity does not need a pass', () async {
    final practice = assessments.where((assessment) => !assessment.graded);
    if (practice.isEmpty) return;
    final questions = await gate.download(
      assessment: practice.first,
      studentId: 'STD/1',
      attemptId: 'attempt-1',
    );
    expect(questions, isNotEmpty);
  });

  test('status shows approved while a replacement waits', () {
    final status = OfficialFaceIdStatus.fromJson(<String, Object?>{
      'student_id': 'STD/1',
      'active_template_id': 'tpl-1',
      'pending_submission_id': 'sub-2',
    });
    expect(status.state, OfficialFaceIdState.approved);
    expect(status.hasPendingSubmission, isTrue);
    expect(
      OfficialFaceIdStatus.fromJson(<String, Object?>{
        'student_id': 'STD/1',
        'last_rejection_reason': 'blurred',
      }).state,
      OfficialFaceIdState.rejected,
    );
  });
}

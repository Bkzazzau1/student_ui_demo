class DemoCourse {
  const DemoCourse({
    required this.code,
    required this.title,
    required this.lecturer,
  });

  final String code;
  final String title;
  final String lecturer;
}

class DemoAssessment {
  const DemoAssessment({
    required this.id,
    required this.course,
    required this.title,
    required this.kind,
    required this.durationMinutes,
    required this.graded,
    required this.remoteProctored,
    required this.sections,
  });

  final String id;
  final DemoCourse course;
  final String title;
  final String kind;
  final int durationMinutes;
  final bool graded;
  final bool remoteProctored;
  final List<DemoExamSection> sections;
}

enum DemoExamSection { objective, fillBlank, theory }

extension DemoExamSectionX on DemoExamSection {
  String get label {
    switch (this) {
      case DemoExamSection.objective:
        return 'Objective';
      case DemoExamSection.fillBlank:
        return 'Fill blank';
      case DemoExamSection.theory:
        return 'Theory';
    }
  }
}

class DemoQuestion {
  const DemoQuestion({
    required this.id,
    required this.section,
    required this.prompt,
    required this.marks,
    this.options = const <String>[],
    this.answer,
    this.keywords = const <String>[],
  });

  final String id;
  final DemoExamSection section;
  final String prompt;
  final int marks;
  final List<String> options;
  final String? answer;
  final List<String> keywords;
}

class DemoExamResult {
  const DemoExamResult({
    required this.assessment,
    required this.totalMarks,
    required this.scoredMarks,
    required this.startedAt,
    required this.endedAt,
    required this.proctoringManifestPath,
    required this.agentDecision,
  });

  final DemoAssessment assessment;
  final int totalMarks;
  final int scoredMarks;
  final DateTime startedAt;
  final DateTime endedAt;
  final String? proctoringManifestPath;
  final String agentDecision;

  int get percent =>
      totalMarks == 0 ? 0 : ((scoredMarks / totalMarks) * 100).round();
}

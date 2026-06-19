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
    this.policy = AssessmentPolicy.practice,
    this.availableDateIso,
    this.availableUntilIso,
    this.weeklyWeekday,
  });

  final String id;
  final DemoCourse course;
  final String title;
  final String kind;
  final int durationMinutes;
  final bool graded;
  final bool remoteProctored;
  final List<DemoExamSection> sections;
  final AssessmentPolicy policy;
  final String? availableDateIso;
  final String? availableUntilIso;
  final int? weeklyWeekday;

  bool get isStrictExam => policy == AssessmentPolicy.strictExam;

  bool get sendsEventsToLecturer => policy == AssessmentPolicy.gradedAssessment;

  bool get attendanceOnly => policy == AssessmentPolicy.practice;

  String get reviewAudience {
    if (attendanceOnly) return 'attendance';
    return sendsEventsToLecturer ? 'lecturer' : 'invigilator';
  }

  String get assessmentType {
    switch (policy) {
      case AssessmentPolicy.strictExam:
        return 'exam';
      case AssessmentPolicy.gradedAssessment:
        return 'graded_assessment';
      case AssessmentPolicy.practice:
        return 'practice';
    }
  }

  bool isAvailableOn(DateTime date) {
    final day = DateTime(date.year, date.month, date.day);
    final starts = _parseDate(availableDateIso);
    final ends = _parseDate(availableUntilIso);
    if (starts != null && day.isBefore(starts)) return false;
    if (ends != null && day.isAfter(ends)) return false;
    if (weeklyWeekday != null) return date.weekday == weeklyWeekday;
    if (starts != null) return _sameDay(day, starts);
    return true;
  }

  String scheduleLabel() {
    if (weeklyWeekday != null) {
      return 'Weekly ${_weekdayName(weeklyWeekday!)}';
    }
    final starts = _parseDate(availableDateIso);
    if (starts == null) return 'Open schedule';
    return '${starts.day.toString().padLeft(2, '0')}/${starts.month.toString().padLeft(2, '0')}/${starts.year}';
  }

  static DateTime? _parseDate(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final parsed = DateTime.tryParse(value);
    if (parsed == null) return null;
    return DateTime(parsed.year, parsed.month, parsed.day);
  }

  static bool _sameDay(DateTime left, DateTime right) =>
      left.year == right.year &&
      left.month == right.month &&
      left.day == right.day;

  static String _weekdayName(int weekday) {
    switch (weekday) {
      case DateTime.monday:
        return 'Monday';
      case DateTime.tuesday:
        return 'Tuesday';
      case DateTime.wednesday:
        return 'Wednesday';
      case DateTime.thursday:
        return 'Thursday';
      case DateTime.friday:
        return 'Friday';
      case DateTime.saturday:
        return 'Saturday';
      case DateTime.sunday:
        return 'Sunday';
      default:
        return 'week';
    }
  }
}

enum AssessmentPolicy { strictExam, gradedAssessment, practice }

extension AssessmentPolicyX on AssessmentPolicy {
  String get label {
    switch (this) {
      case AssessmentPolicy.strictExam:
        return 'Strict exam';
      case AssessmentPolicy.gradedAssessment:
        return 'Graded assessment';
      case AssessmentPolicy.practice:
        return 'Practice';
    }
  }
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

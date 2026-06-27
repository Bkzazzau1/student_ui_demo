import 'demo_exam_models.dart';

class DemoExamService {
  static const DemoCourse _csc305 = DemoCourse(
    code: 'CSC 305',
    title: 'Secure Examination Systems',
    lecturer: 'Dr. A. Bello',
  );

  static const DemoCourse _gst204 = DemoCourse(
    code: 'GST 204',
    title: 'Entrepreneurship and Innovation',
    lecturer: 'Dr. M. Okafor',
  );

  static const DemoCourse _mat221 = DemoCourse(
    code: 'MAT 221',
    title: 'Linear Algebra for Computing',
    lecturer: 'Dr. S. Musa',
  );

  static List<DemoCourse> courses() => const <DemoCourse>[
    _csc305,
    _gst204,
    _mat221,
  ];

  static List<DemoAssessment> assessments([DateTime? date]) =>
      assessmentsForDate(date ?? DateTime.now());

  static List<DemoAssessment> assessmentsForDate(DateTime date) {
    final scheduled = allAssessments()
        .where((assessment) => assessment.isAvailableOn(date))
        .toList();
    if (scheduled.isNotEmpty) {
      final sampleExam = _sampleExamForDate(date);
      return <DemoAssessment>[
        sampleExam,
        ...scheduled.where((assessment) => assessment.id != sampleExam.id),
      ];
    }
    return _sampleScheduleForDate(date);
  }

  static DemoAssessment _sampleExamForDate(DateTime date) {
    final dateIso = _dateIso(date);
    final idDate = '${date.year}-${date.month}-${date.day}';
    return DemoAssessment(
      id: 'sample-exam-$idDate',
      course: _csc305,
      title: 'Sample supervised exam for today',
      kind: 'Examination',
      durationMinutes: 20,
      graded: true,
      remoteProctored: true,
      policy: AssessmentPolicy.strictExam,
      availableDateIso: dateIso,
      sections: const <DemoExamSection>[
        DemoExamSection.objective,
        DemoExamSection.fillBlank,
        DemoExamSection.theory,
      ],
    );
  }

  static List<DemoAssessment> _sampleScheduleForDate(DateTime date) {
    final dateIso = _dateIso(date);
    final idDate = '${date.year}-${date.month}-${date.day}';
    return <DemoAssessment>[
      _sampleExamForDate(date),
      DemoAssessment(
        id: 'sample-graded-assessment-$idDate',
        course: _gst204,
        title: 'Continuous assessment quiz',
        kind: 'Graded assessment',
        durationMinutes: 15,
        graded: true,
        remoteProctored: false,
        policy: AssessmentPolicy.gradedAssessment,
        availableDateIso: dateIso,
        sections: const <DemoExamSection>[DemoExamSection.objective],
      ),
      DemoAssessment(
        id: 'sample-ungraded-assessment-$idDate',
        course: _csc305,
        title: 'Readiness self-check',
        kind: 'Ungraded assessment',
        durationMinutes: 10,
        graded: false,
        remoteProctored: false,
        policy: AssessmentPolicy.gradedAssessment,
        availableDateIso: dateIso,
        sections: const <DemoExamSection>[
          DemoExamSection.objective,
          DemoExamSection.fillBlank,
        ],
      ),
      DemoAssessment(
        id: 'sample-practice-$idDate',
        course: _mat221,
        title: 'Weekly practice questions',
        kind: 'Practice',
        durationMinutes: 20,
        graded: false,
        remoteProctored: false,
        policy: AssessmentPolicy.practice,
        availableDateIso: dateIso,
        sections: const <DemoExamSection>[
          DemoExamSection.objective,
          DemoExamSection.fillBlank,
        ],
      ),
    ];
  }

  static String _dateIso(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  static List<DemoAssessment> allAssessments() => const <DemoAssessment>[
    DemoAssessment(
      id: 'exam-csc305-first-semester',
      course: _csc305,
      title: 'First semester supervised examination',
      kind: 'Examination',
      durationMinutes: 35,
      graded: true,
      remoteProctored: true,
      policy: AssessmentPolicy.strictExam,
      availableDateIso: '2026-06-19',
      sections: <DemoExamSection>[
        DemoExamSection.objective,
        DemoExamSection.fillBlank,
        DemoExamSection.theory,
      ],
    ),
    DemoAssessment(
      id: 'assess-gst204-ca',
      course: _gst204,
      title: 'Continuous assessment quiz',
      kind: 'Graded assessment',
      durationMinutes: 15,
      graded: true,
      remoteProctored: false,
      policy: AssessmentPolicy.gradedAssessment,
      availableDateIso: '2026-06-19',
      sections: <DemoExamSection>[DemoExamSection.objective],
    ),
    DemoAssessment(
      id: 'assess-csc305-readiness',
      course: _csc305,
      title: 'Readiness self-check',
      kind: 'Ungraded assessment',
      durationMinutes: 10,
      graded: false,
      remoteProctored: false,
      policy: AssessmentPolicy.gradedAssessment,
      availableDateIso: '2026-06-19',
      sections: <DemoExamSection>[
        DemoExamSection.objective,
        DemoExamSection.fillBlank,
      ],
    ),
    DemoAssessment(
      id: 'practice-mat221-matrix',
      course: _mat221,
      title: 'Weekly matrix practice questions',
      kind: 'Practice',
      durationMinutes: 20,
      graded: false,
      remoteProctored: false,
      policy: AssessmentPolicy.practice,
      availableDateIso: '2026-06-19',
      weeklyWeekday: DateTime.friday,
      sections: <DemoExamSection>[
        DemoExamSection.objective,
        DemoExamSection.fillBlank,
      ],
    ),
  ];

  static List<DemoQuestion> questionsFor(DemoAssessment assessment) {
    final objective = <DemoQuestion>[
      const DemoQuestion(
        id: 'q1',
        section: DemoExamSection.objective,
        prompt: 'What should you do before you start a test?',
        marks: 1,
        options: <String>[
          'Read the instructions',
          'Skip the instructions',
          'Close the test',
          'Guess all answers',
        ],
        answer: 'Read the instructions',
      ),
      const DemoQuestion(
        id: 'q2',
        section: DemoExamSection.objective,
        prompt: 'Who should you contact if you cannot start a scheduled test?',
        marks: 1,
        options: <String>[
          'Your lecturer',
          'Another student',
          'A random website',
          'Nobody',
        ],
        answer: 'Your lecturer',
      ),
      const DemoQuestion(
        id: 'q3',
        section: DemoExamSection.objective,
        prompt: 'What should you keep ready before a supervised exam?',
        marks: 1,
        options: <String>[
          'Student ID',
          'Loud music',
          'Another person beside you',
          'A second phone',
        ],
        answer: 'Student ID',
      ),
    ];

    final fillBlank = <DemoQuestion>[
      const DemoQuestion(
        id: 'fb1',
        section: DemoExamSection.fillBlank,
        prompt: 'Weekly practice can be used to mark ____.',
        marks: 2,
        answer: 'attendance',
      ),
      const DemoQuestion(
        id: 'fb2',
        section: DemoExamSection.fillBlank,
        prompt: 'Submit your answers before the ____ ends.',
        marks: 2,
        answer: 'time',
      ),
    ];

    final theory = <DemoQuestion>[
      const DemoQuestion(
        id: 'th1',
        section: DemoExamSection.theory,
        prompt:
            'Explain three things a student should do to prepare for an online test.',
        marks: 5,
        keywords: <String>['read', 'time', 'quiet', 'id', 'internet', 'submit'],
      ),
    ];

    final all = <DemoQuestion>[...objective, ...fillBlank, ...theory];
    return all
        .where((question) => assessment.sections.contains(question.section))
        .toList();
  }
}

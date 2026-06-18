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

  static List<DemoAssessment> assessments() => const <DemoAssessment>[
    DemoAssessment(
      id: 'exam-csc305-first-semester',
      course: _csc305,
      title: 'First semester proctored examination',
      kind: 'Examination',
      durationMinutes: 35,
      graded: true,
      remoteProctored: true,
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
      kind: 'Assessment',
      durationMinutes: 15,
      graded: true,
      remoteProctored: false,
      sections: <DemoExamSection>[DemoExamSection.objective],
    ),
    DemoAssessment(
      id: 'practice-mat221-matrix',
      course: _mat221,
      title: 'Matrix operations practice test',
      kind: 'Practice',
      durationMinutes: 20,
      graded: false,
      remoteProctored: false,
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
        prompt:
            'Which review step combines evidence and recommends an examination action?',
        marks: 1,
        options: <String>[
          'Risk review',
          'Printer setup',
          'Course upload',
          'Result download',
        ],
        answer: 'Risk review',
      ),
      const DemoQuestion(
        id: 'q2',
        section: DemoExamSection.objective,
        prompt:
            'What should happen before a serious examination decision is finalized?',
        marks: 1,
        options: <String>[
          'Human review of evidence',
          'Automatic decision only',
          'Deleting the session',
          'Ignoring all logs',
        ],
        answer: 'Human review of evidence',
      ),
      const DemoQuestion(
        id: 'q3',
        section: DemoExamSection.objective,
        prompt:
            'Which item is normally unauthorized in a closed-book remote exam?',
        marks: 1,
        options: <String>[
          'Phone on desk',
          'Student ID',
          'Webcam',
          'Approved scratch paper',
        ],
        answer: 'Phone on desk',
      ),
    ];

    final fillBlank = <DemoQuestion>[
      const DemoQuestion(
        id: 'fb1',
        section: DemoExamSection.fillBlank,
        prompt:
            'The secure exam app sends structured ____ logs to the backend.',
        marks: 2,
        answer: 'event',
      ),
      const DemoQuestion(
        id: 'fb2',
        section: DemoExamSection.fillBlank,
        prompt:
            'A final proctoring decision should be based on evidence and ____ review.',
        marks: 2,
        answer: 'human',
      ),
    ];

    final theory = <DemoQuestion>[
      const DemoQuestion(
        id: 'th1',
        section: DemoExamSection.theory,
        prompt:
            'Explain how identity check, room scan, screen monitoring, audio monitoring, risk review, and evidence review should work before allowing an examination to start.',
        marks: 5,
        keywords: <String>[
          'identity',
          'room',
          'screen',
          'audio',
          'risk',
          'evidence',
          'review',
        ],
      ),
    ];

    final all = <DemoQuestion>[...objective, ...fillBlank, ...theory];
    return all
        .where((question) => assessment.sections.contains(question.section))
        .toList();
  }
}

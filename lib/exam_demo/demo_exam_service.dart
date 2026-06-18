import 'demo_exam_models.dart';

class DemoExamService {
  static const DemoCourse _csc305 = DemoCourse(
    code: 'CSC 305',
    title: 'Artificial Intelligence',
    lecturer: 'Dr. A. Bello',
  );

  static const DemoCourse _mat221 = DemoCourse(
    code: 'MAT 221',
    title: 'Linear Algebra',
    lecturer: 'Dr. M. Okafor',
  );

  static List<DemoCourse> courses() => const <DemoCourse>[_csc305, _mat221];

  static List<DemoAssessment> assessments() => const <DemoAssessment>[
    DemoAssessment(
      id: 'exam-csc305-mid',
      course: _csc305,
      title: 'Mid-semester examination',
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
      id: 'assess-csc305-quiz',
      course: _csc305,
      title: 'AI foundations quiz',
      kind: 'Assessment',
      durationMinutes: 15,
      graded: true,
      remoteProctored: false,
      sections: <DemoExamSection>[DemoExamSection.objective],
    ),
    DemoAssessment(
      id: 'exam-mat221-practice',
      course: _mat221,
      title: 'Matrix operations practice',
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
        prompt: 'Which AI technique searches possible actions using states?',
        marks: 1,
        options: <String>[
          'State-space search',
          'Data normalization',
          'Packet switching',
          'Memory paging',
        ],
        answer: 'State-space search',
      ),
      const DemoQuestion(
        id: 'q2',
        section: DemoExamSection.objective,
        prompt: 'A model that improves from examples is using what process?',
        marks: 1,
        options: <String>[
          'Machine learning',
          'Static routing',
          'Manual sorting',
          'Disk partitioning',
        ],
        answer: 'Machine learning',
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
        prompt: 'An AI agent senses its environment using ____.',
        marks: 2,
        answer: 'sensors',
      ),
      const DemoQuestion(
        id: 'fb2',
        section: DemoExamSection.fillBlank,
        prompt: 'The action chosen by an agent is executed through an ____.',
        marks: 2,
        answer: 'actuator',
      ),
    ];

    final theory = <DemoQuestion>[
      const DemoQuestion(
        id: 'th1',
        section: DemoExamSection.theory,
        prompt:
            'Explain how an agentic AI proctor should use evidence before making an exam startup decision.',
        marks: 5,
        keywords: <String>[
          'evidence',
          'camera',
          'lighting',
          'review',
          'decision',
        ],
      ),
    ];

    final all = <DemoQuestion>[...objective, ...fillBlank, ...theory];
    return all
        .where((question) => assessment.sections.contains(question.section))
        .toList();
  }
}

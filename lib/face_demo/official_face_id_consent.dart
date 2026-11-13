/// Consent shown before a student registers a Face ID.
///
/// DRAFT: this wording must be reviewed and approved by the school's data
/// protection officer and legal team before production use. Change
/// [version] whenever the text changes; the accepted version is stored with
/// every registration.
abstract final class OfficialFaceIdConsent {
  static const String version = 'kslas-face-id-consent-v1-draft-2026-11';

  static const String title = 'Your Face ID and your privacy';

  static const List<ConsentSection> sections = <ConsentSection>[
    ConsentSection(
      heading: 'What we collect',
      body:
          'Seven photos of your face taken now (front, turned, looking up '
          'and down, smiling, mouth open), and a face template: a set of '
          'numbers the face AI calculates from those photos.',
    ),
    ConsentSection(
      heading: 'Why',
      body:
          'Only to confirm that the person writing your exams, quizzes and '
          'graded assessments is you. Your face is only ever compared with '
          'your own Face ID. It is never used to search for or identify '
          'other people, and never for any other purpose.',
    ),
    ConsentSection(
      heading: 'Who approves and sees it',
      body:
          'Authorised school staff review your photos and approve or reject '
          'them. After approval the school signs your Face ID so that any '
          'device you sign in on can check it.',
    ),
    ConsentSection(
      heading: 'During exams',
      body:
          'The app checks your face on your own device before the questions '
          'open, and at random times during the exam. The live camera picture '
          'is not sent to the school. Only the result of each check is sent '
          'as evidence. If a check fails, one photo from that check is kept '
          'for up to 30 days so a person can review it. A failed check is '
          'never treated as cheating by itself; a person always decides.',
    ),
    ConsentSection(
      heading: 'How long we keep it',
      body:
          'Your approved Face ID is kept while you are a student and replaced '
          'whenever you register a new one. The school will tell you how long '
          'registration photos are kept after you leave.',
    ),
    ConsentSection(
      heading: 'Your choices',
      body:
          'You can ask the school to see, correct or delete your Face ID '
          'data. If you do not want to use Face ID, ask the exam office about '
          'another way to confirm your identity. Questions: contact the '
          "school's data protection officer.",
    ),
  ];

  static const String agreement =
      'I have read this and I agree that my face photos and Face ID are used '
      'as described above.';
}

class ConsentSection {
  const ConsentSection({required this.heading, required this.body});

  final String heading;
  final String body;
}

import 'official_face_id_consent.dart';

/// Consent for the Face ID accuracy study (volunteer calibration).
///
/// DRAFT: the school's data protection officer (and ethics committee, where
/// there is one) must approve this wording before any volunteer is
/// photographed. The signed paper form is
/// `docs/identity/volunteer_study_consent.md`; keep both texts the same and
/// change [version] whenever the wording changes. The app records the
/// version each volunteer agreed to.
abstract final class VolunteerStudyConsent {
  static const String version = 'kslas-face-study-consent-v1-draft-2026-11';

  static const String title = 'Face ID accuracy study';

  static const List<ConsentSection> sections = <ConsentSection>[
    ConsentSection(
      heading: 'Why',
      body:
          'K-SLAS checks that the person writing an exam is the registered '
          'student by comparing their face with their Face ID on the device. '
          'This study measures how accurate that check is on the laptops and '
          'tablets students use, and sets how strict it must be.',
    ),
    ConsentSection(
      heading: 'What we take',
      body:
          'About 30 to 40 photos of your face: 7 registration photos, then 3 '
          'photos per session on each study device, in normal light, in '
          'harder light and on another day. You get a study code such as '
          'v001; your name is never stored with the photos.',
    ),
    ConsentSection(
      heading: 'How they are used',
      body:
          'Only to calculate match scores for this study. A computer compares '
          'your photos with your own and with other volunteers\' photos to '
          'count how often the check makes mistakes. They are never used to '
          'identify you, in exams, to train AI, or for anything else.',
    ),
    ConsentSection(
      heading: 'Storage and deletion',
      body:
          'Photos are stored encrypted on the study devices and on the study '
          'computer. They are not uploaded to the internet or shared outside '
          'the study team. They are deleted within 30 days of the final '
          'report, which contains only numbers.',
    ),
    ConsentSection(
      heading: 'Your choices',
      body:
          'Taking part is voluntary and does not affect your studies or '
          'grades. You can stop at any time and ask for your photos to be '
          'deleted, without giving a reason.',
    ),
    ConsentSection(
      heading: 'Optional: spoofing test',
      body:
          'With your separate permission, we also show the app a printed photo '
          'and a phone video of you, to check that it is not fooled. These '
          'are deleted in the same way.',
    ),
  ];

  /// What staff confirm in the app before taking any photo.
  static const String staffConfirmation =
      'The volunteer has read and signed the paper consent form '
      '($version), and the study code matches the form.';

  static const String spoofTestConfirmation =
      'The volunteer also agreed to the optional spoofing test.';
}

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:students_ui_demo/face_demo/protected_local_store.dart';
import 'package:students_ui_demo/face_demo/volunteer_study_consent.dart';
import 'package:students_ui_demo/face_demo/volunteer_study_store.dart';
import 'package:students_ui_demo/face_demo/volunteer_study_view.dart';

Uint8List _jpeg(int seed) =>
    Uint8List.fromList(<int>[0xFF, 0xD8, seed, 0xFF, 0xD9]);

List<StudyRegistrationPhoto> _registration() => <StudyRegistrationPhoto>[
  for (final (index, pose) in const [
    'front_face',
    'left_angle',
    'right_angle',
    'look_down',
    'look_up',
    'smile',
    'open_mouth',
  ].indexed)
    StudyRegistrationPhoto(
      poseCode: pose,
      jpegBytes: _jpeg(index),
      qualityScore: 0.9,
    ),
];

void main() {
  group('VolunteerStudy codes and labels', () {
    test('study codes only, never names', () {
      expect(VolunteerStudy.normalizeCode(' V001 '), 'v001');
      expect(VolunteerStudy.normalizeCode('v1234'), 'v1234');
      expect(VolunteerStudy.normalizeCode('Amina Bello'), isNull);
      expect(VolunteerStudy.normalizeCode('v01'), isNull);
    });

    test('device labels become folder-safe', () {
      expect(
        VolunteerStudy.sanitizeDeviceLabel('Laptop Dell 3520!'),
        'laptop-dell-3520',
      );
      expect(VolunteerStudy.isValidDeviceLabel('laptop-dell-3520'), isTrue);
      expect(VolunteerStudy.isValidDeviceLabel('a'), isFalse);
      expect(VolunteerStudy.isValidDeviceLabel('-bad-'), isFalse);
    });

    test('sessions are three photos named for the tool\'s grouping', () {
      expect(StudySession.a.fileNames, ['a1.jpg', 'a2.jpg', 'a3.jpg']);
      expect(StudySession.c.fileNames.last, 'c3.jpg');
      expect(StudySession.fromCode('b'), StudySession.b);
    });
  });

  group('VolunteerStudyStore', () {
    late InMemoryProtectedLocalStore backing;
    late VolunteerStudyStore store;

    setUp(() {
      backing = InMemoryProtectedLocalStore();
      store = VolunteerStudyStore(
        backing,
        clock: () => DateTime.utc(2026, 11, 14, 10),
      );
    });

    test('nothing is captured without consent', () async {
      await expectLater(
        store.enrol(
          code: 'v001',
          deviceLabel: 'laptop-a',
          consentConfirmed: false,
        ),
        throwsA(isA<VolunteerStudyException>()),
      );
      await expectLater(
        store.saveSession(
          'v001',
          deviceLabel: 'laptop-a',
          session: StudySession.a,
          photos: [_jpeg(1), _jpeg(2), _jpeg(3)],
          attempts: 3,
          rejected: 0,
        ),
        throwsA(isA<VolunteerStudyException>()),
      );
      expect(await store.volunteerCodes(), isEmpty);
    });

    test('enrol records the consent version and no name', () async {
      final record = await store.enrol(
        code: 'V001',
        deviceLabel: 'laptop-a',
        consentConfirmed: true,
        spoofTestConsent: true,
      );
      expect(record.code, 'v001');
      expect(record.consentVersion, VolunteerStudyConsent.version);
      expect(record.spoofTestConsent, isTrue);
      expect(await store.volunteerCodes(), ['v001']);
      // Adding again keeps the original consent record.
      final again = await store.enrol(
        code: 'v001',
        deviceLabel: 'tablet-b',
        consentConfirmed: true,
      );
      expect(again.consentDeviceLabel, 'laptop-a');
    });

    test('photos are stored sealed, not as plain JPEG files', () async {
      await store.enrol(
        code: 'v001',
        deviceLabel: 'laptop-a',
        consentConfirmed: true,
      );
      await store.saveRegistration(
        'v001',
        deviceLabel: 'laptop-a',
        photos: _registration(),
      );
      final stored = await backing.list('v001/registration');
      expect(stored, hasLength(7));
      expect(stored.every((path) => path.endsWith('.jpg.sealed')), isTrue);
    });

    test('a session needs exactly three photos', () async {
      await store.enrol(
        code: 'v001',
        deviceLabel: 'laptop-a',
        consentConfirmed: true,
      );
      await expectLater(
        store.saveSession(
          'v001',
          deviceLabel: 'laptop-a',
          session: StudySession.a,
          photos: [_jpeg(1), _jpeg(2)],
          attempts: 5,
          rejected: 3,
        ),
        throwsA(isA<VolunteerStudyException>()),
      );
    });

    test(
      'export writes the calibration tool layout and a capture log',
      () async {
        await store.enrol(
          code: 'v001',
          deviceLabel: 'laptop-a',
          consentConfirmed: true,
        );
        await store.enrol(
          code: 'v002',
          deviceLabel: 'laptop-a',
          consentConfirmed: true,
        );
        await store.saveRegistration(
          'v001',
          deviceLabel: 'laptop-a',
          photos: _registration(),
        );
        for (final session in StudySession.values) {
          await store.saveSession(
            'v001',
            deviceLabel: 'laptop-a',
            session: session,
            photos: [_jpeg(10), _jpeg(11), _jpeg(12)],
            attempts: 4,
            rejected: 1,
          );
        }
        await store.saveSession(
          'v002',
          deviceLabel: 'laptop-a',
          session: StudySession.b,
          photos: [_jpeg(20), _jpeg(21), _jpeg(22)],
          attempts: 3,
          rejected: 0,
        );

        final temp = await Directory.systemTemp.createTemp('kslas_study_test');
        addTearDown(() => temp.delete(recursive: true));
        final result = await store.exportTo(
          Directory('${temp.path}${Platform.pathSeparator}export'),
          deviceLabel: 'laptop-a',
        );
        expect(result.volunteers, 2);
        expect(result.photos, 7 + 9 + 3);

        String path(List<String> parts) =>
            [result.folder.path, ...parts].join(Platform.pathSeparator);
        expect(
          await File(
            path(['v001', 'registration', 'front_face.jpg']),
          ).readAsBytes(),
          _jpeg(0),
        );
        final probes =
            Directory(path(['v001', 'probes', 'laptop-a']))
                .listSync()
                .map((entity) => entity.uri.pathSegments.last)
                .toList()
              ..sort();
        expect(probes, [
          'a1.jpg', 'a2.jpg', 'a3.jpg', //
          'b1.jpg', 'b2.jpg', 'b3.jpg', //
          'c1.jpg', 'c2.jpg', 'c3.jpg',
        ]);
        expect(
          File(path(['v002', 'probes', 'laptop-a', 'b2.jpg'])).existsSync(),
          isTrue,
        );
        expect(Directory(path(['v002', 'registration'])).existsSync(), isFalse);

        final log =
            jsonDecode(
                  await File(
                    path(['capture_log_laptop-a.json']),
                  ).readAsString(),
                )
                as Map<String, Object?>;
        final volunteers = log['volunteers']! as Map<String, Object?>;
        expect(volunteers.keys, containsAll(['v001', 'v002']));
        final v001 = volunteers['v001']! as Map<String, Object?>;
        expect(v001['consent_version'], VolunteerStudyConsent.version);
        expect(
          ((v001['sessions']! as Map)['laptop-a'] as Map)['a'],
          containsPair('rejected', 1),
        );
      },
    );

    test('withdrawal deletes everything for that volunteer', () async {
      await store.enrol(
        code: 'v001',
        deviceLabel: 'laptop-a',
        consentConfirmed: true,
      );
      await store.enrol(
        code: 'v002',
        deviceLabel: 'laptop-a',
        consentConfirmed: true,
      );
      await store.saveRegistration(
        'v001',
        deviceLabel: 'laptop-a',
        photos: _registration(),
      );
      await store.saveSession(
        'v001',
        deviceLabel: 'laptop-a',
        session: StudySession.a,
        photos: [_jpeg(1), _jpeg(2), _jpeg(3)],
        attempts: 3,
        rejected: 0,
      );
      await store.deleteVolunteer('v001');
      expect(await store.volunteerCodes(), ['v002']);
      expect(await store.volunteer('v001'), isNull);
      expect(await backing.list('v001/registration'), isEmpty);
      expect(await backing.list('v001/probes/laptop-a'), isEmpty);

      await store.deleteAll();
      expect(await store.volunteerCodes(), isEmpty);
    });
  });

  test('the paper consent form matches the app version', () {
    final form = File(
      'docs/identity/volunteer_study_consent.md',
    ).readAsStringSync();
    expect(form, contains(VolunteerStudyConsent.version));
    for (final section in VolunteerStudyConsent.sections) {
      expect(form, contains(section.heading), reason: section.heading);
    }
  });

  testWidgets('staff set the device label before adding volunteers', (
    tester,
  ) async {
    final store = VolunteerStudyStore(InMemoryProtectedLocalStore());
    await tester.pumpWidget(
      MaterialApp(home: VolunteerStudyView(store: store)),
    );
    await tester.pumpAndSettle();

    FilledButton addButton() => tester.widget<FilledButton>(
      find.ancestor(
        of: find.text('Add volunteer'),
        matching: find.byWidgetPredicate((widget) => widget is FilledButton),
      ),
    );
    expect(addButton().onPressed, isNull);

    await tester.enterText(find.byType(TextField), 'Laptop Dell 3520');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('This device is laptop-dell-3520.'), findsOneWidget);
    expect(addButton().onPressed, isNotNull);

    await tester.tap(find.text('Add volunteer'));
    await tester.pumpAndSettle();
    expect(find.text(VolunteerStudyConsent.staffConfirmation), findsOneWidget);
    // Add stays disabled until the code is valid and consent is confirmed.
    await tester.enterText(
      find.widgetWithText(TextField, 'Study code'),
      'v007',
    );
    await tester.pump();
    FilledButton dialogAdd() =>
        tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Add'));
    expect(dialogAdd().onPressed, isNull);
    await tester.ensureVisible(
      find.text(VolunteerStudyConsent.staffConfirmation),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text(VolunteerStudyConsent.staffConfirmation));
    await tester.pump();
    expect(dialogAdd().onPressed, isNotNull);
  });
}

import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:students_ui_demo/proctoring_demo/e1_exam_object_taxonomy.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('E1ExamObjectTaxonomy', () {
    test('maps detector aliases to stable canonical classes', () {
      expect(
        E1ExamObjectTaxonomy.canonicalizeDetectorLabel('cell phone'),
        'phone',
      );
      expect(
        E1ExamObjectTaxonomy.canonicalizeDetectorLabel('Mobile-Phone'),
        'phone',
      );
      expect(E1ExamObjectTaxonomy.canonicalizeDetectorLabel('tv'), 'display');
      expect(
        E1ExamObjectTaxonomy.canonicalizeDetectorLabel('smart watch'),
        'smartwatch',
      );
      expect(
        E1ExamObjectTaxonomy.canonicalizeDetectorLabel('earphones'),
        'earbud',
      );
    });

    test('does not let a detector invent contextual additional states', () {
      expect(
        E1ExamObjectTaxonomy.canonicalizeDetectorLabel('additional person'),
        'person',
      );
      expect(
        E1ExamObjectTaxonomy.canonicalizeDetectorLabel('partial_person'),
        'person',
      );
      expect(
        E1ExamObjectTaxonomy.canonicalizeDetectorLabel('additional laptop'),
        'laptop',
      );
      expect(
        E1ExamObjectTaxonomy.canonicalizeDetectorLabel('additional display'),
        'display',
      );
    });

    test('does not silently resolve ambiguous notebook label', () {
      expect(
        E1ExamObjectTaxonomy.canonicalizeDetectorLabel('notebook'),
        'notebook',
      );
      expect(E1ExamObjectTaxonomy.isKnownCanonicalClass('notebook'), isFalse);
    });

    test('keeps required detector classes separate from derived states', () {
      expect(E1ExamObjectTaxonomy.requiredDetectorClasses, contains('person'));
      expect(
        E1ExamObjectTaxonomy.requiredDetectorClasses,
        contains('smartwatch'),
      );
      expect(
        E1ExamObjectTaxonomy.requiredDetectorClasses,
        isNot(contains('additional_person')),
      );
      expect(
        E1ExamObjectTaxonomy.derivedContextStates,
        contains('additional_person'),
      );
      expect(
        E1ExamObjectTaxonomy.derivedContextStates,
        contains('additional_display'),
      );
    });

    test('language-neutral JSON taxonomy matches Dart contract', () async {
      final raw = await rootBundle.loadString(
        'assets/models/e1_object_taxonomy_v1.json',
      );
      final decoded = Map<String, Object?>.from(jsonDecode(raw) as Map);

      expect(decoded['taxonomy_id'], E1ExamObjectTaxonomy.taxonomyId);
      expect(decoded['taxonomy_version'], E1ExamObjectTaxonomy.taxonomyVersion);

      final required = (decoded['required_detector_classes'] as List)
          .map((value) => value.toString())
          .toSet();
      final derived = (decoded['derived_context_states'] as List)
          .map((value) => value.toString())
          .toSet();
      final aliases = Map<String, Object?>.from(
        decoded['canonical_aliases'] as Map,
      );

      expect(required, E1ExamObjectTaxonomy.requiredDetectorClasses);
      expect(derived, E1ExamObjectTaxonomy.derivedContextStates);
      for (final entry in aliases.entries) {
        expect(
          E1ExamObjectTaxonomy.canonicalize(entry.key),
          entry.value.toString(),
          reason: 'JSON alias ${entry.key} drifted from Dart taxonomy',
        );
      }
    });
  });
}

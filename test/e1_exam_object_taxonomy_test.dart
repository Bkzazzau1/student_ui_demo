import 'package:flutter_test/flutter_test.dart';
import 'package:students_ui_demo/proctoring_demo/e1_exam_object_taxonomy.dart';

void main() {
  group('E1ExamObjectTaxonomy', () {
    test('maps detector aliases to stable canonical classes', () {
      expect(E1ExamObjectTaxonomy.canonicalizeDetectorLabel('cell phone'), 'phone');
      expect(E1ExamObjectTaxonomy.canonicalizeDetectorLabel('Mobile-Phone'), 'phone');
      expect(E1ExamObjectTaxonomy.canonicalizeDetectorLabel('tv'), 'display');
      expect(E1ExamObjectTaxonomy.canonicalizeDetectorLabel('smart watch'), 'smartwatch');
      expect(E1ExamObjectTaxonomy.canonicalizeDetectorLabel('earphones'), 'earbud');
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
      expect(E1ExamObjectTaxonomy.canonicalizeDetectorLabel('notebook'), 'notebook');
      expect(E1ExamObjectTaxonomy.isKnownCanonicalClass('notebook'), isFalse);
    });

    test('keeps required detector classes separate from derived states', () {
      expect(E1ExamObjectTaxonomy.requiredDetectorClasses, contains('person'));
      expect(E1ExamObjectTaxonomy.requiredDetectorClasses, contains('smartwatch'));
      expect(E1ExamObjectTaxonomy.requiredDetectorClasses, isNot(contains('additional_person')));
      expect(E1ExamObjectTaxonomy.derivedContextStates, contains('additional_person'));
      expect(E1ExamObjectTaxonomy.derivedContextStates, contains('additional_display'));
    });
  });
}

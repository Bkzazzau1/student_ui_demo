import 'package:flutter_test/flutter_test.dart';
import 'package:students_ui_demo/proctoring_demo/e1_object_taxonomy.dart';

void main() {
  group('E1ObjectTaxonomyV1', () {
    test('maps current COCO classes to truthful base-detector coverage', () {
      final phone = E1ObjectTaxonomyV1.resolve('cell_phone');
      final laptop = E1ObjectTaxonomyV1.resolve('Laptop');
      final book = E1ObjectTaxonomyV1.resolve('book');
      final remote = E1ObjectTaxonomyV1.resolve('remote');
      final monitor = E1ObjectTaxonomyV1.resolve('monitor');
      final tvMonitor = E1ObjectTaxonomyV1.resolve('tv_monitor');

      expect(phone.canonicalObjectId, 'phone');
      expect(phone.coverage, E1ObjectCoverage.baseDetector);
      expect(laptop.canonicalObjectId, 'laptop');
      expect(laptop.coverage, E1ObjectCoverage.baseDetector);
      expect(book.coverage, E1ObjectCoverage.baseDetector);
      expect(remote.canonicalObjectId, 'remote');
      expect(remote.coverage, E1ObjectCoverage.baseDetector);
      expect(monitor.canonicalObjectId, 'television');
      expect(monitor.coverage, E1ObjectCoverage.baseDetector);
      expect(tvMonitor.canonicalObjectId, 'television');
      expect(tvMonitor.coverage, E1ObjectCoverage.baseDetector);
    });

    test('marks exam-specific small objects as specialist-required', () {
      for (final label in <String>[
        'smartwatch',
        'earbuds',
        'tablet',
        'calculator',
        'paper',
      ]) {
        final resolved = E1ObjectTaxonomyV1.resolve(label);
        expect(resolved.isKnown, isTrue, reason: label);
        expect(
          resolved.coverage,
          E1ObjectCoverage.specialistRequired,
          reason: label,
        );
        expect(resolved.requiresSpecialist, isTrue, reason: label);
      }
    });

    test(
      'taxonomy 1.1: wrist_device replaces smartwatch as the canonical wrist class',
      () {
        final smartwatchLabel = E1ObjectTaxonomyV1.resolve('smartwatch');
        final smartWatchLabel = E1ObjectTaxonomyV1.resolve('smart watch');

        expect(smartwatchLabel.canonicalObjectId, 'wrist_device');
        expect(smartwatchLabel.coverage, E1ObjectCoverage.specialistRequired);
        expect(smartWatchLabel.canonicalObjectId, 'wrist_device');
        expect(
          E1ObjectTaxonomyV1.specialistCanonicalIds,
          contains('wrist_device'),
        );
        expect(
          E1ObjectTaxonomyV1.specialistCanonicalIds,
          isNot(contains('smartwatch')),
        );
      },
    );

    test('does not promote ambiguous clock or unknown labels', () {
      final clock = E1ObjectTaxonomyV1.resolve('clock');
      final unknown = E1ObjectTaxonomyV1.resolve('mystery device');

      expect(clock.canonicalObjectId, 'unknown');
      expect(clock.coverage, E1ObjectCoverage.unknown);
      expect(unknown.canonicalObjectId, 'unknown');
      expect(unknown.coverage, E1ObjectCoverage.unknown);
    });
  });
}

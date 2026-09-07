import 'package:flutter_test/flutter_test.dart';
import 'package:students_ui_demo/proctoring_demo/object_review_event_mapper.dart';

void main() {
  const mapper = ObjectReviewEventMapper();

  test('maps phone labels to phone event with canonical metadata', () {
    final decisions = mapper.mapLabels(
      const <String>['movement checked', 'phone'],
      target: 'desk surface',
    );

    expect(decisions, hasLength(1));
    expect(decisions.single.eventType, 'yolo_phone_detected');
    expect(decisions.single.severity, 'warning');
    expect(decisions.single.metadata['scan_target'], 'desk surface');
    expect(decisions.single.metadata['canonical_object_ids'], <String>['phone']);
    expect(decisions.single.metadata['object_coverage'], <String>['base_detector']);
    expect(decisions.single.metadata['specialist_required'], isFalse);
  });

  test('maps laptop and monitor labels to extra screen event with mixed coverage', () {
    final decisions = mapper.mapLabels(const <String>['Laptop', 'tv_monitor']);
    final screen = decisions.firstWhere(
      (decision) => decision.eventType == 'yolo_extra_screen_detected',
    );

    expect(screen.metadata['canonical_object_ids'], containsAll(<String>['laptop', 'monitor']));
    expect(screen.metadata['object_coverage'], containsAll(<String>['base_detector', 'specialist_required']));
    expect(screen.metadata['specialist_required'], isTrue);
  });

  test('maps paper and calculator labels to separate specialist-required events', () {
    final decisions = mapper.mapLabels(const <String>['paper', 'calculator']);
    final eventTypes = decisions.map((decision) => decision.eventType).toSet();

    expect(eventTypes, contains('yolo_book_or_paper_detected'));
    expect(eventTypes, contains('yolo_calculator_detected'));
    expect(decisions.every((decision) => decision.metadata['specialist_required'] == true), isTrue);
  });

  test('maps smartwatch and earbud to dedicated E1 events', () {
    final decisions = mapper.mapLabels(const <String>['smart watch', 'earbuds']);
    final eventTypes = decisions.map((decision) => decision.eventType).toSet();

    expect(eventTypes, contains('e1_smartwatch_detected'));
    expect(eventTypes, contains('e1_earbud_detected'));
    expect(decisions.every((decision) => decision.metadata['specialist_required'] == true), isTrue);
  });

  test('does not confuse a remote with phone evidence', () {
    final decisions = mapper.mapLabels(const <String>['remote']);

    expect(
      decisions.where((decision) => decision.eventType == 'yolo_phone_detected'),
      isEmpty,
    );
  });

  test('ignores unknown and background-only labels', () {
    final decisions = mapper.mapLabels(
      const <String>['background', 'none', '', 'mystery device'],
    );

    expect(decisions, isEmpty);
  });
}

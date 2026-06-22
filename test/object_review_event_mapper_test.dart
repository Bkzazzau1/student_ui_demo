import 'package:flutter_test/flutter_test.dart';
import 'package:students_ui_demo/proctoring_demo/object_review_event_mapper.dart';

void main() {
  const mapper = ObjectReviewEventMapper();

  test('maps phone labels to phone event', () {
    final decisions = mapper.mapLabels(
      const <String>['movement checked', 'phone'],
      target: 'desk surface',
    );

    expect(decisions, hasLength(1));
    expect(decisions.single.eventType, 'yolo_phone_detected');
    expect(decisions.single.severity, 'warning');
    expect(decisions.single.metadata['scan_target'], 'desk surface');
  });

  test('maps laptop and monitor labels to extra screen event', () {
    final decisions = mapper.mapLabels(const <String>['Laptop', 'tv_monitor']);

    expect(
      decisions.map((decision) => decision.eventType),
      contains('yolo_extra_screen_detected'),
    );
  });

  test('maps paper and calculator labels to separate events', () {
    final decisions = mapper.mapLabels(const <String>['paper', 'calculator']);
    final eventTypes = decisions.map((decision) => decision.eventType).toSet();

    expect(eventTypes, contains('yolo_book_or_paper_detected'));
    expect(eventTypes, contains('yolo_calculator_detected'));
  });

  test('ignores background-only labels', () {
    final decisions = mapper.mapLabels(const <String>['background', 'none', '']);

    expect(decisions, isEmpty);
  });
}

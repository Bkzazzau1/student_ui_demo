import 'package:flutter_test/flutter_test.dart';
import 'package:students_ui_demo/proctoring_demo/live_event_cooldown_gate.dart';

void main() {
  test('accepts first event and blocks duplicate during cooldown', () {
    var now = DateTime(2026, 6, 23, 9, 0);
    final gate = LiveEventCooldownGate(clock: () => now);

    expect(gate.shouldAccept('event_a'), isTrue);
    expect(gate.shouldAccept('event_a'), isFalse);

    now = now.add(const Duration(seconds: 14));
    expect(gate.shouldAccept('event_a'), isFalse);

    now = now.add(const Duration(seconds: 1));
    expect(gate.shouldAccept('event_a'), isTrue);
  });

  test('tracks different event types independently', () {
    final now = DateTime(2026, 6, 23, 9, 0);
    final gate = LiveEventCooldownGate(clock: () => now);

    expect(gate.shouldAccept('event_a'), isTrue);
    expect(gate.shouldAccept('event_b'), isTrue);
    expect(gate.shouldAccept('event_a'), isFalse);
  });

  test('reset clears one event or all events', () {
    final now = DateTime(2026, 6, 23, 9, 0);
    final gate = LiveEventCooldownGate(clock: () => now);

    expect(gate.shouldAccept('event_a'), isTrue);
    expect(gate.shouldAccept('event_b'), isTrue);

    gate.reset('event_a');
    expect(gate.shouldAccept('event_a'), isTrue);
    expect(gate.shouldAccept('event_b'), isFalse);

    gate.reset();
    expect(gate.shouldAccept('event_b'), isTrue);
  });

  test('reports current tracked state', () {
    final gate = LiveEventCooldownGate(clock: () => DateTime(2026, 6, 23, 9, 0));
    gate.shouldAccept('event_a');

    final state = gate.currentState();

    expect(state['cooldown_ms'], 15000);
    expect(state['tracked_event_types'], contains('event_a'));
  });
}

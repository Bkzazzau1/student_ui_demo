import 'package:flutter_test/flutter_test.dart';
import 'package:students_ui_demo/proctoring_demo/edge_ai_runtime_preflight_service.dart';

void main() {
  test('preflight is ready only when every required component is ready', () {
    final result = EdgeAiRuntimePreflightResult(
      checkedAt: DateTime.utc(2026, 8, 20),
      components: const [
        EdgeAiComponentStatus(name: 'Models', ready: true, detail: 'valid'),
        EdgeAiComponentStatus(name: 'Rust', ready: true, detail: 'loaded'),
      ],
    );

    expect(result.ready, isTrue);
    expect(result.blockingReasons, isEmpty);
  });

  test('preflight reports every failed component as a blocking reason', () {
    final result = EdgeAiRuntimePreflightResult(
      checkedAt: DateTime.utc(2026, 8, 20),
      components: const [
        EdgeAiComponentStatus(
          name: 'Models',
          ready: false,
          detail: 'checksum mismatch',
        ),
        EdgeAiComponentStatus(name: 'Rust', ready: true, detail: 'loaded'),
        EdgeAiComponentStatus(
          name: 'Python',
          ready: false,
          detail: 'health check failed',
        ),
      ],
    );

    expect(result.ready, isFalse);
    expect(result.blockingReasons, [
      'Models: checksum mismatch',
      'Python: health check failed',
    ]);
  });

  test('empty preflight never permits an exam to start', () {
    final result = EdgeAiRuntimePreflightResult(
      checkedAt: DateTime.utc(2026, 8, 20),
      components: const [],
    );

    expect(result.ready, isFalse);
  });
}

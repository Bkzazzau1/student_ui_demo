import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:students_ui_demo/proctoring_demo/e1_small_object_specialist.dart';
import 'package:students_ui_demo/proctoring_demo/e1_small_object_specialist_runtime.dart';
import 'package:students_ui_demo/proctoring_demo/e1_specialist_frame.dart';

E1SpecialistFrameInput _frame({
  int? sourceFrameId = 7,
  int captureTimestampNs = 700,
  int width = 2,
  int height = 2,
}) {
  return E1SpecialistFrameInput(
    format: 'rgb888',
    width: width,
    height: height,
    sourceFrameId: sourceFrameId,
    captureTimestampNs: captureTimestampNs,
    planes: <E1SpecialistFramePlane>[
      E1SpecialistFramePlane(
        bytes: Uint8List.fromList(<int>[
          0,
          0,
          0,
          255,
          255,
          255,
          20,
          20,
          20,
          40,
          40,
          40,
        ]),
        bytesPerRow: width * 3,
        bytesPerPixel: 3,
        width: width,
        height: height,
      ),
    ],
  );
}

const _request = E1SmallObjectSpecialistRequest(
  sessionId: 'attempt-001',
  sourceFrameId: 7,
  captureTimestampNs: 700,
  imageWidth: 2,
  imageHeight: 2,
  targets: <E1SmallObjectTarget>{E1SmallObjectTarget.calculator},
  reason: 'desk_anchor_available_for_small_object_specialist',
  roiHint: E1SpecialistRoiHint(strategy: 'desk_relative_small_object'),
);

void main() {
  const guard = E1SpecialistRuntimeGuard();

  test('accepts a real local frame only when provenance matches request', () {
    final frame = _frame();

    expect(frame.isValid, isTrue);
    expect(frame.matchesRequest(_request), isTrue);
    expect(guard.canInfer(request: _request, frame: frame), isTrue);
    expect(frame.toPlatformMap()['format'], 'rgb888');
  });

  test('blocks mismatched frame id, timestamp or dimensions', () {
    expect(
      guard.canInfer(request: _request, frame: _frame(sourceFrameId: 8)),
      isFalse,
    );
    expect(
      guard.canInfer(request: _request, frame: _frame(captureTimestampNs: 701)),
      isFalse,
    );
    expect(
      guard.canInfer(request: _request, frame: _frame(width: 3)),
      isFalse,
    );
  });

  test('unavailable runtime produces no specialist evidence', () async {
    const runtime = UnavailableE1SmallObjectSpecialistRuntime();

    final output = await runtime.infer(request: _request, frame: _frame());

    expect(output, isEmpty);
  });

  test('runtime guard removes invalid specialist observations', () {
    const valid = E1SmallObjectSpecialistObservation(
      canonicalObjectId: 'calculator',
      confidence: 0.8,
      boundingBox: <String, double>{
        'x': 0.2,
        'y': 0.2,
        'width': 0.2,
        'height': 0.2,
      },
      modelId: 'local-specialist',
      modelVersion: '1',
      sourceFrameId: 7,
      captureTimestampNs: 700,
      inferenceTimestampNs: 710,
    );
    const invalid = E1SmallObjectSpecialistObservation(
      canonicalObjectId: 'phone',
      confidence: 0.8,
      boundingBox: <String, double>{
        'x': 0.2,
        'y': 0.2,
        'width': 0.2,
        'height': 0.2,
      },
      modelId: 'local-specialist',
      modelVersion: '1',
      sourceFrameId: 7,
      captureTimestampNs: 700,
      inferenceTimestampNs: 710,
    );

    final retained = guard.retainValidObservations(
      const <E1SmallObjectSpecialistObservation>[valid, invalid],
    );

    expect(retained, hasLength(1));
    expect(retained.single.canonicalObjectId, 'calculator');
  });
}

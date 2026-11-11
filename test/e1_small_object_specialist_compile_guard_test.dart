import 'package:flutter_test/flutter_test.dart';
import 'package:students_ui_demo/proctoring_demo/e1_small_object_specialist.dart';

class _NoopLocalSpecialist implements E1SmallObjectSpecialist {
  @override
  Future<List<E1SmallObjectSpecialistObservation>> infer(
    E1SmallObjectSpecialistRequest request,
  ) async {
    // A boundary implementation that has no trained model must return no
    // evidence rather than fabricating a detection.
    return const <E1SmallObjectSpecialistObservation>[];
  }
}

void main() {
  test('small-object specialist interface compiles without fabricated evidence', () async {
    final specialist = _NoopLocalSpecialist();
    const request = E1SmallObjectSpecialistRequest(
      sessionId: 'attempt-001',
      sourceFrameId: 1,
      captureTimestampNs: 10,
      imageWidth: 640,
      imageHeight: 480,
      targets: <E1SmallObjectTarget>{E1SmallObjectTarget.wristDevice},
      reason: 'compile_guard',
      roiHint: E1SpecialistRoiHint(
        strategy: 'person_arm_watch',
        anchorCanonicalObjectId: 'person',
        boundingBox: <String, double>{
          'x': 0.2,
          'y': 0.3,
          'width': 0.5,
          'height': 0.6,
        },
      ),
    );

    expect(request.isValid, isTrue);
    expect(await specialist.infer(request), isEmpty);
  });
}

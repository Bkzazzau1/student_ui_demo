import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:students_ui_demo/proctoring_demo/e1_small_object_specialist.dart';
import 'package:students_ui_demo/proctoring_demo/e1_small_object_specialist_manifest.dart';
import 'package:students_ui_demo/proctoring_demo/e1_small_object_specialist_runtime_bridge.dart';
import 'package:students_ui_demo/proctoring_demo/e1_specialist_frame.dart';

const _channel = MethodChannel('kslas.e1_small_object_specialist_runtime');

E1SmallObjectSpecialistManifest _installedManifest() {
  return const E1SmallObjectSpecialistManifest(
    schemaVersion: '1.0',
    installed: true,
    requiredCanonicalClasses: <String>{
      'smartwatch',
      'earbud',
      'tablet',
      'paper_note',
      'calculator',
    },
    modelId: 'e1-small-object-specialist',
    modelVersion: '1.0.0',
    modelPath: 'assets/models/e1_small_object_specialist/model.int8.onnx',
    classNames: <String>[
      'smartwatch',
      'earbud',
      'tablet',
      'paper_note',
      'calculator',
    ],
  );
}

E1SmallObjectSpecialistRequest _request({
  Set<E1SmallObjectTarget> targets = const <E1SmallObjectTarget>{
    E1SmallObjectTarget.smartwatch,
  },
}) {
  return E1SmallObjectSpecialistRequest(
    sessionId: 'attempt-1',
    sourceFrameId: 42,
    captureTimestampNs: 1000,
    imageWidth: 2,
    imageHeight: 2,
    targets: targets,
    reason: 'test_specialist_request',
    roiHint: const E1SpecialistRoiHint(
      strategy: 'person_relative_wearable',
      anchorCanonicalObjectId: 'person',
    ),
  );
}

E1SpecialistFrameInput _frame({int sourceFrameId = 42}) {
  return E1SpecialistFrameInput(
    format: 'rgb888',
    width: 2,
    height: 2,
    sourceFrameId: sourceFrameId,
    captureTimestampNs: 1000,
    planes: <E1SpecialistFramePlane>[
      E1SpecialistFramePlane(
        bytes: Uint8List.fromList(<int>[
          0,
          0,
          0,
          0,
          0,
          0,
          0,
          0,
          0,
          0,
          0,
          0,
        ]),
        bytesPerRow: 6,
        bytesPerPixel: 3,
        width: 2,
        height: 2,
      ),
    ],
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
  });

  test('uninstalled manifest never calls native inference and emits nothing', () async {
    var nativeCalls = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
          nativeCalls++;
          return true;
        });

    final runtime = E1SmallObjectSpecialistRuntimeBridge(
      manifestLoader: () async => const E1SmallObjectSpecialistManifest(
        schemaVersion: '1.0',
        installed: false,
        requiredCanonicalClasses: <String>{
          'smartwatch',
          'earbud',
          'tablet',
          'paper_note',
          'calculator',
        },
      ),
    );

    final observations = await runtime.infer(
      request: _request(),
      frame: _frame(),
    );

    expect(observations, isEmpty);
    expect(runtime.available, isFalse);
    expect(nativeCalls, 0);
  });

  test('native class id maps through specialist manifest, not native label', () async {
    final methods = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
          methods.add(call.method);
          if (call.method == 'initialize') return true;
          if (call.method == 'runFrame') {
            return <String, Object?>{
              'available': true,
              'outputs': <String, Object?>{
                'objects': <Map<String, Object?>>[
                  <String, Object?>{
                    // Deliberately wrong/base-model label. The specialist bridge
                    // must use class_id + manifest class_names instead.
                    'label': 'person',
                    'class_id': 0,
                    'confidence': 0.91,
                    'box': <String, Object?>{
                      'x1': 0.1,
                      'y1': 0.2,
                      'x2': 0.3,
                      'y2': 0.4,
                    },
                  },
                ],
              },
            };
          }
          return null;
        });

    final runtime = E1SmallObjectSpecialistRuntimeBridge(
      manifestLoader: () async => _installedManifest(),
    );
    final observations = await runtime.infer(
      request: _request(),
      frame: _frame(),
    );

    expect(methods, equals(<String>['initialize', 'runFrame']));
    expect(observations, hasLength(1));
    final observation = observations.single;
    expect(observation.canonicalObjectId, 'smartwatch');
    expect(observation.modelId, 'e1-small-object-specialist');
    expect(observation.modelVersion, '1.0.0');
    expect(observation.sourceFrameId, 42);
    expect(observation.captureTimestampNs, 1000);
    expect(observation.inferenceTimestampNs, greaterThanOrEqualTo(1000));
    expect(observation.boundingBox['x'], closeTo(0.1, 0.0001));
    expect(observation.boundingBox['width'], closeTo(0.2, 0.0001));
  });

  test('unrequested specialist class is dropped', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
          if (call.method == 'initialize') return true;
          if (call.method == 'runFrame') {
            return <String, Object?>{
              'available': true,
              'outputs': <String, Object?>{
                'objects': <Map<String, Object?>>[
                  <String, Object?>{
                    'class_id': 0,
                    'confidence': 0.95,
                    'box': <String, Object?>{
                      'x': 0.1,
                      'y': 0.1,
                      'width': 0.2,
                      'height': 0.2,
                    },
                  },
                ],
              },
            };
          }
          return null;
        });

    final runtime = E1SmallObjectSpecialistRuntimeBridge(
      manifestLoader: () async => _installedManifest(),
    );
    final observations = await runtime.infer(
      request: _request(
        targets: const <E1SmallObjectTarget>{E1SmallObjectTarget.earbud},
      ),
      frame: _frame(),
    );

    expect(observations, isEmpty);
  });

  test('mismatched frame provenance blocks native calls', () async {
    var nativeCalls = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
          nativeCalls++;
          return true;
        });

    final runtime = E1SmallObjectSpecialistRuntimeBridge(
      manifestLoader: () async => _installedManifest(),
    );
    final observations = await runtime.infer(
      request: _request(),
      frame: _frame(sourceFrameId: 99),
    );

    expect(observations, isEmpty);
    expect(nativeCalls, 0);
  });
}

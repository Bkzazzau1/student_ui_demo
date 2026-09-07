import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:students_ui_demo/proctoring_demo/e1_small_object_specialist.dart';
import 'package:students_ui_demo/proctoring_demo/e1_small_object_specialist_manifest.dart';
import 'package:students_ui_demo/proctoring_demo/e1_small_object_specialist_runtime_bridge.dart';
import 'package:students_ui_demo/proctoring_demo/e1_specialist_frame.dart';

const _channel = MethodChannel('kslas.e1_small_object_specialist_runtime');

const _roi = <String, double>{
  'x': 0.25,
  'y': 0.25,
  'width': 0.5,
  'height': 0.5,
};

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
  Map<String, double>? roi = _roi,
}) {
  return E1SmallObjectSpecialistRequest(
    sessionId: 'attempt-1',
    sourceFrameId: 42,
    captureTimestampNs: 1000,
    imageWidth: 100,
    imageHeight: 100,
    targets: targets,
    reason: 'test_specialist_request',
    roiHint: E1SpecialistRoiHint(
      strategy: 'person_arm_watch',
      anchorCanonicalObjectId: 'person',
      boundingBox: roi,
    ),
  );
}

E1SpecialistFrameInput _frame({int sourceFrameId = 42}) {
  return E1SpecialistFrameInput(
    format: 'rgb888',
    width: 100,
    height: 100,
    sourceFrameId: sourceFrameId,
    captureTimestampNs: 1000,
    planes: <E1SpecialistFramePlane>[
      E1SpecialistFramePlane(
        bytes: Uint8List(100 * 100 * 3),
        bytesPerRow: 300,
        bytesPerPixel: 3,
        width: 100,
        height: 100,
      ),
    ],
  );
}

Map<String, Object?> _nativeOutputs({
  Map<String, double> sourceRoi = _roi,
  List<Map<String, Object?>> objects = const <Map<String, Object?>>[],
}) {
  return <String, Object?>{
    'output_coordinate_space': 'normalized_roi',
    'source_roi': sourceRoi,
    'objects': objects,
  };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
  });

  test(
    'uninstalled manifest never calls native inference and emits nothing',
    () async {
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
    },
  );

  test(
    'native crop-space box remaps from applied ROI to full-frame coordinates',
    () async {
      final methods = <String>[];
      Map<Object?, Object?>? runFrameArguments;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_channel, (call) async {
            methods.add(call.method);
            if (call.method == 'initialize') return true;
            if (call.method == 'runFrame') {
              runFrameArguments = Map<Object?, Object?>.from(
                call.arguments as Map,
              );
              return <String, Object?>{
                'available': true,
                'outputs': _nativeOutputs(
                  objects: <Map<String, Object?>>[
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
                ),
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

      // Applied crop is [0.25, 0.25, 0.5, 0.5]. Local box
      // [0.1, 0.2, 0.2, 0.2] therefore maps back to
      // [0.30, 0.35, 0.10, 0.10] in the original frame.
      expect(observation.boundingBox['x'], closeTo(0.30, 0.0001));
      expect(observation.boundingBox['y'], closeTo(0.35, 0.0001));
      expect(observation.boundingBox['width'], closeTo(0.10, 0.0001));
      expect(observation.boundingBox['height'], closeTo(0.10, 0.0001));

      final roiHint = Map<Object?, Object?>.from(
        runFrameArguments!['roi_hint'] as Map,
      );
      expect(
        Map<Object?, Object?>.from(roiHint['bounding_box'] as Map),
        equals(<Object?, Object?>{
          'x': 0.25,
          'y': 0.25,
          'width': 0.5,
          'height': 0.5,
        }),
      );
    },
  );

  test('native ROI outside one-pixel tolerance is rejected', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
          if (call.method == 'initialize') return true;
          if (call.method == 'runFrame') {
            return <String, Object?>{
              'available': true,
              'outputs': _nativeOutputs(
                sourceRoi: const <String, double>{
                  'x': 0.10,
                  'y': 0.25,
                  'width': 0.5,
                  'height': 0.5,
                },
                objects: <Map<String, Object?>>[
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
              ),
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

    expect(observations, isEmpty);
  });

  test('missing native ROI coordinate metadata is rejected', () async {
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
      request: _request(),
      frame: _frame(),
    );

    expect(observations, isEmpty);
  });

  test('unrequested specialist class is dropped', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
          if (call.method == 'initialize') return true;
          if (call.method == 'runFrame') {
            return <String, Object?>{
              'available': true,
              'outputs': _nativeOutputs(
                objects: <Map<String, Object?>>[
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
              ),
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

  test(
    'missing ROI blocks native calls rather than falling back to full frame',
    () async {
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
        request: _request(roi: null),
        frame: _frame(),
      );

      expect(observations, isEmpty);
      expect(nativeCalls, 0);
    },
  );
}

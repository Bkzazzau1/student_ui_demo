import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:students_ui_demo/proctoring_demo/optimized_vision_runtime_bridge.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('kslas.test.optimized_vision_runtime');

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('validated manifest owns class labels returned by native runtime', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'initialize') return true;
          if (call.method == 'runFrame') {
            return <String, Object?>{
              'available': true,
              'backend': 'onnxRuntimeCpu',
              'precision': 'int8',
              'inference_ms': 4.2,
              'outputs': <String, Object?>{
                'objects': <Map<String, Object?>>[
                  <String, Object?>{
                    'class_id': 1,
                    'label': 'phone',
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

    final bridge = OptimizedVisionRuntimeBridge(channel: channel);
    final result = await bridge.runRgbFrame(
      rgbBytes: Uint8List.fromList(const <int>[0, 0, 0]),
      width: 1,
      height: 1,
      tasks: const <String>['person_detector'],
      sourceFrameId: 7,
      captureTimestampNs: 100,
    );

    expect(result, isNotNull);
    expect(result!.available, isTrue);
    final objects = result.outputs['objects'] as List;
    final object = Map<String, Object?>.from(objects.single as Map);

    // COCO class 1 is bicycle. A stale/native hard-coded label must not be
    // allowed to redefine the manifest's class semantics.
    expect(object['label'], 'bicycle');
    expect(object['native_label'], 'phone');
    expect(object['label_source'], 'manifest_class_names');
    expect(result.outputs['model_family'], 'yolo');
    expect(result.modelId, 'e1-yolo-exam-review');
    expect(result.modelVersion, 'development-baseline-1');
    expect(result.sourceFrameId, 7);
    expect(result.captureTimestampNs, 100);
    expect(result.hasModelEventProvenance, isTrue);
  });
}

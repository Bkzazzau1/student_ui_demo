import 'package:flutter_test/flutter_test.dart';
import 'package:students_ui_demo/proctoring_demo/e1_small_object_specialist_manifest.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('bundled specialist slot is valid but explicitly not installed', () async {
    final manifest = await E1SmallObjectSpecialistManifest.load();

    expect(manifest, isNotNull);
    expect(manifest!.isValid, isTrue);
    expect(manifest.installed, isFalse);
    expect(manifest.runtimeAvailable, isFalse);
    expect(
      manifest.requiredCanonicalClasses,
      equals(<String>{
        'smartwatch',
        'earbud',
        'tablet',
        'paper_note',
        'calculator',
      }),
    );
    expect(manifest.toNativePolicy(), isEmpty);
  });

  test('installed specialist requires real model provenance and classes', () {
    final invalid = E1SmallObjectSpecialistManifest.fromJson(
      <String, Object?>{
        'manifest_schema_version': '1.0',
        'installed': true,
        'required_canonical_classes': <String>[
          'smartwatch',
          'earbud',
          'tablet',
          'paper_note',
          'calculator',
        ],
      },
    );

    expect(invalid.isValid, isFalse);
    expect(invalid.runtimeAvailable, isFalse);
  });

  test('complete installed manifest produces an explicit native policy', () {
    final manifest = E1SmallObjectSpecialistManifest.fromJson(
      <String, Object?>{
        'manifest_schema_version': '1.0',
        'installed': true,
        'model_id': 'e1-small-object-specialist',
        'model_version': '1.0.0',
        'model_path':
            'assets/models/e1_small_object_specialist/model.int8.onnx',
        'precision': 'int8',
        'backend': 'onnxRuntimeDirectML',
        'input_width': 512,
        'input_height': 512,
        'confidence_threshold': 0.55,
        'iou_threshold': 0.4,
        'required_canonical_classes': <String>[
          'smartwatch',
          'earbud',
          'tablet',
          'paper_note',
          'calculator',
        ],
        'class_names': <String>[
          'smartwatch',
          'earbud',
          'tablet',
          'paper_note',
          'calculator',
        ],
      },
    );

    expect(manifest.isValid, isTrue);
    expect(manifest.runtimeAvailable, isTrue);
    expect(
      manifest.toNativePolicy(),
      containsPair('model_id', 'e1-small-object-specialist'),
    );
    expect(manifest.toNativePolicy(), containsPair('max_input_width', 512));
    expect(
      manifest.toNativePolicy()['class_names'],
      equals(<String>[
        'smartwatch',
        'earbud',
        'tablet',
        'paper_note',
        'calculator',
      ]),
    );
  });
}

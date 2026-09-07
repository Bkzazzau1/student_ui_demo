import 'package:flutter_test/flutter_test.dart';
import 'package:students_ui_demo/proctoring_demo/optimized_vision_runtime_policy.dart';
import 'package:students_ui_demo/proctoring_demo/yolo_exam_review_manifest.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('YoloExamReviewManifest', () {
    test('loads real manifest and reports partial development coverage', () async {
      final manifest = await YoloExamReviewManifest.load();
      expect(manifest, isNotNull);
      final value = manifest!;

      expect(value.modelId, 'e1-yolo-exam-review');
      expect(value.modelVersion, 'development-baseline-1');
      expect(value.taxonomyId, 'e1-exam-object-taxonomy');
      expect(value.taxonomyVersion, '1.0.0');
      expect(value.coverageStatus, 'partial_development_baseline');
      expect(value.finalExamSpecificModel, isFalse);
      expect(value.calibrationStatus, 'uncalibrated');
      expect(value.hasCompleteRequiredClassCoverage, isFalse);
      expect(value.isFinalExamSpecificCoverageCandidate, isFalse);

      expect(value.supportedCanonicalClasses, containsAll(<String>[
        'person',
        'phone',
        'book',
        'laptop',
        'display',
      ]));
      expect(value.missingRequiredCanonicalClasses, containsAll(<String>[
        'tablet',
        'smartwatch',
        'earbud',
        'headphone',
        'paper',
        'note',
        'calculator',
      ]));
    });

    test('passes taxonomy coverage metadata into runtime policy', () {
      final manifest = YoloExamReviewManifest.fromJson(<String, Object?>{
        'manifest_schema_version': '1.0',
        'model_id': 'e1-test',
        'model_version': '1.0.0',
        'model_name': 'test detector',
        'model_family': 'yolo',
        'model_path_int8': 'model.int8.onnx',
        'model_path_fp16': 'model.fp16.onnx',
        'model_path_fp32': 'model.fp32.onnx',
        'input_width': 416,
        'input_height': 416,
        'input_channels': 3,
        'output_layout': 'channels_first_yolov8',
        'confidence_threshold': 0.45,
        'iou_threshold': 0.45,
        'target_fps': 1,
        'class_names': <String>['person'],
        'taxonomy_id': 'e1-exam-object-taxonomy',
        'taxonomy_version': '1.0.0',
        'coverage_status': 'complete_candidate',
        'final_exam_specific_model': true,
        'calibration_status': 'uncalibrated',
        'required_canonical_classes': <String>['person'],
        'supported_canonical_classes': <String>['person'],
        'missing_required_canonical_classes': <String>[],
        'canonical_class_aliases': <String, String>{'person': 'person'},
      });

      expect(manifest.hasCompleteRequiredClassCoverage, isTrue);
      expect(manifest.isFinalExamSpecificCoverageCandidate, isTrue);

      final policy = manifest.toPolicyJson(
        const OptimizedVisionRuntimePolicy(
          backend: VisionRuntimeBackend.onnxRuntimeCpu,
          precision: VisionModelPrecision.int8,
          targetUtilization: 0.15,
          maxInputWidth: 416,
          maxInputHeight: 416,
          targetFps: 1,
          batchSize: 1,
        ),
      );
      expect(policy['taxonomy_id'], 'e1-exam-object-taxonomy');
      expect(policy['has_complete_required_class_coverage'], isTrue);
      expect(policy['final_exam_specific_model'], isTrue);
    });
  });
}

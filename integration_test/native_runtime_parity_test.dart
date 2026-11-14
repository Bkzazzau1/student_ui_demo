// Runs the app's native face, identity, object and storage runtimes on a real
// device or simulator and compares them with the Python/ONNX Runtime
// reference in fixtures/native_parity_fixture.dart.
//
// This is how the iOS (Swift) runtimes are checked in CI without a Mac:
// .github/workflows/ios.yml runs it on an iPad simulator. It also runs on
// Windows and Android:
//
//   flutter test integration_test/native_runtime_parity_test.dart -d <device>
//
// Regenerate the fixture with ai_runtime/tools/build_native_parity_fixture.py.

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:students_ui_demo/exam_demo/exam_lockdown_service.dart';
import 'package:students_ui_demo/face_demo/face_alignment.dart';
import 'package:students_ui_demo/face_demo/face_embedding_pipeline.dart';
import 'package:students_ui_demo/face_demo/native_face_embedding_runtime.dart';
import 'package:students_ui_demo/face_demo/protected_local_store.dart';
import 'package:students_ui_demo/proctoring_demo/native_face_landmarker_runtime.dart';
import 'package:students_ui_demo/proctoring_demo/optimized_vision_runtime_bridge.dart';
import 'package:students_ui_demo/rust/api/official_face_id.dart';
import 'package:students_ui_demo/rust/brain_core_runtime.dart';

import 'fixtures/native_parity_fixture.dart';

const MethodChannel _landmarkerChannel = MethodChannel('kslas.face_landmarker');
const MethodChannel _visionChannel = MethodChannel(
  'kslas.optimized_vision_runtime',
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final image = img.decodePng(
    base64Decode(NativeParityFixture.imagePngBase64),
  )!;
  final width = image.width;
  final height = image.height;
  final rgb = image.getBytes(order: img.ChannelOrder.rgb);
  final reference = <math.Point<double>>[
    for (var i = 0; i < 5; i++)
      math.Point<double>(
        NativeParityFixture.fivePointsXY[i * 2],
        NativeParityFixture.fivePointsXY[i * 2 + 1],
      ),
  ];
  final interOcular = reference[0].distanceTo(reference[1]);

  testWidgets('Rust core loads through Flutter Rust Bridge', (tester) async {
    await BrainCoreRuntime.ensureInitialized();
    final key = sampleSchoolPublicKeyHex(signingSeedHex: '07' * 32);
    expect(key, hasLength(64));
  });

  testWidgets('SFace embedding matches the reference', (tester) async {
    final runtime = NativeFaceEmbeddingRuntime();
    expect(await runtime.initialize(), isTrue);
    final health = await runtime.health();
    expect(health['ready'], isTrue, reason: '${health['error']}');
    final sample = await runtime.embedAlignedRgb(
      base64Decode(NativeParityFixture.alignedRgbBase64),
    );
    expect(sample, isNotNull);
    final cosine = _dot(
      sample!.embedding,
      NativeParityFixture.alignedEmbedding,
    );
    debugPrint('PARITY sface_cosine=$cosine');
    expect(cosine, greaterThan(0.9999));
  });

  testWidgets('face landmarks agree with the reference', (tester) async {
    final landmarker = NativeFaceLandmarkerRuntime();
    expect(await landmarker.initialize(), isTrue);
    final payload = await landmarker.analyseRgbRaw(
      rgbBytes: rgb,
      width: width,
      height: height,
    );
    expect(payload, isNotNull, reason: 'no face found in the test image');
    final five = _fivePoints(payload!, width, height);
    expect(five, isNotNull);
    var worst = 0.0;
    for (var i = 0; i < 5; i++) {
      final error = five![i].distanceTo(reference[i]);
      worst = math.max(worst, error);
      debugPrint('PARITY landmark_$i error_px=${error.toStringAsFixed(2)}');
    }
    debugPrint(
      'PARITY landmark_worst_over_iod=${(worst / interOcular).toStringAsFixed(4)}',
    );
    // MediaPipe (Android, iOS) and the Windows YuNet + mesh crop the face
    // differently, so points differ slightly. A wrong channel order,
    // rotation or mirror moves them by about the eye distance.
    expect(worst / interOcular, lessThan(0.15));
  });

  testWidgets(
    'camera frames (mirrored BGRA, rotated, NV12) give the same landmarks',
    (tester) async {
      if (Platform.isWindows) {
        markTestSkipped('Windows does not stream camera frames.');
        return;
      }
      final landmarker = NativeFaceLandmarkerRuntime();
      expect(await landmarker.initialize(), isTrue);
      final still = _fivePoints(
        (await landmarker.analyseRgbRaw(
          rgbBytes: rgb,
          width: width,
          height: height,
        ))!,
        width,
        height,
      )!;

      Future<List<math.Point<double>>> frame(
        Map<String, Object?> request,
      ) async {
        final payload = await _landmarkerChannel
            .invokeMapMethod<String, Object?>('analyseFrame', request);
        expect(payload, isNotNull, reason: 'no face in ${request['format']}');
        return _fivePoints(payload!, width, height)!;
      }

      // iOS front camera: mirrored BGRA that the runtime un-mirrors.
      final mirrored = img.flipHorizontal(img.Image.from(image));
      final mirroredPoints = await frame(<String, Object?>{
        'width': width,
        'height': height,
        'format': 'bgra8888',
        'rotation_degrees': 0,
        'mirror_horizontal': true,
        'planes': [_bgraPlane(mirrored)],
      });

      // Sensor-oriented frame (Android): rotated 90 degrees counter-clockwise,
      // turned upright by a clockwise rotation of 90.
      final sideways = img.copyRotate(image, angle: 270);
      final rotatedPoints = await frame(<String, Object?>{
        'width': sideways.width,
        'height': sideways.height,
        'format': 'bgra8888',
        'rotation_degrees': 90,
        'mirror_horizontal': false,
        'planes': [_bgraPlane(sideways)],
      });

      // iOS bi-planar YUV (NV12, video range).
      final nv12 = _toNv12(rgb, width, height);
      final nv12Points = await frame(<String, Object?>{
        'width': width,
        'height': height,
        'format': 'yuv420',
        'rotation_degrees': 0,
        'mirror_horizontal': false,
        'planes': [
          <String, Object?>{
            'bytes': nv12.luma,
            'bytes_per_row': width,
            'bytes_per_pixel': 1,
            'width': width,
            'height': height,
          },
          <String, Object?>{
            'bytes': nv12.chroma,
            'bytes_per_row': width,
            'bytes_per_pixel': 2,
            'width': width ~/ 2,
            'height': height ~/ 2,
          },
        ],
      });

      for (final (name, points, tolerance) in [
        ('mirrored_bgra', mirroredPoints, 1.5),
        ('rotated_bgra', rotatedPoints, 1.5),
        ('nv12', nv12Points, 3.0),
      ]) {
        var worst = 0.0;
        for (var i = 0; i < 5; i++) {
          worst = math.max(worst, points[i].distanceTo(still[i]));
        }
        debugPrint('PARITY frame_$name worst_px=${worst.toStringAsFixed(2)}');
        expect(worst, lessThan(tolerance), reason: name);
      }
    },
  );

  testWidgets('full face pipeline matches the reference embedding', (
    tester,
  ) async {
    final pipeline = FaceEmbeddingPipeline();
    final result = await pipeline.processEncodedImage(
      base64Decode(NativeParityFixture.imagePngBase64),
    );
    expect(result, isNotNull, reason: pipeline.lastFailureReason);
    final cosine = _dot(result!.embedding, NativeParityFixture.imageEmbedding);
    debugPrint('PARITY pipeline_cosine=$cosine');
    // Landmarks differ slightly between landmark runtimes; the same face
    // must still embed almost identically (different people score < 0.4).
    expect(cosine, greaterThan(0.90));
  });

  testWidgets('YOLO finds the person like the reference', (tester) async {
    final bridge = OptimizedVisionRuntimeBridge();
    expect(await bridge.initialize(), isTrue);
    final fromRgb = await bridge.runRgbFrame(
      rgbBytes: rgb,
      width: width,
      height: height,
      tasks: const <String>['objects'],
    );
    expect(
      fromRgb?.available,
      isTrue,
      reason: '${fromRgb?.outputs['message']}',
    );
    final person = _bestPerson(fromRgb!.outputs);
    expect(person, isNotNull);
    final box = person!.box;
    debugPrint(
      'PARITY yolo_conf=${person.confidence.toStringAsFixed(4)} '
      'box=${box.map((v) => v.toStringAsFixed(4)).join(',')}',
    );
    expect(
      (person.confidence - NativeParityFixture.personConfidence).abs(),
      lessThan(0.03),
    );
    for (var i = 0; i < 4; i++) {
      expect(
        (box[i] - NativeParityFixture.personBox[i]).abs(),
        lessThan(0.03),
        reason: 'box[$i]',
      );
    }

    if (Platform.isWindows) return;
    // The live monitor sends camera planes; BGRA must decode to the same
    // pixels, so the detection is identical.
    final policy = <String, Object?>{
      ...bridge.policy.toJson(),
      ...?bridge.manifest?.toPolicyJson(bridge.policy),
    };
    final response = await _visionChannel.invokeMapMethod<String, Object?>(
      'runFrame',
      <String, Object?>{
        'policy': policy,
        'tasks': const <String>['objects'],
        'width': width,
        'height': height,
        'format': 'bgra8888',
        'planes': [_bgraPlane(image)],
      },
    );
    final fromBgra = _bestPerson(
      Map<String, Object?>.from(response?['outputs'] as Map? ?? const {}),
    );
    expect(fromBgra, isNotNull);
    expect((fromBgra!.confidence - person.confidence).abs(), lessThan(1e-4));
  });

  testWidgets('protected storage round-trips and is bound to its purpose', (
    tester,
  ) async {
    final support = await getApplicationSupportDirectory();
    final store = NativeProtectedLocalStore(
      Directory('${support.path}${Platform.pathSeparator}parity_test'),
    );
    const value = '{"template":"parity-secret-value"}';
    expect(
      await store.write('students/a/template.bin', value, purpose: 'template'),
      isTrue,
    );
    expect(
      await store.read('students/a/template.bin', purpose: 'template'),
      value,
    );
    // Bound to its purpose: the same file read for another purpose fails.
    expect(
      await store.read('students/a/template.bin', purpose: 'evidence'),
      isNull,
    );
    final files = await store.list('students/a');
    expect(files, hasLength(1));
    final raw = await File(
      '${support.path}${Platform.pathSeparator}parity_test'
      '${Platform.pathSeparator}students${Platform.pathSeparator}a'
      '${Platform.pathSeparator}template.bin',
    ).readAsBytes();
    expect(latin1.decode(raw).contains('parity-secret-value'), isFalse);
    await store.delete('students/a/template.bin');
  });

  testWidgets('iPad lockdown reports Guided Access', (tester) async {
    if (!Platform.isIOS) {
      markTestSkipped('Guided Access is iPad only.');
      return;
    }
    final readiness = await const ExamLockdownService().status();
    expect(readiness.supported, isTrue);
    expect(readiness.usesGuidedAccess, isTrue);
    // Nobody turns Guided Access on in CI.
    expect(readiness.lockTaskActive, isFalse);
  });
}

double _dot(List<double> a, List<double> b) {
  var sum = 0.0;
  for (var i = 0; i < a.length; i++) {
    sum += a[i] * b[i];
  }
  return sum;
}

List<math.Point<double>>? _fivePoints(
  Map<String, Object?> payload,
  int width,
  int height,
) {
  final raw = payload['face_landmarks'] ?? payload['landmarks'];
  if (raw is! List) return null;
  final points = <int, math.Point<double>>{};
  for (final item in raw) {
    if (item is! Map || item['name'] != null) continue;
    points[(item['index'] as num).toInt()] = math.Point<double>(
      (item['x'] as num).toDouble() * width,
      (item['y'] as num).toDouble() * height,
    );
  }
  return FaceAlignment.fivePoints(points);
}

/// One BGRA plane, as the iOS camera plugin streams it.
Map<String, Object?> _bgraPlane(img.Image frame) {
  return <String, Object?>{
    'bytes': frame.getBytes(order: img.ChannelOrder.bgra),
    'bytes_per_row': frame.width * 4,
    'bytes_per_pixel': 4,
    'width': frame.width,
    'height': frame.height,
  };
}

({Uint8List luma, Uint8List chroma}) _toNv12(
  Uint8List rgb,
  int width,
  int height,
) {
  final luma = Uint8List(width * height);
  final chroma = Uint8List(width * height ~/ 2);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final i = (y * width + x) * 3;
      final r = rgb[i], g = rgb[i + 1], b = rgb[i + 2];
      luma[y * width + x] = (16 + 0.256788 * r + 0.504129 * g + 0.097906 * b)
          .round()
          .clamp(0, 255);
    }
  }
  for (var y = 0; y < height; y += 2) {
    for (var x = 0; x < width; x += 2) {
      var r = 0.0, g = 0.0, b = 0.0;
      for (final (dx, dy) in [(0, 0), (1, 0), (0, 1), (1, 1)]) {
        final i = ((y + dy) * width + x + dx) * 3;
        r += rgb[i];
        g += rgb[i + 1];
        b += rgb[i + 2];
      }
      r /= 4;
      g /= 4;
      b /= 4;
      final o = (y ~/ 2) * width + x;
      chroma[o] = (128 - 0.148223 * r - 0.290993 * g + 0.439216 * b)
          .round()
          .clamp(0, 255);
      chroma[o + 1] = (128 + 0.439216 * r - 0.367788 * g - 0.071427 * b)
          .round()
          .clamp(0, 255);
    }
  }
  return (luma: luma, chroma: chroma);
}

({double confidence, List<double> box})? _bestPerson(
  Map<String, Object?> outputs,
) {
  final objects = outputs['objects'];
  if (objects is! List) return null;
  ({double confidence, List<double> box})? best;
  for (final item in objects.whereType<Map>()) {
    if (item['label'] != 'person') continue;
    final confidence = (item['confidence'] as num).toDouble();
    if (best != null && confidence <= best.confidence) continue;
    final box = Map<Object?, Object?>.from(item['box'] as Map);
    best = (
      confidence: confidence,
      box: [
        for (final key in ['x1', 'y1', 'x2', 'y2'])
          (box[key] as num).toDouble(),
      ],
    );
  }
  return best;
}

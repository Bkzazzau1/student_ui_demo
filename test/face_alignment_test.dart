import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:students_ui_demo/face_demo/face_alignment.dart';
import 'package:students_ui_demo/face_demo/native_face_embedding_runtime.dart';

/// Same formula as `procedural_rgb` in ai_runtime/face_identity_reference.py.
Uint8List proceduralRgb(int width, int height) {
  final bytes = Uint8List(width * height * 3);
  var offset = 0;
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      bytes[offset++] = (x * 7 + y * 3) % 256;
      bytes[offset++] = (x * 2 + y * 5 + 40) % 256;
      bytes[offset++] = (x * x + y * 11) % 256;
    }
  }
  return bytes;
}

void main() {
  final golden =
      jsonDecode(
            File(
              'ai_runtime/tests/fixtures/face_alignment_golden.json',
            ).readAsStringSync(),
          )
          as Map<String, dynamic>;

  test('the app and the school reference use the same preprocessing', () {
    expect(
      NativeFaceEmbeddingRuntime.preprocessingVersion,
      golden['preprocessing_version'],
    );
  });

  test('alignment matches the Python reference fixture', () {
    final width = golden['image_width'] as int;
    final height = golden['image_height'] as int;
    final points = (golden['points'] as List)
        .map(
          (point) => math.Point<double>(
            ((point as List)[0] as num).toDouble(),
            (point[1] as num).toDouble(),
          ),
        )
        .toList();
    final transform = FaceAlignment.similarityLeastSquares(
      points,
      FaceAlignment.arcFaceTemplate,
    )!;
    final matrix = (golden['matrix'] as List)
        .map((row) => (row as List).map((v) => (v as num).toDouble()).toList())
        .toList();
    expect(transform.a, closeTo(matrix[0][0], 1e-12));
    expect(transform.b, closeTo(matrix[1][0], 1e-12));
    expect(transform.tx, closeTo(matrix[0][2], 1e-9));
    expect(transform.ty, closeTo(matrix[1][2], 1e-9));

    final aligned = FaceAlignment.warpBilinear(
      proceduralRgb(width, height),
      width,
      height,
      transform,
    )!;
    final expected = base64Decode(golden['aligned_rgb_b64'] as String);
    expect(aligned.length, expected.length);
    var maxDiff = 0;
    var exact = 0;
    for (var i = 0; i < aligned.length; i++) {
      final diff = (aligned[i] - expected[i]).abs();
      maxDiff = math.max(maxDiff, diff);
      if (diff == 0) exact++;
    }
    // Same float64 arithmetic; allow a 1-level rounding tie difference.
    expect(maxDiff, lessThanOrEqualTo(1));
    expect(exact / aligned.length, greaterThan(0.999));
  });

  test('five points use eye-corner midpoints, nose tip and mouth corners', () {
    final points = <int, math.Point<double>>{
      33: const math.Point(10, 20),
      133: const math.Point(20, 20),
      362: const math.Point(40, 22),
      263: const math.Point(50, 22),
      1: const math.Point(30, 35),
      61: const math.Point(18, 50),
      291: const math.Point(42, 50),
    };
    expect(FaceAlignment.fivePoints(points), const <math.Point<double>>[
      math.Point(15, 20),
      math.Point(45, 22),
      math.Point(30, 35),
      math.Point(18, 50),
      math.Point(42, 50),
    ]);
    expect(FaceAlignment.fivePoints(<int, math.Point<double>>{}), isNull);
  });

  test('the template maps onto itself', () {
    final transform = FaceAlignment.similarityLeastSquares(
      FaceAlignment.arcFaceTemplate,
      FaceAlignment.arcFaceTemplate,
    )!;
    expect(transform.a, closeTo(1, 1e-12));
    expect(transform.b, closeTo(0, 1e-12));
    expect(transform.tx, closeTo(0, 1e-9));
    expect(transform.ty, closeTo(0, 1e-9));
  });
}
